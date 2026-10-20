import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../backup_config.dart';
import '../models/pain_event.dart';
import '../models/symptom_profile.dart';
import '../models/tag.dart';
import 'storage_service.dart';

class BackupException implements Exception {
  final String message;
  BackupException(this.message);
  @override
  String toString() => message;
}

enum _PutResult { ok, retry, fatal }

/// 只在用户主动备份或找回时访问服务器。打开应用不会从这里拉数据。
class BackupService {
  final StorageService storage;
  final http.Client Function() _clientFactory;
  final Duration firstUploadAt;
  final Duration secondUploadAt;
  final Duration firstTimeout;
  final Duration secondTimeout;
  String _lastUploadError = 'The server did not confirm the backup.';

  BackupService(
    this.storage, {
    http.Client Function()? clientFactory,
    this.firstUploadAt = const Duration(minutes: 1),
    this.secondUploadAt = const Duration(minutes: 2),
    this.firstTimeout = const Duration(seconds: 50),
    this.secondTimeout = const Duration(minutes: 3),
  }) : _clientFactory = clientFactory ?? http.Client.new;

  // Closing the per-request client also aborts an HTTP request after timeout.
  Future<http.Response> _request(
    Future<http.Response> Function(http.Client client) send,
    Duration timeout,
  ) async {
    final client = _clientFactory();
    try {
      return await send(client).timeout(timeout);
    } on TimeoutException {
      throw BackupException(
          'Server request timed out. Check your connection and try again.');
    } finally {
      client.close();
    }
  }

  bool get isConfigured => backupApiBaseUrl.isNotEmpty;

  Uri _uri(String path) => Uri.parse('$backupApiBaseUrl$path');

  Future<String> register(String email, String password) async {
    return _auth('/auth/register', email, password);
  }

  Future<String> login(String email, String password) async {
    return _auth('/auth/login', email, password);
  }

  Future<void> deleteAccount() async {
    _requireConfigured();
    final token = storage.accountToken;
    if (token == null || token.isEmpty) {
      throw BackupException('Log in before deleting your account.');
    }

    final response = await _request(
        (client) => client.delete(
              _uri('/account'),
              headers: {'Authorization': 'Bearer $token'},
            ),
        const Duration(minutes: 1));
    if (response.statusCode != 200) {
      throw BackupException(_errorMessage(response));
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['ok'] != true) {
      throw BackupException('The server did not confirm account deletion.');
    }
  }

  Future<void> upload() async {
    await uploadAfterWake();
  }

  /// Wakes a sleeping free instance, then uploads at 1 minute and again at 2 minutes.
  Future<void> uploadAfterWake({void Function(String step)? onStep}) async {
    _requireConfigured();
    final token = storage.accountToken;
    if (token == null || token.isEmpty) {
      throw BackupException('Log in before backing up.');
    }

    onStep?.call('Preparing the backup…');
    final body =
        jsonEncode(await _buildPayload().timeout(const Duration(seconds: 30)));
    final started = Stopwatch()..start();
    var wakeStatus = 'Waking the server';
    unawaited(_wake().then((status) => wakeStatus = status));

    await _waitUntil(
        started, firstUploadAt, onStep, () => '$wakeStatus. Upload 1/2');
    final first =
        await _uploadWithProgress(body, token, 1, firstTimeout, onStep);
    if (first == _PutResult.fatal) {
      throw BackupException('Login expired. Enter your password again.');
    }

    await _waitUntil(
        started,
        secondUploadAt,
        onStep,
        () => first == _PutResult.ok
            ? 'Backup saved on attempt 1. Scheduled upload 2/2'
            : 'Attempt 1 failed: $_lastUploadError Upload 2/2');
    final second =
        await _uploadWithProgress(body, token, 2, secondTimeout, onStep);
    if (second == _PutResult.ok) {
      onStep?.call('Backup saved. Server confirmed receipt.');
      return;
    }
    if (first == _PutResult.ok) {
      onStep?.call(
          'Backup saved on attempt 1. The second upload was not confirmed.');
      return;
    }
    if (second == _PutResult.fatal) {
      throw BackupException('Login expired. Enter your password again.');
    }
    throw BackupException(
        'Backup failed after 2 attempts. $_lastUploadError Your local records are unchanged.');
  }

  Future<String> _wake() async {
    try {
      final response = await _request(
          (client) => client.get(_uri('/health')), const Duration(seconds: 30));
      return response.statusCode == 200
          ? 'Server is awake'
          : 'Wake-up returned HTTP ${response.statusCode}';
    } catch (_) {
      return 'Wake-up not confirmed; upload will still be attempted';
    }
  }

  Future<void> _waitUntil(Stopwatch started, Duration mark,
      void Function(String)? onStep, String Function() label) async {
    while (started.elapsed < mark) {
      final left = mark - started.elapsed;
      onStep?.call('${label()} in ${(left.inMilliseconds / 1000).ceil()} s.');
      await Future<void>.delayed(left < const Duration(seconds: 1)
          ? left
          : const Duration(seconds: 1));
    }
  }

  Future<_PutResult> _uploadWithProgress(String body, String token, int attempt,
      Duration timeout, void Function(String)? onStep) async {
    final watch = Stopwatch()..start();
    void report() => onStep?.call(
        'Uploading $attempt/2 - ${watch.elapsed.inSeconds} s elapsed '
        '(timeout ${timeout.inSeconds} s). Waiting for server confirmation.');
    report();
    final ticker = Timer.periodic(const Duration(seconds: 1), (_) => report());
    try {
      return await _putBackup(body, token, timeout: timeout);
    } finally {
      ticker.cancel();
      watch.stop();
    }
  }

