# Rpc Module API Reference

The `Rpc` module provides the low-level transport and protocol handling for the Agent Client Protocol (ACP). It manages JSON-RPC communication over standard I/O (stdio) and provides a typed interface for ACP methods and notifications.

*Note: `Json` is used throughout this module as a typedef for `Map<String, dynamic>`.*

## 1. Classes

### **LineJsonChannel**
Wraps a process's stdio as a line-delimited JSON `StreamChannel`. This is the foundational transport for communicating with an ACP agent.

- **Constructors:**
  - `LineJsonChannel(Process process, {void Function(String)? onStderr, void Function(String line)? onInboundLine, void Function(String line)? onOutboundLine})`
    Creates a line-delimited channel around a running [Process].
    - `onStderr`: Callback for lines written to the process's stderr.
    - `onInboundLine`: Callback for raw lines received from the process's stdout.
    - `onOutboundLine`: Callback for raw lines sent to the process's stdin.

- **Fields:**
  - `Process process` — The underlying process being wrapped.
  - `StreamChannel<String> channel` — The stream channel used by the `JsonRpcPeer`.
  - `void Function(String line)? onInboundLine` — Optional hook for raw inbound message inspection.
  - `void Function(String line)? onOutboundLine` — Optional hook for raw outbound message inspection.

- **Methods:**
  - `Future<void> dispose()`
    Stops listening to the process streams, flushes stdin, and closes the channel.

---

### **JsonRpcPeer**
A thin wrapper around `json_rpc_2.Peer` that provides typed methods for ACP requests and hooks for handling client-side requests from the agent.

- **Constructors:**
  - `JsonRpcPeer(StreamChannel<String> channel)`
    Binds a new JSON-RPC peer to the provided [StreamChannel].

- **Fields:**
  - `Stream<Json> sessionUpdates` — A broadcast stream of raw `session/update` notifications from the agent.
  - `Future<dynamic> Function(Json)? onReadTextFile` — Handler invoked when the agent requests `fs/read_text_file`.
  - `Future<dynamic> Function(Json)? onWriteTextFile` — Handler invoked when the agent requests `fs/write_text_file`.
  - `Future<dynamic> Function(Json)? onRequestPermission` — Handler invoked when the agent requests `session/request_permission`.
  - `Future<dynamic> Function(Json)? onTerminalCreate` — Handler invoked when the agent requests `terminal/create`.
  - `Future<dynamic> Function(Json)? onTerminalOutput` — Handler invoked when the agent requests `terminal/output`.
  - `Future<dynamic> Function(Json)? onTerminalWaitForExit` — Handler invoked when the agent requests `terminal/wait_for_exit`.
  - `Future<dynamic> Function(Json)? onTerminalKill` — Handler invoked when the agent requests `terminal/kill`.
  - `Future<dynamic> Function(Json)? onTerminalRelease` — Handler invoked when the agent requests `terminal/release`.

- **Methods:**
  - `Future<void> close()`
    Closes the peer and stops all message processing.
  - `Future<Json> initialize(Json params)`
    Sends an `initialize` request to the agent.
    - *Example Params:* `{'protocolVersion': 1, 'clientCapabilities': {...}}`
  - `Future<Json> newSession(Json params)`
    Sends a `session/new` request to create a conversation.
    - *Example Params:* `{'cwd': '/path/to/project', 'mcpServers': []}`
  - `Future<void> loadSession(Json params)`
    Sends a `session/load` request to resume a session (replay mode).
  - `Future<Json> prompt(Json params)`
    Sends a `session/prompt` request to start an agent turn.
    - *Example Params:* `{'sessionId': 'sess_123', 'prompt': [{'type': 'text', 'text': '...'}]}`
  - `Future<void> cancel(Json params)`
    Sends a `session/cancel` notification to interrupt the current turn.
  - `Future<void> setSessionMode(Json params)`
    (Extension) Sends a `session/set_mode` request to change the active mode.
  - `Future<Json> sendRaw(String method, Json params)`
    Sends an arbitrary JSON-RPC request by method name.
  - `Future<void> sendNotificationRaw(String method, Json params)`
    Sends an arbitrary JSON-RPC notification.

