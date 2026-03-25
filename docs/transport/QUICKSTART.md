# Transport Module Quickstart

## 1. Overview
The Transport module provides the communication layer for the Agent Communication Protocol (ACP), abstracting the underlying connections. It includes:
- **AcpTransport**: The base interface for all transport implementations.
- **StdioTransport**: Spawns and communicates with a child agent process via `stdin`, `stdout`, and `stderr`.
- **StdinTransport**: Communicates over standard I/O streams without spawning a process, ideal for agents running directly in the current process or for testing.

## 2. Import
To use the transport implementations, import the main package:

```dart
import 'package:dart_acp/dart_acp.dart';
import 'package:logging/logging.dart'; // Required for the logger parameter
```

## 3. Setup
You can set up a transport by instantiating either `StdioTransport` or `StdinTransport`.

### Spawning an Agent Process (StdioTransport)
`StdioTransport` is used when you need to manage a separate agent process.

```dart
final logger = Logger('AcpTransport');

final transport = StdioTransport(
  logger: logger,
  // Agent executable name/path.
  command: 'python3',
  // Arguments passed to the agent.
  args: ['agent.py'],
  // Optional working directory for the agent process.
  cwd: '/path/to/agent/dir',
  // Environment variable overlay for the agent process.
  envOverrides: {'AGENT_ENV': 'production'},
  // Optional callbacks for protocol monitoring.
  onProtocolIn: (line) => logger.finer('Received frame: $line'),
  onProtocolOut: (line) => logger.finer('Sending frame: $line'),
);
```

### Communicating via Standard Streams (StdinTransport)
`StdinTransport` allows the ACP client to communicate with an agent via standard I/O streams directly.

```dart
final transport = StdinTransport(
  logger: Logger('AcpTransport'),
  // Optional callbacks for protocol monitoring.
  onProtocolIn: (line) => print('Inbound: $line'),
  onProtocolOut: (line) => print('Outbound: $line'),
);
```

## 4. Common Operations

### Starting and Stopping
Before communicating, you must start the transport. When finished, stop it to clean up resources.

```dart
// Start the transport (spawns process for StdioTransport)
await transport.start();

// ... communicate ...

// Stop the transport (terminates process for StdioTransport)
await transport.stop();
```

### Accessing the Channel
Once started, you can access the bi-directional `StreamChannel<String>` to send and receive protocol messages. This channel is typically consumed by a JSON-RPC `Peer`.

```dart
final channel = transport.channel;

// Listen for incoming messages
channel.stream.listen((message) {
  print('Received from agent: $message');
});

// Send a message to the agent
channel.sink.add('{"jsonrpc":"2.0","method":"ping","id":1}');
```

### Process Management (StdioTransport Only)
For `StdioTransport`, you can monitor the lifecycle of the spawned process.

```dart
if (transport is StdioTransport) {
  // Access the PID of the spawned agent process
  print('Agent PID: ${transport.pid}');

  // Wait for the agent to exit
  transport.exitCode?.then((code) {
    print('Agent process exited with code $code');
  });
}
```

## 5. Advanced Usage

### Testing with Custom Streams
`StdinTransport` supports providing custom input and output streams, which is useful for unit testing or embedding the transport in custom environments.

```dart
import 'dart:async';
import 'dart:io';

final inputController = StreamController<List<int>>();
final outputBuffer = BytesBuilder();

final testTransport = StdinTransport(
  logger: Logger('TestTransport'),
  inputStream: inputController.stream,
  // Using a custom IOSink for the output
  outputSink: IOSink(StreamController<List<int>>().sink), 
);

await testTransport.start();
```

## 6. Configuration Details
- **Logging**: Both transports require a `Logger` instance from the `logging` package to capture internal diagnostics and errors.
- **Environment**: `StdioTransport` inherits the environment from `Platform.environment` and applies `envOverrides`.
- **Protocol Monitoring**: `onProtocolIn` and `onProtocolOut` provide access to the raw string frames before they are parsed as JSON-RPC, which is essential for low-level debugging.

## 7. Integration
The Transport module is designed to work seamlessly with the RPC module:
- The `channel` property is passed to a `Peer` or `LineJsonChannel`.
- The `SessionManager` typically handles the instantiation and lifecycle of the transport based on the provided configuration.