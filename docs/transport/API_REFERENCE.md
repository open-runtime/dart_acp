# Transport API Reference

The `Transport` module provides the foundational communication layer for the Agent Client Protocol (ACP). It abstracts underlying I/O (such as standard I/O, child processes, or mock streams) into a unified `StreamChannel<String>` used by the JSON-RPC layer.

## 1. Core Abstraction

### `AcpTransport`
An abstract base class for all ACP transport implementations. It defines the lifecycle for connecting to and disconnecting from an agent.

#### **Properties**
| Property | Type | Description |
| :--- | :--- | :--- |
| `channel` | `StreamChannel<String>` | The bi-directional JSON-RPC channel. Throws `StateError` if accessed before `start()`. |

#### **Methods**
| Method | Return Type | Description |
| :--- | :--- | :--- |
| `start()` | `Future<void>` | Initializes the transport, connects to the agent, and prepares the `channel`. |
| `stop()` | `Future<void>` | Gracefully shuts down the transport and cleans up all underlying resources. |

---

## 2. Implementations

### `StdioTransport`
The standard transport for local agents. It spawns the agent as a child process and communicates via `stdin` and `stdout`. It also monitors `stderr` for logging and tracks the process lifecycle.

#### **Constructor**
```dart
StdioTransport({
  required Logger logger,
  String? command,
  List<String> args = const [],
  Map<String, String> envOverrides = const {},
  String? cwd,
  void Function(String line)? onProtocolOut,
  void Function(String line)? onProtocolIn,
})
```

#### **Properties**
| Property | Type | Description |
| :--- | :--- | :--- |
| `command` | `String?` | The executable name or path to the agent (e.g., `'node'`, `'python'`). |
| `args` | `List<String>` | Command-line arguments passed to the agent. |
| `cwd` | `String?` | The working directory for the agent process. |
| `envOverrides` | `Map<String, String>` | Environment variables to merge into the agent's environment. |
| `logger` | `Logger` | Logger used for diagnostic information. |
| `onProtocolOut` | `Function(String)?` | Optional callback triggered for every raw JSON-RPC message sent to the agent. |
| `onProtocolIn` | `Function(String)?` | Optional callback triggered for every raw JSON-RPC message received from the agent. |
| `pid` | `int?` | The process ID of the agent (available after `start()`). |
| `exitCode` | `Future<int>?` | A future that completes with the agent's exit code when it terminates. |

---

### `StdinTransport`
A "direct" standard I/O transport that uses the current process's `stdin` and `stdout` (or provided custom streams). This is typically used when the ACP client itself is running as a sub-process or in specialized testing environments.

#### **Constructor**
```dart
StdinTransport({
  required Logger logger,
  void Function(String line)? onProtocolOut,
  void Function(String line)? onProtocolIn,
  Stream<List<int>>? inputStream,
  IOSink? outputSink,
})
```

#### **Properties**
| Property | Type | Description |
| :--- | :--- | :--- |
| `logger` | `Logger` | Logger used for diagnostic information. |
| `onProtocolOut` | `Function(String)?` | Optional callback for outbound protocol inspection. |
| `onProtocolIn` | `Function(String)?` | Optional callback for inbound protocol inspection. |
| `channel` | `StreamChannel<String>` | The bi-directional JSON-RPC channel. |

---

## 3. Usage Examples

### **Launching a Local Agent with `StdioTransport`**
This is the most common way to use ACP. The transport handles the process lifecycle, including cleanup when `stop()` is called.

```dart
import 'package:logging/logging.dart';
import 'package:dart_acp/dart_acp.dart';

void main() async {
  final logger = Logger('ACP');
  
  // Configure the transport
  final transport = StdioTransport(
    logger: logger,
    command: 'node',
    args: ['path/to/agent.js'],
    envOverrides: {'DEBUG': 'acp:*'},
    onProtocolIn: (line) => print('--> $line'),
    onProtocolOut: (line) => print('<-- $line'),
  );

  // Start the agent process
  await transport.start();
  print('Agent started with PID: ${transport.pid}');

  // Use the transport to start a client
  final client = await AcpClient.start(
    config: AcpConfig(
      agentCommand: 'node', // Not used if transport is provided
      logger: logger,
    ),
    transport: transport,
  );

  // ... interact with the agent ...

  // Stop the client and transport
  await client.dispose();
}
```

### **Testing with `StdinTransport`**
You can use `StdinTransport` with custom streams for unit or integration testing without spawning real processes.

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:logging/logging.dart';
import 'package:dart_acp/dart_acp.dart';

void main() async {
  final inputController = StreamController<List<int>>();
  
  // Custom transport with specific streams
  final transport = StdinTransport(
    logger: Logger('Test'),
    inputStream: inputController.stream,
    outputSink: stdout, // Redirect to current process stdout
  );

  await transport.start();
  
  // Simulate receiving a message from the "agent"
  inputController.add(utf8.encode('{"jsonrpc": "2.0", "method": "session/update", "params": {...}}\n'));
  
  // Inspect the channel
  transport.channel.stream.listen((message) {
    print('Received on channel: $message');
  });

  await transport.stop();
}
```

### **Extending Transport**
You can implement `AcpTransport` to support other protocols, such as TCP or WebSockets.

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:stream_channel/stream_channel.dart';
import 'package:dart_acp/dart_acp.dart';

class TcpTransport implements AcpTransport {
  final String host;
  final int port;
  Socket? _socket;
  StreamChannel<String>? _channel;

  TcpTransport(this.host, this.port);

  @override
  StreamChannel<String> get channel => _channel ?? (throw StateError('Not started'));

  @override
  Future<void> start() async {
    _socket = await Socket.connect(host, port);
    // Wrap the socket in a line-delimited String channel
    final stringStream = _socket!.transform(utf8.decoder).transform(const LineSplitter());
    _channel = StreamChannel<String>(stringStream, _socket!);
  }

  @override
  Future<void> stop() async {
    await _socket?.close();
  }
}
```
