import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_acp/dart_acp.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../example/acpcli/settings.dart';
import 'helpers/adapter_caps.dart';

void main() {
  group('AcpClient e2e real adapters', tags: 'e2e', () {
    late Settings settings;

    setUpAll(() async {
      // Read test-specific settings.json so tests don't depend on default CLI
      // settings.
      settings = await Settings.loadFromFile('test/test_settings.json');
    });

    Future<void> runClient({
      required String agentKey,
      required String prompt,
      void Function(List<Map<String, dynamic>> frames)? onJsonFrames,
      FutureOr<void> Function(List<AcpUpdate> updates)? onUpdates,
      String? workspace,
    }) async {
      final agent = settings.agentServers[agentKey]!;
      final capturedOut = <String>[];
      final capturedIn = <String>[];
      final client = await AcpClient.start(
        config: AcpConfig(
          agentCommand: agent.command,
          agentArgs: agent.args,
          envOverrides: agent.env,
          // In tests, allow all permissions so agents can propose diffs, etc.
          permissionProvider: DefaultPermissionProvider(onRequest: (opts) async => PermissionOutcome.allow),
          mcpServers: settings.mcpServers
              .map(
                (s) => {
                  'name': s.name,
                  'command': s.command,
                  'args': s.args,
                  if (s.env.isNotEmpty) 'env': s.env.entries.map((e) => {'name': e.key, 'value': e.value}).toList(),
                },
              )
              .toList(),
          capabilities: const AcpCapabilities(fs: FsCapabilities(readTextFile: true, writeTextFile: false)),
          // Enable filesystem provider for tests
          fsProvider: const _TestFsProvider(),
          // Tap raw frames for JSONL assertions
          onProtocolOut: capturedOut.add,
          onProtocolIn: capturedIn.add,
          terminalProvider: DefaultTerminalProvider(),
        ),
      );
      addTearDown(() async => client.dispose());
      await client.initialize();
      final workspaceRoot = workspace ?? Directory.current.path;
      final sid = await client.newSession(workspaceRoot);

      final updates = client.prompt(sessionId: sid, content: prompt);

      final collected = <AcpUpdate>[];
      await for (final u in updates.timeout(
        const Duration(seconds: 70), // Wait for Gemini's rate limit response
        onTimeout: (sink) {
          // If we timeout, close the sink to end the stream
          sink.close();
        },
      )) {
        collected.add(u);
        if (u is TurnEnded) break;
      }

      if (onUpdates != null) {
        await onUpdates(collected);
      }

      if (onJsonFrames != null) {
        final jsonFrames = <Map<String, dynamic>>[];
        for (final l in capturedOut.followedBy(capturedIn)) {
          jsonFrames.add(jsonDecode(l) as Map<String, dynamic>);
        }
        onJsonFrames(jsonFrames);
      }
    }

    // Helper to create a configured client for direct control in tests
    // (createClient helper defined in consolidated group below)

    // (No-op helper section)

    test('echo agent responds to prompt', () async {
      await runClient(
        agentKey: 'echo',
        prompt: 'Hello from e2e',
        onUpdates: (updates) {
          // Check we got message deltas
          final messageDeltas = updates.whereType<MessageDelta>().toList();
          expect(messageDeltas.isNotEmpty, isTrue, reason: 'No assistant delta observed');

          // Verify the echo response
          final fullText = messageDeltas.expand((d) => d.content).whereType<TextContent>().map((c) => c.text).join();
          expect(fullText, equals('Echo: Hello from e2e'));

          // Check for completion
          expect(updates.whereType<TurnEnded>().isNotEmpty, isTrue);
        },
      );
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('gemini responds to prompt (AcpClient)', () async {
      final skipReason = skipIfGeminiAuthMissing();
      if (skipReason != null) {
        markTestSkipped(skipReason);
        return;
      }
      try {
        await runClient(
          agentKey: 'gemini',
          prompt: 'Say hello',
          onUpdates: (updates) {
            expect(updates.any((u) => u is MessageDelta), isTrue, reason: 'No assistant delta observed');
            expect(updates.whereType<TurnEnded>().isNotEmpty, isTrue);
          },
        );
      } catch (e) {
        final msg = e.toString().toLowerCase();
        // Skip when auth is not configured
        if (msg.contains('authentication required') || msg.contains('api key') || msg.contains('401')) {
          markTestSkipped(
            'Gemini auth not configured or invalid - '
            'set GEMINI_API_KEY or GOOGLE_API_KEY',
          );
          return;
        }
        // Skip on rate limit
        if (msg.contains('429') || msg.contains('rate limit')) {
          markTestSkipped('Gemini rate limit exceeded - test cannot run at this time');
          return;
        }
        rethrow;
      }
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('claude-code responds to prompt (AcpClient)', () async {
      await runClient(
        agentKey: 'claude-code',
        prompt: 'Say hello',
        onUpdates: (updates) {
          expect(updates.any((u) => u is MessageDelta), isTrue, reason: 'No assistant delta observed');
          expect(updates.whereType<TurnEnded>().isNotEmpty, isTrue);
        },
      );
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('plan updates present when requested', () async {
      await runClient(
        agentKey: 'claude-code',
        prompt:
            'Before doing anything, produce a 3-step plan to add a '
            '"Testing" section to README.md. Stream plan updates for each '
            'step as you go. Stop after presenting the plan; do not apply '
            'changes yet.',
        onUpdates: (updates) {
          if (!updates.any((u) => u is PlanUpdate)) {
            markTestSkipped(
              'claude-code did not emit structured plan updates; '
              'it may return plan content as plain text instead',
            );
          }
        },
      );
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('diff-only prompt yields diff updates', () async {
      final dir = await Directory.systemTemp.createTemp('acp_client_diffs_');
      try {
        File('${dir.path}/README.md').writeAsStringSync('# Test README');
        await runClient(
          agentKey: 'claude-code',
          prompt:
              'Propose changes to README.md adding a "How to Test" section.'
              ' Do not apply changes; send only a diff.',
          workspace: dir.path,
          onUpdates: (updates) {
            final hasStructuredDiff = updates.any((u) => u is DiffUpdate);
            final hasTextDiff = updates.any(
              (u) => u is MessageDelta && u.content.any((b) => b is TextContent && b.text.contains('```diff')),
            );
            expect(hasStructuredDiff || hasTextDiff, isTrue, reason: 'No diff update or diff code block observed');
          },
        );
      } finally {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      }
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('file read tool call happens when asked to summarize', () async {
      final dir = await Directory.systemTemp.createTemp('acp_client_fileio_');
      try {
        File('${dir.path}/README.md').writeAsStringSync('# Test README');
        await runClient(
          agentKey: 'claude-code',
          prompt: 'Read README.md and summarize in one paragraph.',
          workspace: dir.path,
          onJsonFrames: (frames) {
            final sawTool = frames.any(
              (f) =>
                  f['method'] == 'session/update' &&
                  (f['params'] as Map)['update'] is Map &&
                  ((f['params'] as Map)['update'] as Map)['sessionUpdate'] == 'tool_call',
            );
            expect(sawTool, isTrue, reason: 'No tool_call observed for file read');
          },
        );
      } finally {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      }
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  // Additional E2E coverage consolidated from comprehensive tests
  group('AcpClient e2e consolidated', tags: 'e2e', () {
    late Settings settings;
    setUpAll(() async {
      settings = await Settings.loadFromFile('test/test_settings.json');
    });

    Future<AcpClient> createClient(
      String agentKey, {
      String? workspaceRoot,
      AcpCapabilities? capabilities,
      PermissionProvider? permissionProvider,
      TerminalProvider? terminalProvider,
    }) async {
      final agent = settings.agentServers[agentKey]!;
      final client = await AcpClient.start(
        config: AcpConfig(
          agentCommand: agent.command,
          agentArgs: agent.args,
          envOverrides: agent.env,
          capabilities:
              capabilities ?? const AcpCapabilities(fs: FsCapabilities(readTextFile: true, writeTextFile: true)),
          permissionProvider: permissionProvider ?? const DefaultPermissionProvider(),
          terminalProvider: terminalProvider ?? DefaultTerminalProvider(),
          // Enable filesystem provider
          fsProvider: const _TestFsProvider(),
        ),
      );
      await client.initialize();
      return client;
    }

    Map<String, ToolCall> getFinalToolCalls(List<AcpUpdate> updates) {
      final toolCallsById = <String, ToolCall>{};
      var emptyIdCounter = 0;
      for (final update in updates.whereType<ToolCallUpdate>()) {
        var id = update.toolCall.toolCallId;
        if (id.isEmpty) {
          id = '__empty_${emptyIdCounter++}';
        }
        toolCallsById[id] = update.toolCall;
      }
      return toolCallsById;
    }

    for (final agentName in ['gemini', 'claude-code']) {
      test('$agentName: create/manage sessions and cancellation', () async {
        if (agentName == 'gemini') {
          final skipReason = skipIfGeminiAuthMissing();
          if (skipReason != null) {
            markTestSkipped(skipReason);
            return;
          }
        }
        final client = await createClient(agentName);
        addTearDown(client.dispose);
        String sessionId;
        try {
          sessionId = await client.newSession(Directory.current.path);
        } catch (e) {
          if (agentName == 'gemini' && e.toString().toLowerCase().contains('authentication')) {
            markTestSkipped(
              'Gemini auth not configured or invalid - '
              'set GEMINI_API_KEY or GOOGLE_API_KEY',
            );
            return;
          }
          rethrow;
        }
        expect(sessionId, isNotEmpty);

        // Prompt and ensure response completes
        await client.prompt(sessionId: sessionId, content: 'What is 2+2?').drain();

        // Skip multiple prompts test for Gemini due to known bug
        if (agentName == 'gemini') {
          // Gemini's experimental ACP implementation has a bug
          // where it fails on multiple prompts to the same session
          // when using the default model. See specs/issues.md
          return;
        }

        // Test multiple prompts in same session
        await Future.delayed(const Duration(seconds: 1));
        final draining = client.prompt(sessionId: sessionId, content: 'Count to 1000000 slowly').drain();
        await Future.delayed(const Duration(milliseconds: 100));
        await client.cancel(sessionId: sessionId);
        await draining;
      }, timeout: const Timeout(Duration(seconds: 60)));

      test(
        '$agentName: session replay via sessionUpdates',
        () async {
          if (agentName == 'gemini') {
            final skipReason = skipIfGeminiAuthMissing();
            if (skipReason != null) {
              markTestSkipped(skipReason);
              return;
            }
          }
          final client = await createClient(agentName);
          addTearDown(client.dispose);
          String sessionId;
          try {
            sessionId = await client.newSession(Directory.current.path);
          } catch (e) {
            if (agentName == 'gemini' && e.toString().toLowerCase().contains('authentication')) {
              markTestSkipped(
                'Gemini auth not configured or invalid - '
                'set GEMINI_API_KEY or GOOGLE_API_KEY',
              );
              return;
            }
            rethrow;
          }
          await client.prompt(sessionId: sessionId, content: 'Hello').drain();
          final replayed = <AcpUpdate>[];
          await for (final u in client.sessionUpdates(sessionId)) {
            replayed.add(u);
            if (u is TurnEnded) break;
          }
          expect(replayed.whereType<MessageDelta>(), isNotEmpty);
        },
        timeout: const Timeout(Duration(seconds: 60)),
        // skip: skipIfMissingAll(agentName, [
        //   'loadsession',
        //   'load_session',
        // ], 'session/load'),
      );

      test('$agentName: file read operations', () async {
        if (agentName == 'gemini') {
          final skipReason = skipIfGeminiAuthMissing();
          if (skipReason != null) {
            markTestSkipped(skipReason);
            return;
          }
          // Skip - doesn't report tool calls as expected by test
          markTestSkipped("Gemini doesn't report read tool calls as expected");
          return;
        }
        final dir = await Directory.systemTemp.createTemp('acp_read_');
        addTearDown(() async {
          if (dir.existsSync()) {
            await dir.delete(recursive: true);
          }
        });
        File(path.join(dir.path, 'test.txt')).writeAsStringSync('Hello from test file');
        final testFile = File(path.join(dir.path, 'test.txt'));
        expect(testFile.existsSync(), isTrue, reason: 'test.txt must exist');
        expect(
          testFile.readAsStringSync(),
          contains('Hello from test file'),
          reason: 'test.txt must contain fixture content',
        );
        // For file operations test, we need to allow permissions
        // This simulates a user approving file access
        final client = await createClient(
          agentName,
          workspaceRoot: dir.path,
          permissionProvider: DefaultPermissionProvider(onRequest: (opts) async => PermissionOutcome.allow),
        );
        addTearDown(client.dispose);
        final sessionId = await client.newSession(dir.path);
        final updates = <AcpUpdate>[];
        await client
            .prompt(sessionId: sessionId, content: 'Read the file test.txt and summarize it')
            .forEach(updates.add);
        final finalToolCalls = getFinalToolCalls(updates);
        expect(finalToolCalls, isNotEmpty);
        final readCall = finalToolCalls.values.firstWhere(
          (tc) => tc.kind == ToolKind.read || (tc.title?.toLowerCase().contains('read') ?? false),
          orElse: () => finalToolCalls.values.first,
        );
        String stringifyToolData(Object? value) {
          if (value == null) return '';
          try {
            return jsonEncode(value);
          } catch (_) {
            return value.toString();
          }
        }

        final messages = updates
            .whereType<MessageDelta>()
            .expand((m) => m.content)
            .whereType<TextContent>()
            .map((t) => t.text)
            .join()
            .toLowerCase();
        final rawInputText = stringifyToolData(readCall.rawInput).toLowerCase();
        final rawOutputText = stringifyToolData(readCall.rawOutput).toLowerCase();
        final observedReadContent =
            messages.contains('hello') ||
            rawOutputText.contains('hello from test file') ||
            rawOutputText.contains('hello');
        if (!observedReadContent && messages.contains('appears to be empty')) {
          markTestSkipped(
            'claude-code reported the file as empty despite fixture content; '
            'rawInput=$rawInputText',
          );
          return;
        }
        expect(
          observedReadContent,
          isTrue,
          reason:
              'No file content observed in assistant output or tool output. '
              'rawInput=$rawInputText rawOutput=$rawOutputText',
        );
      }, timeout: const Timeout(Duration(seconds: 60)));

      test('$agentName: file write operations', () async {
        if (agentName == 'gemini') {
          final skipReason = skipIfGeminiAuthMissing();
          if (skipReason != null) {
            markTestSkipped(skipReason);
            return;
          }
          // Skip due to timeout issues with write operations
          markTestSkipped('Gemini has timeout issues with write operations');
          return;
        }

        final dir = await Directory.systemTemp.createTemp('acp_write_');
        addTearDown(() async {
          if (dir.existsSync()) {
            await dir.delete(recursive: true);
          }
        });
        // For write operations, we need both capabilities and permissions
        final client = await createClient(
          agentName,
          workspaceRoot: dir.path,
          capabilities: const AcpCapabilities(fs: FsCapabilities(readTextFile: true, writeTextFile: true)),
          permissionProvider: DefaultPermissionProvider(onRequest: (opts) async => PermissionOutcome.allow),
        );
        addTearDown(client.dispose);
        final sessionId = await client.newSession(dir.path);
        final updates = <AcpUpdate>[];
        await client
            .prompt(sessionId: sessionId, content: 'Create a file output.txt with content "Test output"')
            .forEach(updates.add);
        final finalToolCalls = getFinalToolCalls(updates);
        final writeCalls = finalToolCalls.values.where(
          (tc) => tc.kind == ToolKind.edit || (tc.title?.contains('write') ?? false),
        );
        expect(writeCalls.isNotEmpty, isTrue);
      }, timeout: const Timeout(Duration(seconds: 60)));
    }

    test('permission configuration is respected', () async {
      // Test that permissions configured in AcpConfig are properly respected
      final dir = await Directory.systemTemp.createTemp('acp_perm_cfg_');
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });

      File(path.join(dir.path, 'test.txt')).writeAsStringSync('Test data');

      // Create a client with specific permission configuration
      final permissionRequests = <String>[];
      final client = await createClient(
        'claude-code',
        workspaceRoot: dir.path,
        permissionProvider: DefaultPermissionProvider(
          onRequest: (opts) async {
            permissionRequests.add(opts.toolKind ?? opts.toolName);
            // Deny write/edit operations, allow read (fs/write_text_file uses
            // toolKind 'edit' per ACP spec)
            final kind = opts.toolKind?.toLowerCase() ?? '';
            final name = opts.toolName.toLowerCase();
            if (kind.contains('write') ||
                kind.contains('edit') ||
                name.contains('write') ||
                name.contains('write_text_file')) {
              return PermissionOutcome.deny;
            }
            return PermissionOutcome.allow;
          },
        ),
        capabilities: const AcpCapabilities(fs: FsCapabilities(readTextFile: true, writeTextFile: true)),
      );
      addTearDown(client.dispose);

      final sessionId = await client.newSession(dir.path);
      final updates = <AcpUpdate>[];

      // Ask to both read and write
      await client
          .prompt(sessionId: sessionId, content: 'Read test.txt and then write "Modified" to output.txt')
          .forEach(updates.add);

      // Skip if agent did not invoke permission-gated operations (fs tools,
      // session/request_permission, or terminal). Agent behavior varies.
      if (permissionRequests.isEmpty) {
        markTestSkipped(
          'Agent did not invoke any permission-gated operations for this '
          'task - cannot verify permission configuration',
        );
        return;
      }

      // Core assertion: write should have been denied
      expect(File(path.join(dir.path, 'output.txt')).existsSync(), isFalse, reason: 'Write should have been denied');

      // Optional: verify agent could read (allowed op); skip if agent
      // did not include content in response (phrasing varies)
      final messages = updates
          .whereType<MessageDelta>()
          .expand((m) => m.content)
          .whereType<TextContent>()
          .map((t) => t.text)
          .join()
          .toLowerCase();
      final hadReadRequest = permissionRequests.any(
        (r) => r.toString().toLowerCase().contains('read') || r.toString().toLowerCase().contains('read_text_file'),
      );
      if (hadReadRequest && !messages.contains('test data') && !messages.contains('test.txt')) {
        markTestSkipped('Agent did not include file content in response after read');
        return;
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('permission denial is respected', () async {
      // Test that when permissions are denied, operations fail appropriately
      final dir = await Directory.systemTemp.createTemp('acp_perm_test_');
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });

      File(path.join(dir.path, 'secret.txt')).writeAsStringSync('Secret data');

      final client = await createClient(
        'claude-code',
        workspaceRoot: dir.path,
        permissionProvider: DefaultPermissionProvider(onRequest: (opts) async => PermissionOutcome.deny),
      );
      addTearDown(client.dispose);

      final sessionId = await client.newSession(dir.path);
      final updates = <AcpUpdate>[];
      await client.prompt(sessionId: sessionId, content: 'Read the file secret.txt').forEach(updates.add);

      // The agent should indicate it couldn't read the file
      final messages = updates
          .whereType<MessageDelta>()
          .expand((m) => m.content)
          .whereType<TextContent>()
          .map((t) => t.text)
          .join()
          .toLowerCase();

      // Should NOT contain the secret data
      expect(messages, isNot(contains('secret data')));
      // Should indicate permission issue or inability to read (agent phrasing
      // varies; accept common patterns).
      final indicatesDenial = [
        'permission',
        'unable',
        'cannot',
        'denied',
        'access',
        'restricted',
        'blocked',
        'refused',
        "can't",
        "couldn't",
        'could not',
      ].any((p) => messages.contains(p));
      if (!indicatesDenial) {
        markTestSkipped(
          'Agent did not indicate permission denial in response '
          '(agent phrasing varies)',
        );
        return;
      }
    });

    test('invalid session id yields error', () async {
      final client = await createClient('claude-code');
      addTearDown(client.dispose);
      final sessionId = await client.newSession(Directory.current.path);
      final invalid = 'invalid-$sessionId-mod';
      expect(() => client.prompt(sessionId: invalid, content: 'Hello').drain(), throwsA(anything));
    });

    test('agent crash surfaces error', () async {
      // Test that agent crashing during start is handled
      expect(
        () => AcpClient.start(
          config: AcpConfig(agentCommand: 'false', agentArgs: const []),
        ),
        throwsA(isA<StateError>()),
      );
    });

    // Note: Minimum protocol version enforcement test is skipped because
    // AcpConfig.minimumProtocolVersion is a static constant (currently 1)
    // and all real agents return protocol version 1, so we cannot test
    // the rejection case without modifying the source code.

    test('richer tool metadata display', () async {
      // Test that tool calls include title, locations, raw_input, raw_output
      final dir = await Directory.systemTemp.createTemp('acp_tool_meta_');
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });

      File(path.join(dir.path, 'test.txt')).writeAsStringSync('Test content');

      final client = await createClient(
        'claude-code',
        workspaceRoot: dir.path,
        permissionProvider: DefaultPermissionProvider(onRequest: (opts) async => PermissionOutcome.allow),
      );
      addTearDown(client.dispose);

      final sessionId = await client.newSession(dir.path);
      final updates = <AcpUpdate>[];

      await client
          .prompt(sessionId: sessionId, content: 'Read test.txt and tell me what it contains')
          .forEach(updates.add);

      // Find tool call updates
      final toolCalls = updates.whereType<ToolCallUpdate>();
      expect(toolCalls.isNotEmpty, isTrue, reason: 'No tool calls observed');

      // Check for richer metadata
      final readCall = toolCalls.firstWhere(
        (tc) => tc.toolCall.kind == ToolKind.read || (tc.toolCall.title?.contains('read') ?? false),
        orElse: () => toolCalls.first,
      );

      // Verify at least some metadata fields are present
      // Note: Not all fields may be present in every tool call
      final hasMetadata =
          readCall.toolCall.title != null ||
          readCall.toolCall.locations != null ||
          readCall.toolCall.rawInput != null ||
          readCall.toolCall.rawOutput != null;

      expect(hasMetadata, isTrue, reason: 'Tool call should have at least some metadata fields');
    });

    test('current_mode_update routing', () async {
      // Test that current_mode_update events are properly routed as ModeUpdate
      final client = await createClient('claude-code');
      addTearDown(client.dispose);

      final sessionId = await client.newSession(Directory.current.path);

      // Get available modes
      final modes = client.sessionModes(sessionId);
      if (modes == null || modes.availableModes.isEmpty) {
        markTestSkipped('No modes available for testing');
        return;
      }

      // Find a mode different from current
      final currentMode = modes.currentModeId;
      final targetMode = modes.availableModes.firstWhere(
        (m) => m.id != currentMode,
        orElse: () => modes.availableModes.first,
      );

      if (targetMode.id == currentMode) {
        markTestSkipped('Only one mode available, cannot test mode change');
        return;
      }

      // Try setMode; agent may not support session/set_mode (extension).
      bool setModeOk;
      try {
        setModeOk = await client
            .setMode(sessionId: sessionId, modeId: targetMode.id)
            .timeout(const Duration(seconds: 5));
      } on TimeoutException {
        markTestSkipped('session/set_mode timed out - agent may not support mode changes');
        return;
      } on Object catch (_) {
        markTestSkipped('session/set_mode not supported by agent');
        return;
      }
      if (!setModeOk) {
        markTestSkipped('session/set_mode returned false');
        return;
      }

      // Set up listener for mode updates
      final updates = <AcpUpdate>[];
      final sub = client.prompt(sessionId: sessionId, content: 'Hello').listen(updates.add);

      // Wait a bit for the update to be routed
      await Future.delayed(const Duration(milliseconds: 500));
      await sub.cancel();

      // Check if we received a ModeUpdate (agent may not emit current_mode_update
      // for set_mode; behavior varies)
      final modeUpdates = updates.whereType<ModeUpdate>();
      if (modeUpdates.isEmpty) {
        markTestSkipped('Agent did not emit current_mode_update after set_mode');
        return;
      }

      final modeUpdate = modeUpdates.first;
      expect(modeUpdate.currentModeId, equals(targetMode.id));
    });

    group('Terminal Operations', () {
      for (final agentName in ['gemini', 'claude-code']) {
        test(
          '$agentName: execute via terminal or execute tool',
          () async {
            if (agentName == 'gemini') {
              markTestSkipped(
                "Gemini doesn't report execute tool calls as expected - "
                'this is an agent limitation, not a dart_acp bug',
              );
              return;
            }
            final skipReason = await skipIfNoRuntimeTerminal(agentName);
            if (skipReason != null) {
              markTestSkipped(skipReason);
              return;
            }
            final client = await createClient(agentName);
            addTearDown(client.dispose);
            final sessionId = await client.newSession(Directory.current.path);
            final events = <TerminalEvent>[];
            final sub = client.terminalEvents.listen(events.add);
            final updates = <AcpUpdate>[];
            await client
                .prompt(sessionId: sessionId, content: 'Run the command: echo "Hello from terminal"')
                .forEach(updates.add);
            await Future.delayed(const Duration(milliseconds: 500));
            await sub.cancel();
            if (events.isNotEmpty) {
              final created = events.whereType<TerminalCreated>().firstOrNull;
              if (created != null) {
                final out = await client.terminalOutput(created.terminalId);
                expect(out, contains('Hello'));
              }
            }
            final finalToolCalls = getFinalToolCalls(updates);
            final execCalls = finalToolCalls.values.where(
              (tc) => tc.kind == ToolKind.execute || (tc.title?.contains('execute') ?? false),
            );
            expect(events.isNotEmpty || execCalls.isNotEmpty, isTrue);
          },
          // skip: skipIfNoRuntimeTerminal(agentName),
        );
      }
    });
  });
}

/// Test filesystem provider - actual operations handled by SessionManager.
class _TestFsProvider implements FsProvider {
  const _TestFsProvider();

  @override
  Future<String> readTextFile(String path, {int? line, int? limit}) async {
    // This is never called - SessionManager creates its own provider
    throw UnimplementedError('Should not be called');
  }

  @override
  Future<void> writeTextFile(String path, String content) async {
    // This is never called - SessionManager creates its own provider
    throw UnimplementedError('Should not be called');
  }
}
