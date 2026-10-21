import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:symptom_tracker_app/models/pain_event.dart';
import 'package:symptom_tracker_app/models/symptom_profile.dart';
import 'package:symptom_tracker_app/models/tag.dart';
import 'package:symptom_tracker_app/services/backup_service.dart';
import 'package:symptom_tracker_app/services/storage_service.dart';

class TestStorage extends StorageService {
  String? token = 'test-token';
  @override
  String? get accountToken => token;
  @override
  List<PainEvent> getAllEvents() => [];
  @override
  List<SymptomProfile> getAllProfiles() => [];
  @override
  List<Tag> getAllTags() => [];
}

class TrackingClient extends MockClient {
  bool closed = false;
  TrackingClient(super.handler);
  @override
  void close() {
    closed = true;
    super.close();
  }
}

void main() {
  for (final scenario in [
    'success',
    'retry',
    'first-only',
    'cold-start',
    'cold-timeout',
    'unauthorized',
    'server-error',
    'timeout',
    'invalid-response',
    'too-large'
  ]) {
    test('Backup: $scenario reports progress and terminates', () async {
      final steps = <String>[];
      final clients = <TrackingClient>[];
      final payloads = <String>[];
      var uploads = 0;
      var healthChecks = 0;
      final service = BackupService(
        TestStorage(),
        wakeTimeout: const Duration(milliseconds: 100),
        healthTimeout: const Duration(milliseconds: 20),
        retryDelay: const Duration(milliseconds: 1),
        firstTimeout: const Duration(milliseconds: 20),
        secondTimeout: const Duration(milliseconds: 20),
        clientFactory: () {
          final client = TrackingClient((request) async {
            if (request.url.path == '/health') {
              healthChecks++;
              if (scenario == 'cold-timeout' && healthChecks == 1) {
                return Completer<http.Response>().future;
              }
              if (scenario == 'cold-start' && healthChecks <= 2) {
                return http.Response('{}', 503);
              }
              return http.Response('{"ok":true}', 200);
            }
            expect(request.method, 'PUT');
            expect(request.headers['Authorization'], 'Bearer test-token');
            payloads.add(request.body);
            uploads++;
            if (scenario == 'timeout') return Completer<http.Response>().future;
            if (scenario == 'unauthorized') return http.Response('{}', 401);
            if (scenario == 'too-large') return http.Response('', 413);
            if (scenario == 'invalid-response') {
              return http.Response('not JSON', 200);
            }
            if (scenario == 'server-error' ||
                (scenario == 'retry' && uploads == 1) ||
                (scenario == 'first-only' && uploads != 2)) {
              return http.Response('{}', 503);
            }
            return http.Response('{"ok":true}', 200);
          });
          clients.add(client);
          return client;
        },
      );
      final operation = service.uploadAfterWake(onStep: steps.add);
      if (['success', 'retry', 'first-only', 'cold-start', 'cold-timeout']
          .contains(scenario)) {
        await operation;
        expect(steps.last, startsWith('Backup saved'));
      } else {
        final reason = switch (scenario) {
          'unauthorized' => 'Login expired',
          'server-error' => 'HTTP 503',
          'timeout' => 'timed out',
          'too-large' => 'too large',
          _ => 'invalid response',
        };
        await expectLater(
            operation,
            throwsA(isA<BackupException>()
                .having((e) => e.message, 'message', contains(reason))));
      }
      final expected =
          ['success', 'unauthorized', 'too-large'].contains(scenario)
              ? 1
              : scenario.startsWith('cold-')
                  ? 2
                  : 3;
      expect(uploads, expected);
      if (scenario == 'success') expect(healthChecks, 1);
      if (scenario == 'cold-start') expect(healthChecks, 3);
      if (uploads > 1) {
        expect(steps.any((s) => s.contains('Uploading recovery 2/2')), isTrue);
        expect(payloads.toSet().length, 1);
      }
      expect(jsonDecode(payloads.first)['events'], isEmpty);
      expect(clients.every((client) => client.closed), isTrue);
    });
  }

  test('Missing login fails before contacting server', () async {
    final storage = TestStorage()..token = null;
    final service = BackupService(storage,
        clientFactory: () => throw StateError('Network not expected'));
    await expectLater(service.upload(), throwsA(isA<BackupException>()));
  });

  for (final hanging in [false, true]) {
    test('Unavailable server stops without uploading (hanging: $hanging)',
        () async {
      final clients = <TrackingClient>[];
      final service = BackupService(TestStorage(),
          wakeTimeout: const Duration(milliseconds: 30),
          healthTimeout: const Duration(milliseconds: 10),
          retryDelay: const Duration(milliseconds: 1), clientFactory: () {
        final client = TrackingClient((request) async {
          expect(request.url.path, '/health');
          if (hanging) return Completer<http.Response>().future;
          return http.Response('<html>Starting...</html>', 200);
        });
        clients.add(client);
        return client;
      });
      await expectLater(
          service.upload(),
          throwsA(isA<BackupException>().having(
              (e) => e.message, 'message', contains('did not become ready'))));
      expect(clients.every((client) => client.closed), isTrue);
    });
  }
}
