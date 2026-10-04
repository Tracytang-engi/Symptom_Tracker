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

  BackupService(this.storage);

  bool get isConfigured => backupApiBaseUrl.isNotEmpty;

  Uri _uri(String path) => Uri.parse('$backupApiBaseUrl$path');

  Future<String> register(String email, String password) async {
    return _auth('/auth/register', email, password);
  }

  Future<String> login(String email, String password) async {
    return _auth('/auth/login', email, password);
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
    final body = jsonEncode(await _buildPayload());
    final started = DateTime.now();
    onStep?.call('Waking the server…');
    unawaited(_wake());

    await _waitUntil(started, const Duration(minutes: 1));
    onStep?.call('Uploading…');
    final first = await _putBackup(body, timeout: const Duration(seconds: 50));
    if (first == _PutResult.fatal) {
      throw BackupException('Login expired. Enter your password again.');
    }

    await _waitUntil(started, const Duration(minutes: 2));
    onStep?.call('Uploading again…');
    final second = await _putBackup(body, timeout: const Duration(minutes: 3));
    if (first == _PutResult.ok || second == _PutResult.ok) return;
    if (second == _PutResult.fatal) {
      throw BackupException('Login expired. Enter your password again.');
    }
    throw BackupException('The backup server did not wake up. Try again.');
  }

  Future<void> _wake() async {
    try {
      await http.get(_uri('/health')).timeout(const Duration(seconds: 30));
    } catch (_) {}
  }

  Future<void> _waitUntil(DateTime started, Duration mark) async {
    final left = mark - DateTime.now().difference(started);
    if (left > Duration.zero) await Future<void>.delayed(left);
  }

  Future<_PutResult> _putBackup(String body, {required Duration timeout}) async {
    final token = storage.accountToken;
    if (token == null || token.isEmpty) return _PutResult.fatal;
    try {
      final response = await http
          .put(
            _uri('/backup'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: body,
          )
          .timeout(timeout);
      if (response.statusCode == 401) return _PutResult.fatal;
      if (response.statusCode != 200) return _PutResult.retry;
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['ok'] == true) return _PutResult.ok;
      return _PutResult.retry;
    } on TimeoutException {
      return _PutResult.retry;
    } on SocketException {
      return _PutResult.retry;
    } on http.ClientException {
      return _PutResult.retry;
    } on FormatException {
      return _PutResult.retry;
    }
  }

  /// 找回前必须重新提交密码。不使用已经保存的登录令牌。
  Future<void> restore({required String email, required String password}) async {
    final token = await login(email, password);
    final response = await http.get(
      _uri('/backup'),
      headers: {'Authorization': 'Bearer $token'},
    );
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
    final response = await http.post(
      _uri(path),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email.trim(), 'password': password}),
    );
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
      if (decoded is Map && decoded['error'] is String) return decoded['error'] as String;
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
        final ids = (map['voiceFileIds'] as List?)?.whereType<String>().toList() ?? [];
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
