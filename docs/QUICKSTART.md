# QUICKSTART

## 1. Overview
The `dart_acp` module provides a robust Dart client implementation of the Agent Client Protocol (ACP). It handles transport orchestration (JSON-RPC over standard I/O streams), session lifecycle management, file system sandboxing, and real-time streaming of agent updates, tool executions, and terminal interactions.

## 2. Import
```dart
import 'package:dart_acp/dart_acp.dart';
```

## 3. Setup
Configure your `AcpConfig` and launch the `AcpClient`. The configuration defines how the agent process is spawned and what capabilities are advertised.

```dart
import 'package:dart_acp/dart_acp.dart';

Future<void> main() async {
  // 1. Configure the ACP client
  final config = AcpConfig(
    agentCommand: 'my-acp-agent', // Agent executable name or path
    agentArgs: ['--stdio'],
    envOverrides: {'DEBUG': 'true'},
    capabilities: const AcpCapabilities(
      fs: FsCapabilities(
        readTextFile: true,   // Allow the agent to read files
        writeTextFile: true,  // Allow the agent to write files
      ),
      terminal: true,         // Advertise terminal support
    ),
    // Define request timeouts
    timeouts: const AcpTimeouts(
      initialize: Duration(seconds: 15),
      prompt: Duration(minutes: 5),
    ),
  );

  // 2. Start the client process and transport
  final client = await AcpClient.start(config: config);

  // 3. Negotiate protocol versions and capabilities
  final initResult = await client.initialize();
  print('Agent protocol version: ${initResult.protocolVersion}');
  
  if (initResult.supportsListSessions) {
    print('Agent supports listing sessions');
  }
  
  // Check rich prompt capabilities
  final promptCaps = initResult.promptCapabilities;
  print('Supports images: ${promptCaps.image}');
  print('Supports audio: ${promptCaps.audio}');

  // Cleanup when finished
  await client.dispose();
}
```

## 4. Session Management

### Creating and Loading Sessions
Sessions are bound to a workspace root directory. You can create new sessions, list existing ones, or fork them for independent work.

```dart
// Create a new session in a specific workspace
final sessionId = await client.newSession('/home/user/project');

// List existing sessions (requires agent support)
final listResult = await client.listSessions(cwd: '/home/user/project');
for (final info in listResult.sessions) {
  // Fields use camelCase: sessionId, updatedAt, etc.
  print('Session: ${info.sessionId} updated at ${info.updatedAt}');
}

// Fork an existing session to create a new branch
final forkResult = await client.forkSession(sessionId: sessionId);
final forkedId = forkResult.sessionId;

// Load a previous session with full history replay
await client.loadSession(sessionId: sessionId, workspaceRoot: '/home/user/project');
```

### Modes and Configuration
Agents may offer specific operation modes or configurable options like model selection.

```dart
// Get currently available and active modes
final modes = client.sessionModes(sessionId);
if (modes != null) {
  print('Current mode: ${modes.currentModeId}');
  // Set session mode (extension)
  await client.setMode(sessionId: sessionId, modeId: 'architect');
}

// Set session-specific configuration options
final updatedConfig = await client.setConfigOption(
  sessionId: sessionId,
  configId: 'model',
  value: 'gpt-4o',
);
```

## 5. Interaction

### Sending Prompts
The `prompt` method automatically processes @-mentions for local files and remote URLs.

```dart
final updateStream = client.prompt(
  sessionId: sessionId,
  content: 'Analyze @main.dart and compare with @https://example.com/spec.md',
);

await for (final update in updateStream) {
  _handleUpdate(update);
}
```

### Handling Streamed Updates
The client receives typed `AcpUpdate` events. All Dart fields follow `camelCase` naming.

```dart
void _handleUpdate(AcpUpdate update) {
  switch (update) {
    case MessageDelta():
      // Role is 'assistant' or 'user'
      print('${update.role}: ${update.text}');
      // Handle rich content blocks if present
      for (final block in update.content) {
        if (block is ImageContent) {
          print('  [Image: ${block.mimeType}]');
        } else if (block is ResourceContent) {
          print('  [Resource: ${block.uri} (${block.title ?? 'No title'})]');
        }
      }
      break;
      
    case ToolCallUpdate():
      final call = update.toolCall;
      // toolCallId, rawInput, rawOutput, etc.
      print('Tool [${call.toolCallId}]: ${call.title} (${call.status.name})');
      if (call.locations != null) {
        for (final loc in call.locations!) {
          print('  File: ${loc.path}:${loc.line}');
        }
      }
      break;

    case PlanUpdate():
      print('Plan: ${update.plan.title}');
      for (final entry in update.plan.entries) {
        // status is PlanEntryStatus (pending, inProgress, completed)
        print('  - [${entry.status.name}] ${entry.content}');
      }
      break;

    case DiffUpdate():
      final diff = update.diff;
      print('Diff for ${diff.uri} status: ${diff.status.name}');
      break;

    case TurnEnded():
      // StopReason: endTurn, maxTokens, cancelled, etc.
      print('Turn ended: ${update.stopReason.name}');
      break;

    case AvailableCommandsUpdate():
      final names = update.commands.map((c) => c.name).join(', ');
      print('Commands available: $names');
      break;
      
    default:
      break;
  }
}
```

## 6. Terminal Interaction
Observe and manage shell processes launched by the agent.

```dart
client.terminalEvents.listen((event) {
  switch (event) {
    case TerminalCreated():
      print('Terminal [${event.terminalId}] started: ${event.command}');
      break;
    case TerminalOutputEvent():
      print('Output [${event.terminalId}]: ${event.output}');
      if (event.exitCode != null) {
        print('Exited with code: ${event.exitCode}');
      }
      break;
    case TerminalExited():
      print('Terminal [${event.terminalId}] exited with code ${event.code}');
      break;
  }
});

// Manual control
await client.terminalKill('some-terminal-id');
final currentBuffer = await client.terminalOutput('some-terminal-id');
```

## 7. Extensions
Custom vendor-specific methods and metadata are supported via the extensions API.

```dart
// Create a namespaced extension method
final method = extensionMethodName('my-vendor.com', 'workspace/list-files');

// Use ExtensionParams builder
final params = ExtensionParams()
  ..set('depth', 2)
  ..withMeta(ExtensionMeta({
    'my-vendor/requestId': 'abc-123',
  }));

// Send request
final response = await client.sendExtensionRequest(method, params);
print('Files: ${response['files']}');

// Check for extension metadata in response
final meta = response.meta;
if (meta != null && meta.containsKey('my-vendor/cache-hit')) {
  print('Cache hit: ${meta['my-vendor/cache-hit']}');
}
```

## 8. Advanced Configuration

### Custom Providers
You can override default behavior for file systems, permissions, and terminals.

```dart
final config = AcpConfig(
  // ...
  fsProvider: MyCustomFsProvider(),
  permissionProvider: DefaultPermissionProvider(
    onRequest: (options) async {
      print('Permission requested for: ${options.toolName}');
      print('Rationale: ${options.rationale}');
      // Return PermissionOutcome.allow, .deny, or .cancelled
      return PermissionOutcome.allow;
    },
  ),
);
```

### Protocol Monitoring
Monitor raw JSON-RPC traffic for debugging or auditing.

```dart
final config = AcpConfig(
  // ...
  onProtocolIn: (line) => print('RECV: $line'),
  onProtocolOut: (line) => print('SEND: $line'),
);
```