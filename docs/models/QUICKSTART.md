# Models Quickstart

### 1. Overview
The Models module provides the core domain types and data structures for the Agent Context Protocol (ACP) Dart implementation. It includes comprehensive, strongly-typed representations for sessions, tools, content blocks, terminal events, diffs, and protocol updates, complete with JSON serialization and deserialization methods to interact with the ACP wire format safely.

### 2. Import
Import the specific model type definitions based on your needs directly from the `src/models` directory:

```dart
import 'package:dart_acp/src/models/command_types.dart';
import 'package:dart_acp/src/models/content_types.dart';
import 'package:dart_acp/src/models/diff_types.dart';
import 'package:dart_acp/src/models/session_types.dart';
import 'package:dart_acp/src/models/terminal_events.dart';
import 'package:dart_acp/src/models/tool_types.dart';
import 'package:dart_acp/src/models/types.dart';
import 'package:dart_acp/src/models/updates.dart';
```

### 3. Setup
The module primarily consists of data transfer objects (DTOs) and domain types. You do not need to instantiate a central manager; simply use the classes and their `fromJson` or `toJson` methods to parse and construct ACP payloads. 

```dart
import 'package:dart_acp/src/models/tool_types.dart';

// Parse a ToolCall from an ACP JSON payload
final payload = {
  'toolCallId': 'call_123',
  'status': 'in_progress',
  'kind': 'execute',
  'title': 'Run unit tests'
};

final toolCall = ToolCall.fromJson(payload);
print(toolCall.toolCallId); // "call_123"
```

### 4. Common Operations

#### Handling Content Blocks
ACP uses heterogeneous content blocks (Text, Images, Resources). The `ContentBlock.fromJson` factory handles type resolution for you.

```dart
import 'package:dart_acp/src/models/content_types.dart';

void processContent(Map<String, dynamic> json) {
  final block = ContentBlock.fromJson(json);

  if (block is TextContent) {
    print('Text: ${block.text}');
  } else if (block is ImageContent) {
    print('Image (MIME: ${block.mimeType}): ${block.data.substring(0, 10)}...');
  } else if (block is ResourceContent) {
    print('Resource URI: ${block.uri}, Title: ${block.title}');
  } else if (block is UnknownContent) {
    print('Unknown content type: ${block.data}');
  }
}
```

#### Processing Session Updates
The `updates.dart` library models different types of ACP session events using the sealed `AcpUpdate` class.

```dart
import 'package:dart_acp/src/models/updates.dart';
import 'package:dart_acp/src/models/content_types.dart';

void handleAcpUpdate(AcpUpdate update) {
  print('Update text: ${update.text}');

  if (update is MessageDelta) {
    print('Author: ${update.role} (Thought: ${update.isThought})');
    for (final block in update.content) {
      if (block is TextContent) print(block.text);
    }
  } else if (update is ToolCallUpdate) {
    final tool = update.toolCall;
    print('Tool ${tool.toolCallId} changed status to ${tool.status.toWire()}');
  } else if (update is PlanUpdate) {
    print('Plan title: ${update.plan.title}');
  } else if (update is TurnEnded) {
    print('Turn stopped because: ${update.stopReason.name}');
  }
}
```

#### Managing Terminal Events
Terminal streams and lifecycle statuses are mapped to `TerminalEvent` subclasses.

```dart
import 'package:dart_acp/src/models/terminal_events.dart';

void onTerminalEvent(TerminalEvent event) {
  if (event is TerminalCreated) {
    print('Created terminal ${event.terminalId} for cmd: ${event.command}');
  } else if (event is TerminalOutputEvent) {
    print('Terminal ${event.terminalId} output: ${event.output}');
    if (event.exitCode != null) {
      print('Terminal exited with code ${event.exitCode}');
    }
  } else if (event is TerminalExited) {
    print('Terminal ${event.terminalId} exited: ${event.code}');
  }
}
```

#### Working with Sessions and Capabilities
Agents and clients negotiate session details using `SessionCapabilities` and `ConfigOption`.

```dart
import 'package:dart_acp/src/models/session_types.dart';

void examineSession(SessionResult result) {
  print('Session ID: ${result.sessionId}');
  
  if (result.configOptions != null) {
    for (final option in result.configOptions!) {
      print('Config ${option.name} (Current: ${option.currentValue})');
      for (final choice in option.options) {
        print('  - Choice: ${choice.name} (${choice.value})');
      }
    }
  }
}
```

### 5. Configuration
The models themselves are stateless and do not require configuration. However, `SessionCapabilities` dictates what session operations (`list`, `resume`, `fork`, `configOptions`) are officially supported by the current agent. These are represented in wire format during the agent initialization phase.

### 6. Related Modules
- **Session:** Uses these models in `session_manager.dart` to maintain state.
- **Providers:** Subsystems like `terminal_provider.dart` emit `TerminalEvent` objects.
- **RPC:** Serializes and deserializes these objects over the wire transport.