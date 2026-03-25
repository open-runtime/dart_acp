# Session API Reference

The **Session** module orchestrates the life cycle of Agent Client Protocol (ACP) sessions, including initialization, capability negotiation, message prompting, and terminal management.

---

## 1. Primary Classes

### SessionManager
The central coordinator for ACP communication, managing transport, routing updates, and handling client-side tool/terminal operations.

- **Methods:**
  - `initialize({AcpCapabilities? capabilitiesOverride}) -> Future<InitializeResult>`: Negotiates protocol version and capabilities with the agent.
  - `newSession({required String workspaceRoot}) -> Future<String>`: Creates a new session in the specified directory.
  - `loadSession({required String sessionId, required String workspaceRoot}) -> Future<void>`: Loads a previous session and replays its history.
  - `prompt({required String sessionId, required List<Map<String, dynamic>> content}) -> Stream<AcpUpdate>`: Sends a prompt to the agent and returns a stream of typed updates for the current turn.
  - `cancel({required String sessionId}) -> Future<void>`: Cancels the active turn for the given session.
  - `dispose() -> Future<void>`: Cleans up internal streams, replay buffers, and terminal processes.
  - `listSessions({String? cwd, String? cursor}) -> Future<SessionListResult>`: Lists existing sessions (requires agent support).
  - `resumeSession({required String sessionId, required String workspaceRoot}) -> Future<SessionResult>`: Resumes a session without history replay.
  - `forkSession({required String sessionId}) -> Future<SessionResult>`: Forks an existing session into a new independent one.
  - `setConfigOption({required String sessionId, required String configId, required String value}) -> Future<List<ConfigOption>>`: Updates a session-level configuration option.
  - `sessionUpdates(String sessionId) -> Stream<AcpUpdate>`: Returns a persistent stream of updates, including history replay.
  - `sessionModes(String sessionId) -> ({String? currentModeId, List<({String id, String name})> availableModes})?`: Returns currently known mode information.
  - `setSessionMode({required String sessionId, required String modeId}) -> Future<bool>`: Switches the session's active mode.

- **Getters:**
  - `terminalEvents` (`Stream<TerminalEvent>`): A broadcast stream of terminal lifecycle events (creation, output, exit).

---

### InitializeResult
Contains the result of the `initialize` handshake, including negotiated protocol versions and advertised capabilities.

- **Fields:**
  - `protocolVersion` (`int`): The negotiated protocol version (minimum 1).
  - `agentCapabilities` (`Map<String, dynamic>?`): Raw capabilities advertised by the agent.
  - `authMethods` (`List<Map<String, dynamic>>?`): Supported authentication methods.

- **Getters:**
  - `extensionCapabilities` (`ExtensionCapabilities`): Parsed extension-specific capabilities from the `_meta` field.
  - `sessionCapabilities` (`SessionCapabilities`): Parsed session-related capabilities (list, resume, fork).
  - `supportsLoadSession` (`bool`): Whether the agent supports `session/load`.
  - `supportsListSessions` (`bool`): Whether the agent supports `session/list`.
  - `supportsResumeSession` (`bool`): Whether the agent supports `session/resume`.
  - `supportsForkSession` (`bool`): Whether the agent supports `session/fork`.
  - `promptCapabilities` (`({bool image, bool audio, bool embeddedContext})`): Specific input types supported in prompts.

---

## 2. Models & Data Types

### SessionInfo
Basic metadata about a session, typically returned by `listSessions`.

- **Fields:**
  - `sessionId` (`String`): Unique identifier for the session.
  - `cwd` (`String`): The working directory associated with the session.
  - `title` (`String?`): Optional human-readable title.
  - `updatedAt` (`DateTime?`): Last modified timestamp.
  - `meta` (`Map<String, dynamic>?`): Vendor-specific metadata.

### ConfigOption
A configurable setting advertised by the agent for a specific session.

- **Fields:**
  - `id` (`String`): Unique identifier for the option.
  - `name` (`String`): Human-readable label.
  - `type` (`String`): The type of control (e.g., "select").
  - `currentValue` (`String`): The currently active value.
  - `options` (`List<ConfigOptionChoice>`): Available choices for this option.
  - `description` (`String?`): Optional help text.
  - `group` (`String?`): Optional grouping for UI organization.

---

### AcpUpdate (Sealed Class)
The base class for all typed updates streamed from the agent during a session.

- **Subclasses:**
  - **PlanUpdate**: Contains the agent's current multi-step execution plan.
  - **MessageDelta**: Streaming chunks of text or content for user/assistant roles.
  - **ToolCallUpdate**: Updates on the status and results of tool invocations.
  - **DiffUpdate**: Proposed file changes and patches.
  - **AvailableCommandsUpdate**: Changes to the set of commands the agent can execute.
  - **TurnEnded**: Signal that a prompt turn has completed, including a `StopReason`.
  - **ModeUpdate**: Notification that the session mode has changed.

---

## 3. Enums

### StopReason
Reasons why a prompt turn might finish.
- `endTurn`: The model finished naturally.
- `maxTokens`: The turn hit a token limit.
- `maxTurnRequests`: The agent exceeded the maximum allowed RPC requests per turn.
- `cancelled`: The turn was explicitly cancelled by the client.
- `refusal`: The agent refused to provide a response.
- `other`: Non-standard or unknown stop reason.

### ToolCallStatus
Current state of a tool invocation.
- `pending`: Awaiting execution or approval.
- `inProgress`: Currently running.
- `completed`: Succeeded.
- `failed`: Terminated with an error.
- `cancelled`: Aborted by the client or agent.

---

## 4. Usage Examples

### Initializing and Starting a Session
```dart
import 'package:dart_acp/dart_acp.dart';

Future<void> main() async {
  // Assuming 'manager' is an instance of SessionManager
  final init = await manager.initialize();
  print('Negotiated Protocol: ${init.protocolVersion}');

  if (init.supportsListSessions) {
    final list = await manager.listSessions(cwd: '/project/root');
    for (final session in list.sessions) {
      print('Existing Session: ${session.sessionId} (${session.title})');
    }
  }

  final sessionId = await manager.newSession(workspaceRoot: '/project/root');
  print('New Session ID: $sessionId');
}
```

### Prompting and Streaming Updates
```dart
final updates = manager.prompt(
  sessionId: 'session-123',
  content: [
    {'type': 'text', 'text': 'Identify all TODOs in lib/'}
  ],
);

await for (final update in updates) {
  if (update is MessageDelta) {
    // Cascade notation used for builder patterns in related types
    final text = update.text; 
    print('Agent: $text');
  } else if (update is ToolCallUpdate) {
    final tc = update.toolCall;
    print('Tool [${tc.toolCallId}] Status: ${tc.status}');
  } else if (update is TurnEnded) {
    print('Turn finished: ${update.stopReason}');
  }
}
```

### Managing Configuration Options
```dart
// Fetch and update a config option
final options = await manager.setConfigOption(
  sessionId: 'session-123',
  configId: 'editor_mode',
  value: 'vim',
);

for (final opt in options) {
  print('Option ${opt.name} is now ${opt.currentValue}');
}
```
