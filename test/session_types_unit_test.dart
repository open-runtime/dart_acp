// Unit tests for ACP session types module

import 'package:dart_acp/dart_acp.dart';
import 'package:test/test.dart';

void main() {
  group('SessionInfo', () {
    test('creates from required fields', () {
      const info = SessionInfo(
        sessionId: 'sess_123',
        cwd: '/home/user/project',
      );
      expect(info.sessionId, 'sess_123');
      expect(info.cwd, '/home/user/project');
      expect(info.title, isNull);
      expect(info.updatedAt, isNull);
      expect(info.meta, isNull);
    });

    test('creates with all fields', () {
      final now = DateTime.now();
      final info = SessionInfo(
        sessionId: 'sess_456',
        cwd: '/work',
        title: 'My Session',
        updatedAt: now,
        meta: {'custom': 'data'},
      );
      expect(info.sessionId, 'sess_456');
      expect(info.title, 'My Session');
      expect(info.updatedAt, now);
      expect(info.meta?['custom'], 'data');
    });

    test('fromJson parses required fields', () {
      final info = SessionInfo.fromJson({
        'sessionId': 'sess_789',
        'cwd': '/project',
      });
      expect(info.sessionId, 'sess_789');
      expect(info.cwd, '/project');
    });

    test('fromJson parses all fields', () {
      final info = SessionInfo.fromJson({
        'sessionId': 'sess_abc',
        'cwd': '/work',
        'title': 'Test Session',
        'updatedAt': '2025-01-15T10:30:00.000Z',
        '_meta': {'key': 'value'},
      });
      expect(info.title, 'Test Session');
      expect(info.updatedAt, isNotNull);
      expect(info.meta?['key'], 'value');
    });

    test('toJson produces correct output', () {
      final now = DateTime.utc(2025, 1, 15, 10, 30);
      final info = SessionInfo(
        sessionId: 'sess_xyz',
        cwd: '/work',
        title: 'My Title',
        updatedAt: now,
        meta: {'foo': 'bar'},
      );
      final json = info.toJson();
      expect(json['sessionId'], 'sess_xyz');
      expect(json['cwd'], '/work');
      expect(json['title'], 'My Title');
      expect(json['updatedAt'], now.toIso8601String());
      expect(json['_meta'], {'foo': 'bar'});
    });

    test('toJson omits null fields', () {
      const info = SessionInfo(sessionId: 'sess_1', cwd: '/');
      final json = info.toJson();
      expect(json.containsKey('title'), isFalse);
      expect(json.containsKey('updatedAt'), isFalse);
      expect(json.containsKey('_meta'), isFalse);
    });
  });

  group('SessionListResult', () {
    test('creates empty result', () {
      const result = SessionListResult(sessions: []);
      expect(result.sessions, isEmpty);
      expect(result.nextCursor, isNull);
      expect(result.hasMore, isFalse);
    });

    test('creates with sessions and cursor', () {
      const result = SessionListResult(
        sessions: [
          SessionInfo(sessionId: 's1', cwd: '/a'),
          SessionInfo(sessionId: 's2', cwd: '/b'),
        ],
        nextCursor: 'cursor123',
      );
      expect(result.sessions.length, 2);
      expect(result.nextCursor, 'cursor123');
      expect(result.hasMore, isTrue);
    });

    test('fromJson parses sessions', () {
      final result = SessionListResult.fromJson({
        'sessions': [
          {'sessionId': 's1', 'cwd': '/a'},
          {'sessionId': 's2', 'cwd': '/b'},
        ],
      });
      expect(result.sessions.length, 2);
      expect(result.sessions[0].sessionId, 's1');
      expect(result.sessions[1].sessionId, 's2');
    });

    test('fromJson handles empty sessions', () {
      final result = SessionListResult.fromJson({});
      expect(result.sessions, isEmpty);
      expect(result.nextCursor, isNull);
    });

    test('fromJson parses cursor', () {
      final result = SessionListResult.fromJson({
        'sessions': [],
        'nextCursor': 'page2token',
      });
      expect(result.nextCursor, 'page2token');
      expect(result.hasMore, isTrue);
    });
  });

  group('ConfigOption', () {
    test('creates with required fields', () {
      const option = ConfigOption(
        id: 'model',
        name: 'Model',
        type: 'select',
        currentValue: 'gpt-4',
        options: [],
      );
      expect(option.id, 'model');
      expect(option.name, 'Model');
      expect(option.type, 'select');
      expect(option.currentValue, 'gpt-4');
    });

    test('fromJson parses all fields', () {
      final option = ConfigOption.fromJson({
        'id': 'lang',
        'name': 'Language',
        'type': 'select',
        'currentValue': 'en',
        'description': 'Choose language',
        'group': 'preferences',
        'options': [
          {'value': 'en', 'name': 'English'},
          {'value': 'es', 'name': 'Spanish', 'description': 'Espanol'},
        ],
      });
      expect(option.id, 'lang');
      expect(option.description, 'Choose language');
      expect(option.group, 'preferences');
      expect(option.options.length, 2);
      expect(option.options[0].value, 'en');
      expect(option.options[1].description, 'Espanol');
    });

    test('toJson produces correct output', () {
      const option = ConfigOption(
        id: 'test',
        name: 'Test',
        type: 'select',
        currentValue: 'a',
        description: 'A test option',
        group: 'testing',
        options: [ConfigOptionChoice(value: 'a', name: 'Option A')],
      );
      final json = option.toJson();
      expect(json['id'], 'test');
      expect(json['description'], 'A test option');
      expect(json['group'], 'testing');
      expect((json['options'] as List).length, 1);
    });
  });

  group('ConfigOptionChoice', () {
    test('creates with required fields', () {
      const choice = ConfigOptionChoice(value: 'v1', name: 'Value 1');
      expect(choice.value, 'v1');
      expect(choice.name, 'Value 1');
      expect(choice.description, isNull);
    });

    test('fromJson parses all fields', () {
      final choice = ConfigOptionChoice.fromJson({
        'value': 'opt1',
        'name': 'Option 1',
        'description': 'First option',
      });
      expect(choice.value, 'opt1');
      expect(choice.name, 'Option 1');
      expect(choice.description, 'First option');
    });

    test('toJson omits null description', () {
      const choice = ConfigOptionChoice(value: 'x', name: 'X');
      final json = choice.toJson();
      expect(json.containsKey('description'), isFalse);
    });
  });

  group('SessionResult', () {
    test('creates with session ID only', () {
      const result = SessionResult(sessionId: 'new_session');
      expect(result.sessionId, 'new_session');
      expect(result.configOptions, isNull);
      expect(result.meta, isNull);
    });

    test('fromJson parses all fields', () {
      final result = SessionResult.fromJson({
        'sessionId': 'sess_result',
        'configOptions': [
          {
            'id': 'model',
            'name': 'Model',
            'type': 'select',
            'currentValue': 'gpt-4',
            'options': [],
          },
        ],
        '_meta': {'agent': 'test'},
      });
      expect(result.sessionId, 'sess_result');
      expect(result.configOptions?.length, 1);
      expect(result.configOptions?[0].id, 'model');
      expect(result.meta?['agent'], 'test');
    });

    test('fromJson handles missing optional fields', () {
      final result = SessionResult.fromJson({'sessionId': 'minimal'});
      expect(result.sessionId, 'minimal');
      expect(result.configOptions, isNull);
      expect(result.meta, isNull);
    });
  });

  group('SessionCapabilities', () {
    test('creates with defaults', () {
      const caps = SessionCapabilities();
      expect(caps.list, isFalse);
      expect(caps.resume, isFalse);
      expect(caps.fork, isFalse);
      expect(caps.configOptions, isFalse);
    });

    test('fromJson handles null', () {
      final caps = SessionCapabilities.fromJson(null);
      expect(caps.list, isFalse);
      expect(caps.resume, isFalse);
    });

    test('fromJson parses sessionCapabilities format', () {
      final caps = SessionCapabilities.fromJson({
        'sessionCapabilities': {'list': {}, 'fork': {}},
      });
      expect(caps.list, isTrue);
      expect(caps.fork, isTrue);
      expect(caps.resume, isFalse);
    });

    test('fromJson parses session format', () {
      final caps = SessionCapabilities.fromJson({
        'session': {'list': {}, 'resume': {}, 'configOptions': {}},
      });
      expect(caps.list, isTrue);
      expect(caps.resume, isTrue);
      expect(caps.fork, isFalse);
      expect(caps.configOptions, isTrue);
    });

    test('toString produces readable output', () {
      const caps = SessionCapabilities(list: true, fork: true);
      final str = caps.toString();
      expect(str, contains('list: true'));
      expect(str, contains('fork: true'));
      expect(str, contains('resume: false'));
    });
  });
}