---

## 2. Usage Examples

### **Initializing a Connection**
This example shows how to launch an agent process, wrap it in a channel, and initialize the ACP connection.

```dart
import 'dart:io';
import 'package:dart_acp/dart_acp.dart';
import 'package:dart_acp/src/rpc/line_channel.dart';
import 'package:dart_acp/src/rpc/peer.dart';

void main() async {
  // 1. Launch the agent process
  final process = await Process.start('my-agent-binary', []);

  // 2. Create the transport channel (stdio wrapper)
  final channel = LineJsonChannel(
    process,
    onStderr: (line) => print('Agent Stderr: $line'),
  );

  // 3. Bind the JSON-RPC peer
  final peer = JsonRpcPeer(channel.channel);

  // 4. Negotiate protocol and capabilities
  final result = await peer.initialize({
    'protocolVersion': 1,
    'clientCapabilities': {
      'fs': {'readTextFile': true, 'writeTextFile': true},
      'terminal': true,
    },
  });

  print('Initialized with protocol version: ${result['protocolVersion']}');
}
```

### **Handling Session Updates**
The agent streams progress via `session/update` notifications. You can listen to these raw updates via the `sessionUpdates` stream.

```dart
void setupUpdateListener(JsonRpcPeer peer) {
  peer.sessionUpdates.listen((update) {
    // raw session/update notification payload
    final sessionId = update['sessionId'] as String;
    final payload = update['update'] as Map<String, dynamic>;
    
    print('Update for session $sessionId: ${payload['sessionUpdate']}');
  });
}
```

### **Registering Agent-to-Client Handlers**
To support agent operations like reading files or running commands, you must register the appropriate handlers on the peer.

```dart
void registerClientHandlers(JsonRpcPeer peer) {
  // Handle file read requests from the agent
  peer.onReadTextFile = (params) async {
    final path = params['path'] as String;
    try {
      final file = File(path);
      final content = await file.readAsString();
      return {'content': content};
    } catch (e) {
      throw Exception('Failed to read file: $e');
    }
  };

  // Handle permission requests for tool calls
  peer.onRequestPermission = (params) async {
    print('Agent is requesting permission for tool: ${params['toolCall']['title']}');
    return {
      'outcome': {
        'outcome': 'selected',
        'optionId': 'allow-once',
      }
    };
  };
}
```

### **Using Model Classes with Peer**
While the `JsonRpcPeer` methods take and return `Json` maps, you can use the model classes from `package:dart_acp/dart_acp.dart` to construct and parse these payloads.

```dart
import 'package:dart_acp/dart_acp.dart';

Future<void> sendPrompt(JsonRpcPeer peer, String sessionId, String userText) async {
  // Construct a prompt using models
  final promptRequest = {
    'sessionId': sessionId,
    'prompt': [
      TextContent(text: userText).toJson(),
    ],
  };

  // Send the request
  final response = await peer.prompt(promptRequest);

  // Parse the stop reason using the StopReason enum
  final stopReason = response['stopReason'] as String;
  print('Turn ended with reason: $stopReason');
}
```

---

## 3. Reference Enums
These enums are commonly used when processing RPC payloads. (See [Models Reference](../models/API_REFERENCE.md) for full details).

- **StopReason**: `endTurn`, `maxTokens`, `maxTurnRequests`, `cancelled`, `refusal`, `other`
- **ToolCallStatus**: `pending`, `inProgress`, `completed`, `failed`, `cancelled`
- **PlanEntryStatus**: `pending`, `inProgress`, `completed`
- **PlanEntryPriority**: `high`, `medium`, `low`
