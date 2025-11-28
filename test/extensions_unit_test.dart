// Unit tests for ACP extensions module

// ignore_for_file: avoid_dynamic_calls

import 'package:dart_acp/dart_acp.dart';
import 'package:dart_acp/src/session/session_manager.dart';
import 'package:test/test.dart';

void main() {
  group('Extension method naming', () {
    test('isValidExtensionMethod accepts underscore prefix', () {
      expect(isValidExtensionMethod('_test'), isTrue);
      expect(isValidExtensionMethod('_zed.dev/workspace'), isTrue);
      expect(isValidExtensionMethod('_mycompany.com/custom'), isTrue);
    });

    test('isValidExtensionMethod rejects non-underscore prefix', () {
      expect(isValidExtensionMethod('test'), isFalse);
      expect(isValidExtensionMethod('session/new'), isFalse);
      expect(isValidExtensionMethod(''), isFalse);
    });

    test('extensionMethodName creates proper format', () {
      expect(
        extensionMethodName('zed.dev', 'workspace/buffers'),
        '_zed.dev/workspace/buffers',
      );
      expect(
        extensionMethodName('mycompany.com', 'custom'),
        '_mycompany.com/custom',
      );
    });
  });

  group('ExtensionMeta', () {
    test('creates empty metadata', () {
      const meta = ExtensionMeta();
      expect(meta.isEmpty, isTrue);
      expect(meta.isNotEmpty, isFalse);
    });

    test('creates from map', () {
      const meta = ExtensionMeta({'zed.dev/debug': true, 'version': '1.0'});
      expect(meta.isEmpty, isFalse);
      expect(meta['zed.dev/debug'], isTrue);
      expect(meta['version'], '1.0');
    });

    test('fromJson handles null', () {
      final meta = ExtensionMeta.fromJson(null);
      expect(meta.isEmpty, isTrue);
    });

    test('fromJson parses map', () {
      final meta = ExtensionMeta.fromJson(const {'key': 'value'});
      expect(meta['key'], 'value');
    });

    test('get returns typed value with default', () {
      const meta = ExtensionMeta({'count': 42, 'name': 'test'});
      expect(meta.get<int>('count', 0), 42);
      expect(meta.get<String>('name', ''), 'test');
      expect(meta.get<int>('missing', 99), 99);
      expect(meta.get<int>('name', 0), 0); // wrong type returns default
    });

    test('getVendorData returns nested map', () {
      const meta = ExtensionMeta({
        'zed.dev': {'workspace': true, 'version': '2.0'},
      });
      final vendor = meta.getVendorData('zed.dev');
      expect(vendor, isNotNull);
      expect(vendor!['workspace'], isTrue);
      expect(vendor['version'], '2.0');
    });

    test('getVendorData returns null for non-map', () {
      const meta = ExtensionMeta({'scalar': 'value'});
      expect(meta.getVendorData('scalar'), isNull);
      expect(meta.getVendorData('missing'), isNull);
    });

    test('copyWith adds entries', () {
      const meta = ExtensionMeta({'a': 1});
      final updated = meta.copyWith({'b': 2});
      expect(updated['a'], 1);
      expect(updated['b'], 2);
    });

    test('toJson returns immutable map', () {
      const meta = ExtensionMeta({'key': 'value'});
      final json = meta.toJson();
      expect(json['key'], 'value');
      expect(() => json['new'] = 'test', throwsUnsupportedError);
    });

    test('containsKey works correctly', () {
      const meta = ExtensionMeta({'exists': true});
      expect(meta.containsKey('exists'), isTrue);
      expect(meta.containsKey('missing'), isFalse);
    });

    test('keys and entries iterate correctly', () {
      const meta = ExtensionMeta({'a': 1, 'b': 2});
      expect(meta.keys.toList(), containsAll(['a', 'b']));
      expect(meta.entries.length, 2);
    });

    test('equality works', () {
      const meta1 = ExtensionMeta({'a': 1, 'b': 2});
      const meta2 = ExtensionMeta({'a': 1, 'b': 2});
      const meta3 = ExtensionMeta({'a': 1});
      expect(meta1, equals(meta2));
      expect(meta1, isNot(equals(meta3)));
    });
  });

  group('ExtensionCapabilities', () {
    test('creates empty capabilities', () {
      const caps = ExtensionCapabilities();
      expect(caps.isEmpty, isTrue);
      expect(caps.isNotEmpty, isFalse);
    });

    test('hasVendor checks vendor existence', () {
      const caps = ExtensionCapabilities({
        'zed.dev': {'workspace': true},
      });
      expect(caps.hasVendor('zed.dev'), isTrue);
      expect(caps.hasVendor('other.com'), isFalse);
    });

    test('getVendorCapabilities returns vendor map', () {
      const caps = ExtensionCapabilities({
        'zed.dev': {'workspace': true, 'files': false},
      });
      final vendor = caps.getVendorCapabilities('zed.dev');
      expect(vendor, isNotNull);
      expect(vendor!['workspace'], isTrue);
      expect(vendor['files'], isFalse);
    });

    test('supports checks capability support', () {
      const caps = ExtensionCapabilities({
        'zed.dev': {'workspace': true, 'disabled': false, 'version': '1.0'},
      });
      expect(caps.supports('zed.dev', 'workspace'), isTrue);
      expect(caps.supports('zed.dev', 'disabled'), isFalse);
      expect(caps.supports('zed.dev', 'version'), isTrue); // non-bool truthy
      expect(caps.supports('zed.dev', 'missing'), isFalse);
      expect(caps.supports('other.com', 'workspace'), isFalse);
    });

    test('getValue gets typed capability value', () {
      const caps = ExtensionCapabilities({
        'zed.dev': {'count': 42, 'name': 'test'},
      });
      expect(caps.getValue<int>('zed.dev', 'count'), 42);
      expect(caps.getValue<String>('zed.dev', 'name'), 'test');
      expect(caps.getValue<int>('zed.dev', 'name'), isNull); // wrong type
      expect(caps.getValue<int>('zed.dev', 'missing'), isNull);
      expect(caps.getValue<int>('other.com', 'count'), isNull);
    });

    test('vendors lists all vendor domains', () {
      const caps = ExtensionCapabilities({'zed.dev': {}, 'mycompany.com': {}});
      expect(caps.vendors.toList(), containsAll(['zed.dev', 'mycompany.com']));
    });

    test('toJson returns immutable map', () {
      const caps = ExtensionCapabilities({'zed.dev': {}});
      final json = caps.toJson();
      expect(() => json['new'] = {}, throwsUnsupportedError);
    });

    test('fromJson handles null', () {
      final caps = ExtensionCapabilities.fromJson(null);
      expect(caps.isEmpty, isTrue);
    });
  });

  group('ExtensionResponse', () {
    test('wraps raw result', () {
      const response = ExtensionResponse({'data': 'test', 'count': 42});
      expect(response.raw['data'], 'test');
      expect(response['count'], 42);
    });

    test('get returns typed value with default', () {
      const response = ExtensionResponse({'count': 42});
      expect(response.get<int>('count', 0), 42);
      expect(response.get<int>('missing', 99), 99);
    });

    test('containsKey works', () {
      const response = ExtensionResponse({'exists': true});
      expect(response.containsKey('exists'), isTrue);
      expect(response.containsKey('missing'), isFalse);
    });

    test('meta extracts _meta field', () {
      const response = ExtensionResponse({
        'data': 'test',
        '_meta': {'debug': true},
      });
      final meta = response.meta;
      expect(meta, isNotNull);
      expect(meta!['debug'], isTrue);
    });

    test('meta returns null when not present', () {
      const response = ExtensionResponse({'data': 'test'});
      expect(response.meta, isNull);
    });
  });

  group('ExtensionParams', () {
    test('creates empty params', () {
      final params = ExtensionParams();
      expect(params.toJson(), isEmpty);
    });

    test('creates from initial map', () {
      final params = ExtensionParams({'key': 'value'});
      expect(params.toJson()['key'], 'value');
    });

    test('set adds single value', () {
      final params = ExtensionParams().set('key', 'value');
      expect(params.toJson()['key'], 'value');
    });

    test('setAll adds multiple values', () {
      final params = ExtensionParams().setAll({'a': 1, 'b': 2});
      final json = params.toJson();
      expect(json['a'], 1);
      expect(json['b'], 2);
    });

    test('withMeta adds _meta field', () {
      final params = ExtensionParams({
        'data': 'test',
      }).withMeta(const ExtensionMeta({'debug': true}));
      final json = params.toJson();
      expect(json['data'], 'test');
      expect(json['_meta'], {'debug': true});
    });

    test('withMeta skips empty meta', () {
      final params = ExtensionParams({
        'data': 'test',
      }).withMeta(const ExtensionMeta());
      expect(params.toJson().containsKey('_meta'), isFalse);
    });

    test('chaining works', () {
      final params = ExtensionParams()
          .set('a', 1)
          .set('b', 2)
          .setAll({'c': 3})
          .withMeta(const ExtensionMeta({'d': 4}));
      final json = params.toJson();
      expect(json['a'], 1);
      expect(json['b'], 2);
      expect(json['c'], 3);
      expect(json['_meta'], {'d': 4});
    });
  });

  group('ExtensionErrorCodes', () {
    test('methodNotFound is standard JSON-RPC code', () {
      expect(ExtensionErrorCodes.methodNotFound, -32601);
    });

    test('reserved range is correct', () {
      expect(ExtensionErrorCodes.reservedRangeStart, -32000);
      expect(ExtensionErrorCodes.reservedRangeEnd, -32099);
    });

    test('isImplementationError checks range', () {
      expect(ExtensionErrorCodes.isImplementationError(-32000), isTrue);
      expect(ExtensionErrorCodes.isImplementationError(-32050), isTrue);
      expect(ExtensionErrorCodes.isImplementationError(-32099), isTrue);
      expect(ExtensionErrorCodes.isImplementationError(-32100), isFalse);
      expect(ExtensionErrorCodes.isImplementationError(-31999), isFalse);
      expect(ExtensionErrorCodes.isImplementationError(-32601), isFalse);
    });
  });

  group('AcpCapabilities with extensions', () {
    test('includes _meta in JSON when present', () {
      const caps = AcpCapabilities(
        meta: {
          'mycompany.com': {'customFeature': true},
        },
      );
      final json = caps.toJson();
      expect(json['_meta'], isNotNull);
      expect(json['_meta']['mycompany.com']['customFeature'], isTrue);
    });

    test('excludes _meta when null', () {
      const caps = AcpCapabilities();
      final json = caps.toJson();
      expect(json.containsKey('_meta'), isFalse);
    });

    test('excludes _meta when empty', () {
      const caps = AcpCapabilities(meta: {});
      final json = caps.toJson();
      expect(json.containsKey('_meta'), isFalse);
    });

    test('includes terminal capability', () {
      const caps = AcpCapabilities(terminal: true);
      final json = caps.toJson();
      expect(json['terminal'], isTrue);
    });

    test('excludes terminal when false', () {
      const caps = AcpCapabilities();
      final json = caps.toJson();
      expect(json.containsKey('terminal'), isFalse);
    });

    test('copyWith preserves values', () {
      const caps = AcpCapabilities(terminal: true, meta: {'test': true});
      final copied = caps.copyWith(
        fs: const FsCapabilities(writeTextFile: true),
      );
      expect(copied.terminal, isTrue);
      expect(copied.meta, {'test': true});
      expect(copied.fs.writeTextFile, isTrue);
    });
  });

  group('InitializeResult extension helpers', () {
    test('extensionCapabilities parses _meta', () {
      final result = InitializeResult(
        protocolVersion: 1,
        agentCapabilities: {
          'loadSession': true,
          '_meta': {
            'zed.dev': {'workspace': true},
          },
        },
        authMethods: null,
      );
      final extCaps = result.extensionCapabilities;
      expect(extCaps.supports('zed.dev', 'workspace'), isTrue);
    });

    test('extensionCapabilities handles missing _meta', () {
      final result = InitializeResult(
        protocolVersion: 1,
        agentCapabilities: {'loadSession': true},
        authMethods: null,
      );
      final extCaps = result.extensionCapabilities;
      expect(extCaps.isEmpty, isTrue);
    });

    test('extensionCapabilities handles null capabilities', () {
      final result = InitializeResult(
        protocolVersion: 1,
        agentCapabilities: null,
        authMethods: null,
      );
      final extCaps = result.extensionCapabilities;
      expect(extCaps.isEmpty, isTrue);
    });

    test('supportsLoadSession checks capability', () {
      final result = InitializeResult(
        protocolVersion: 1,
        agentCapabilities: {'loadSession': true},
        authMethods: null,
      );
      expect(result.supportsLoadSession, isTrue);
    });

    test('promptCapabilities parses correctly', () {
      final result = InitializeResult(
        protocolVersion: 1,
        agentCapabilities: {
          'promptCapabilities': {
            'image': true,
            'audio': false,
            'embeddedContext': true,
          },
        },
        authMethods: null,
      );
      final caps = result.promptCapabilities;
      expect(caps.image, isTrue);
      expect(caps.audio, isFalse);
      expect(caps.embeddedContext, isTrue);
    });

    test('promptCapabilities defaults when missing', () {
      final result = InitializeResult(
        protocolVersion: 1,
        agentCapabilities: null,
        authMethods: null,
      );
      final caps = result.promptCapabilities;
      expect(caps.image, isFalse);
      expect(caps.audio, isFalse);
      expect(caps.embeddedContext, isFalse);
    });

    test('mcpCapabilities parses correctly', () {
      final result = InitializeResult(
        protocolVersion: 1,
        agentCapabilities: {
          'mcpCapabilities': {'http': true, 'sse': false},
        },
        authMethods: null,
      );
      final caps = result.mcpCapabilities;
      expect(caps.http, isTrue);
      expect(caps.sse, isFalse);
    });
  });
}