  Future<_PutResult> _putBackup(String body, String token,
      {required Duration timeout}) async {
    try {
      final response = await _request(
          (client) => client.put(
                _uri('/backup'),
                headers: {
                  'Authorization': 'Bearer $token',
                  'Content-Type': 'application/json',
                },
                body: body,
              ),
          timeout);
      if (response.statusCode == 401) return _PutResult.fatal;
      if (response.statusCode != 200) {
        _lastUploadError = response.statusCode == 413
            ? 'Backup is too large for the server.'
            : 'Server returned HTTP ${response.statusCode}.';
        return _PutResult.retry;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['ok'] == true) return _PutResult.ok;
      _lastUploadError = 'Server did not confirm receipt.';
      return _PutResult.retry;
    } on BackupException catch (error) {
      _lastUploadError = error.message;
      return _PutResult.retry;
    } on SocketException {
      _lastUploadError = 'Network connection failed.';
      return _PutResult.retry;
    } on http.ClientException {
      _lastUploadError = 'Network connection failed.';
      return _PutResult.retry;
    } on FormatException {
      _lastUploadError = 'Server returned an invalid response.';
      return _PutResult.retry;
    }
  }

  /// 找回前必须重新提交密码。不使用已经保存的登录令牌。
  Future<void> restore(
      {required String email, required String password}) async {
    final token = await login(email, password);
    final response = await _request(
        (client) => client.get(
              _uri('/backup'),
              headers: {'Authorization': 'Bearer $token'},
            ),
        const Duration(minutes: 3));
    if (response.statusCode == 404) {
      throw BackupException('No backup stored for this account.');
    }
    if (response.statusCode != 200) {
      throw BackupException(_errorMessage(response));
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) throw BackupException('Backup was empty.');
    await _applyPayload(Map<String, dynamic>.from(decoded));
  }

  Future<String> _auth(String path, String email, String password) async {
    _requireConfigured();
    final response = await _request(
        (client) => client.post(
              _uri(path),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'email': email.trim(), 'password': password}),
            ),
        const Duration(minutes: 2));
    if (response.statusCode != 200) {
      throw BackupException(_errorMessage(response));
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['token'] is! String) {
      throw BackupException('Server did not return a login token.');
    }
    final token = decoded['token'] as String;
    await storage.saveAccount(email: email.trim(), token: token);
    return token;
  }

  void _requireConfigured() {
    if (!isConfigured) {
      throw BackupException(
        'Backup server is not configured. Set backupApiBaseUrl in backup_config.dart.',
      );
    }
  }

  String _errorMessage(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['error'] is String) {
        return decoded['error'] as String;
      }
    } catch (_) {}
    return 'Server error (${response.statusCode}).';
  }

  Future<Map<String, dynamic>> _buildPayload() async {
    final files = <Map<String, String>>[];
    final events = <Map<String, dynamic>>[];
    for (final event in storage.getAllEvents()) {
      final json = event.toJson();
      final storedIds = <String>[];
      for (final path in event.voiceNotePaths) {
        final file = File(path);
        if (!await file.exists()) continue;
        final id = const Uuid().v4();
        files.add({
          'id': id,
          'name': path.split(RegExp(r'[\\/]')).last,
          'data': base64Encode(await file.readAsBytes()),
        });
        storedIds.add(id);
      }
      json['voiceFileIds'] = storedIds;
      json['voiceNotePaths'] = <String>[];
      events.add(json);
    }
    return {
      'version': 1,
      'events': events,
      'profiles': storage.getAllProfiles().map((p) => p.toJson()).toList(),
      'tags': storage.getAllTags().map((t) => t.toJson()).toList(),
      'files': files,
    };
  }

  Future<void> _applyPayload(Map<String, dynamic> payload) async {
    final fileBytes = <String, List<int>>{};
    final fileNames = <String, String>{};
    final files = payload['files'];
    if (files is List) {
      for (final raw in files) {
        if (raw is! Map) continue;
        final id = raw['id'] as String?;
        final data = raw['data'] as String?;
        if (id == null || data == null) continue;
        fileBytes[id] = base64Decode(data);
        fileNames[id] = raw['name'] as String? ?? '$id.m4a';
      }
    }

    final dir = await getApplicationDocumentsDirectory();
    final voiceDir = Directory('${dir.path}/voice_notes');
    if (!await voiceDir.exists()) await voiceDir.create(recursive: true);

    final events = payload['events'];
    if (events is List) {
      for (final raw in events) {
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        final ids =
            (map['voiceFileIds'] as List?)?.whereType<String>().toList() ?? [];
        final paths = <String>[];
        for (final id in ids) {
          final bytes = fileBytes[id];
          if (bytes == null) continue;
          final path = '${voiceDir.path}/${fileNames[id]}';
          await File(path).writeAsBytes(bytes, flush: true);
          paths.add(path);
        }
        map['voiceNotePaths'] = paths;
        await storage.saveEvent(PainEvent.fromJson(map));
      }
    }

    final profiles = payload['profiles'];
    if (profiles is List) {
      var count = storage.getAllProfiles().length;
      for (final raw in profiles) {
        if (raw is! Map) continue;
        final profile = SymptomProfile.fromJson(raw);
        final exists = storage.getAllProfiles().any((p) => p.id == profile.id);
        if (!exists && count >= 10) continue;
        await storage.saveProfile(profile);
        if (!exists) count++;
      }
    }

    final tags = payload['tags'];
    if (tags is List && tags.isNotEmpty) {
      await storage.saveAllTags(
        tags.whereType<Map>().map((m) => Tag.fromJson(m)).toList(),
      );
    }
  }
}
