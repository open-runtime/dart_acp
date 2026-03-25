# RPC Module Quickstart

## 1. Overview
The RPC module provides the underlying JSON-RPC 2.0 communication layer for the Agent Communication Protocol (ACP). It includes utilities to wrap a raw process's standard I/O into a line-delimited stream channel (`LineJsonChannel`) and a strongly-typed peer (`JsonRpcPeer`) to manage bidirectional requests, responses, and notifications.

## 2. Import
```dart
import 'package:dart_acp/src/rpc/line_channel.dart';
import 'package:dart_acp/src/rpc/peer.dart';
```

## 3. Setup
To set up the RPC connection, you need a running `Process`. Wrap its standard I/O using `LineJsonChannel`, and then initialize the `JsonRpcPeer` with the resulting stream channel.

```dart
import 'dart:io';
import 'package:dart_acp/src/rpc/line_channel.dart';
import 'package:dart_acp/src/rpc/peer.dart';

void main() async {
  // 1. Start the agent process
  final process = await Process.start('agent_executable', []);

  // 2. Wrap the process I/O in a line-delimited JSON channel
  final lineChannel = LineJsonChannel(
    process,
    onStderr: (line) => print('Agent Error: $line'),
    onInboundLine: (line) => print('<<< $line'), // Raw JSON received
    onOutboundLine: (line) => print('>>> $line'), // Raw JSON sent
  );

  // 3. Bind the JSON-RPC peer to the channel
  final peer = JsonRpcPeer(lineChannel.channel);

  // (Use the peer...)

  // 4. Cleanup when finished
  await peer.close();
  await lineChannel.dispose();
}
```

## 4. Common Operations

### Initializing the Protocol
Once the peer is connected, the first step is typically sending the `initialize` request to negotiate versions and capabilities.

```dart
final initResponse = await peer.initialize({
  'protocolVersion': 1,
  'clientCapabilities': {
    'fs': {
      'readTextFile': true,
      'writeTextFile': true,
    },
    'terminal': true,
  },
});
print('Agent Protocol Version: ${initResponse['protocolVersion']}');
```

### Managing Sessions
After initialization, you must create or load a session before sending prompts.

```dart
// Create a new session
final sessionResult = await peer.newSession({
  'cwd': Directory.current.absolute.path,
  'mcpServers': [], // Optional MCP server configurations
});
final sessionId = sessionResult['sessionId'] as String;

// (Optional) Load an existing session for replay
// await peer.loadSession({
//   'sessionId': 'previous_session_id',
//   'cwd': Directory.current.absolute.path,
//   'mcpServers': [],
// });
```

### Handling Agent Requests (Reverse RPC)
The agent may request host resources (like the filesystem or terminal). You handle these by assigning callbacks to the `JsonRpcPeer`.

```dart
// Filesystem: Read a file for the agent
peer.onReadTextFile = (Json params) async {
  final path = params['path'] as String;
  // File paths in ACP are always absolute
  return {'content': 'File contents of $path'};
};

// Filesystem: Write a file modified by the agent
peer.onWriteTextFile = (Json params) async {
  final path = params['path'] as String;
  final content = params['content'] as String;
  print('Writing $path...');
  return null; // Success
};

// Permissions: Authorize a tool call
peer.onRequestPermission = (Json params) async {
  // params contains 'toolCall' details and available 'options'
  return {
    'outcome': {
      'outcome': 'selected',
      'optionId': 'allow-once',
    }
  };
};

// Terminal: Create a new terminal for command execution
peer.onTerminalCreate = (Json params) async {
  // Returns a unique terminalId immediately
  return {'terminalId': 'term-${DateTime.now().millisecondsSinceEpoch}'};
};
```

### Sending Prompts and Handling Updates
You can send prompts to the agent and listen to streaming session updates (message chunks, tool calls, plans).

```dart
// Listen for real-time session updates
peer.sessionUpdates.listen((Json update) {
  final type = update['sessionUpdate'];
  print('Update received: $type');
});

// Send a prompt to the agent
final result = await peer.prompt({
  'sessionId': sessionId,
  'prompt': [
    {'type': 'text', 'text': 'List the files in the current directory'}
  ],
});
print('Turn stopped due to: ${result['stopReason']}');
```

### Controlling the Session
You can cancel ongoing turns or change the session mode.

```dart
// Cancel the current prompt turn
await peer.cancel({'sessionId': sessionId});

// Change the session mode (e.g., from 'ask' to 'code')
await peer.setSessionMode({
  'sessionId': sessionId,
  'modeId': 'code',
});
```

### Sending Raw Messages
For custom or extension methods (starting with `_`) not explicitly mapped, use `sendRaw` or `sendNotificationRaw`.

```dart
final customResult = await peer.sendRaw('_custom/method', {'foo': 'bar'});

await peer.sendNotificationRaw('_custom/event', {'status': 'ready'});
```

## 5. Configuration
The `LineJsonChannel` provides several debugging and configuration callbacks during instantiation:
*   `onStderr`: Consumes standard error output from the process to prevent blocking.
*   `onInboundLine`: Taps into raw JSON strings received from the agent (useful for logging).
*   `onOutboundLine`: Taps into raw JSON strings sent to the agent (useful for logging).

## 6. Related Modules
*   **Transport**: For higher-level lifecycle management of the subprocess (`lib/src/transport/`).
*   **Session**: The `SessionManager` coordinates multiple interactions over the `JsonRpcPeer` and uses structured models (`lib/src/session/`).
*   **Providers**: Host-side implementations for the agent request callbacks, such as `FsProvider` and `TerminalProvider` (`lib/src/providers/`).
*   **Models**: Structured Dart classes for content, updates, and session data (`lib/src/models/`).
