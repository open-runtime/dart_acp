# Session Module Quickstart

## 1. Overview
The `Session` module orchestrates the Agent Control Protocol (ACP) lifecycle. It is responsible for negotiating connection capabilities, managing session creation and state, routing real-time agent updates, and handling side-effects like tool execution, terminal events, and file system permissions safely within defined workspace boundaries.

## 2. Import
The primary entry point for session management is the `SessionManager`. While typically accessed through the high-level `AcpClient`, you can also use it directly:

```dart
import 'package:dart_acp/dart_acp.dart';
import 'package:dart_acp/src/session/session_manager.dart';
```

## 3. Setup
The `SessionManager` requires an `AcpConfig` and a `JsonRpcPeer`.

```dart
final config = AcpConfig(
  agentCommand: 'npx',
  agentArgs: ['@modelcontextprotocol/server-everything'],
  capabilities: const AcpCapabilities(
    fs: FsCapabilities(readTextFile: true, writeTextFile: true),
    terminal: true,
  ),
);

// SessionManager is typically initialized by AcpClient
final manager = SessionManager(
  config: config,
  peer: peer,
);

// Clean up resources
await manager.dispose();
```

## 4. Common Operations

### Initializing the Protocol
Negotiate protocol capabilities with the agent before starting sessions.

```dart
final InitializeResult initResult = await manager.initialize();

print('Protocol Version: ${initResult.protocolVersion}');

// Check agent capabilities
if (initResult.supportsLoadSession) {
  print('Agent supports loading existing sessions');
}

final promptCaps = initResult.promptCapabilities;
print('Images: ${promptCaps.image}, Audio: ${promptCaps.audio}');

final sessionCaps = initResult.sessionCapabilities;
if (sessionCaps.fork) {
  print('Agent supports session forking');
}
```

### Creating and Resuming Sessions
Create a new session or resume an existing one.

```dart
// Start a new session in a workspace
final sessionId = await manager.newSession(
  workspaceRoot: '/path/to/project',
);

// Resume a session (simpler than loadSession, no history replay)
final resumeResult = await manager.resumeSession(
  sessionId: 'old-session-id',
  workspaceRoot: '/path/to/project',
);
print('Resumed session: ${resumeResult.sessionId}');
```

### Sending a Prompt
Send a prompt and handle streaming updates.

```dart
final stream = manager.prompt(
  sessionId: sessionId,
  content: [
    TextContent(text: 'Analyze the current directory').toJson(),
    ResourceContent(uri: 'file:///path/to/project/README.md').toJson(),
  ],
);

await for (final update in stream) {
  if (update is MessageDelta) {
    print('Agent: ${update.text}');
  } else if (update is ToolCallUpdate) {
    final tool = update.toolCall;
    print('Tool ${tool.title} is ${tool.status.name}');
  } else if (update is PlanUpdate) {
    print('New plan: ${update.plan.title}');
  } else if (update is TurnEnded) {
    print('Turn finished. Reason: ${update.stopReason.name}');
  }
}
```

### Managing Sessions (List, Fork, Config)
```dart
// List existing sessions
final result = await manager.listSessions(cwd: '/path/to/project');
for (final session in result.sessions) {
  print('Session ${session.sessionId} at ${session.cwd}');
}

// Fork a session
final forked = await manager.forkSession(sessionId: sessionId);
print('New forked session: ${forked.sessionId}');

// Set a session configuration option
final options = await manager.setConfigOption(
  sessionId: sessionId,
  configId: 'model-selection',
  value: 'gpt-4o',
);
```

### Terminal Management
Manage terminals spawned by the agent.

```dart
manager.terminalEvents.listen((event) {
  if (event is TerminalCreated) {
    print('Terminal ${event.terminalId} created: ${event.command}');
  }
});

// Interact with a specific terminal
final output = await manager.readTerminalOutput(terminalId);
await manager.waitTerminal(terminalId);
await manager.killTerminal(terminalId);
await manager.releaseTerminal(terminalId);
```

## 5. Model Reference

### AcpUpdate Types
The `prompt()` stream and `sessionUpdates()` stream emit these types:
- **`MessageDelta`**: Partial message content (text or thoughts).
- **`PlanUpdate`**: The agent's current execution plan/todo list.
- **`ToolCallUpdate`**: Progress or results of a tool execution.
- **`DiffUpdate`**: Proposed file changes.
- **`AvailableCommandsUpdate`**: Commands currently available for execution.
- **`ModeUpdate`**: Notification that the session mode changed.
- **`TurnEnded`**: Final event of a turn.

### StopReason
Used in `TurnEnded` to indicate why the agent stopped:
- `endTurn`: Completed successfully.
- `maxTokens`: Hit token limit.
- `maxTurnRequests`: Exceeded turn request limit.
- `cancelled`: Interrupted by client.
- `refusal`: Agent refused to fulfill request.

### ToolCallStatus
- `pending`: Awaiting execution or approval.
- `inProgress`: Tool is running.
- `completed`: Success.
- `failed`: Error occurred.
- `cancelled`: Terminated early.

## 6. Configuration & Security
The `SessionManager` enforces security policies defined in `AcpConfig`:
- **Workspace Jail**: Restricts file operations to the `workspaceRoot` unless `allowReadOutsideWorkspace` is true.
- **Permissions**: Every sensitive operation (read, edit, execute) is gated by the `permissionProvider`.
- **Providers**: Supply the actual implementation for `FsProvider` and `TerminalProvider`.
