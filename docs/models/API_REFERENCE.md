# Models API Reference

The Models module provides the core data structures for the Agentic Control Protocol (ACP). These classes represent sessions, content blocks, execution plans, tool calls, and real-time updates.

## Importing Models

All models are exported from the main package:

```dart
import 'package:dart_acp/dart_acp.dart';
```

---

## Session Management

These models handle session lifecycle, enumeration, and configuration.

### SessionInfo
Information about a session returned by `session/list`.

- **sessionId**: `String` - Unique session identifier.
- **cwd**: `String` - Working directory for this session.
- **title**: `String?` - Human-readable title.
- **updatedAt**: `DateTime?` - Last updated timestamp.
- **meta**: `Map<String, dynamic>?` - Agent-specific metadata.

### SessionResult
Result of session creation or resumption (`session/new`, `session/load`, `session/resume`, `session/fork`).

- **sessionId**: `String` - The session ID.
- **configOptions**: `List<ConfigOption>?` - Available configuration options.
- **meta**: `Map<String, dynamic>?` - Agent-specific metadata.

### SessionCapabilities
Capabilities advertised by an agent for session management.

- **list**: `bool` - Agent supports `session/list`.
- **resume**: `bool` - Agent supports `session/resume`.
- **fork**: `bool` - Agent supports `session/fork`.
- **configOptions**: `bool` - Agent supports `configOptions` in session responses.

### ConfigOption
A configuration option available for a session (e.g., model selection, temperature).

- **id**: `String` - Unique identifier for this option.
- **name**: `String` - Human-readable name.
- **type**: `String` - Option type (currently "select").
- **currentValue**: `String` - Currently selected value.
- **options**: `List<ConfigOptionChoice>` - Available choices.
- **description**: `String?` - Optional description.
- **group**: `String?` - Optional group for organization.

---

## Messages & Content

ACP messages are composed of content blocks.

### ContentBlock (Sealed)
Base class for all content types. Use `ContentBlock.fromJson()` to polymorphically parse blocks.

#### TextContent
Represents a simple text block.
- **text**: `String` - The text content.

#### ImageContent
Represents an embedded image.
- **mimeType**: `String` - MIME type (e.g., `image/png`).
- **data**: `String` - Base64-encoded image data.

#### ResourceContent
Represents a link to an external resource or file.
- **uri**: `String` - URI of the resource.
- **title**: `String?` - Optional title.
- **mimeType**: `String?` - Optional MIME type.

**Example: Constructing Content**
```dart
final text = TextContent(text: 'Hello, world!');

final image = ImageContent(
  mimeType: 'image/png',
  data: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BfAQJ3AfVf8f9mAAAAAElFTkSuQmCC',
);

final resource = ResourceContent(
  uri: 'file:///home/user/project/main.dart',
  title: 'main.dart',
  mimeType: 'text/x-dart',
);
```

---

## Execution Plans & Commands

Agents use plans to communicate their intended steps and available interactive commands.

### Plan
An execution plan with structured entries.

- **title**: `String?` - Title of the plan.
- **description**: `String?` - Overall description.
- **entries**: `List<PlanEntry>` - List of plan steps.
- **metadata**: `Map<String, dynamic>?` - Agent-specific metadata.

### PlanEntry
A single step in an execution plan.

- **content**: `String` - Description of this step.
- **priority**: `PlanEntryPriority` - Priority level (`high`, `medium`, `low`).
- **status**: `PlanEntryStatus` - Execution status (`pending`, `inProgress`, `completed`).
- **metadata**: `Map<String, dynamic>?` - Agent-specific metadata.

### AvailableCommand
A command that the user can execute in the current context.

- **name**: `String` - Identifier of the command.
- **description**: `String?` - Human-readable description.
- **parameters**: `Map<String, dynamic>?` - Parameters for the command.
- **input**: `AvailableCommandInput?` - Input specification.

**Example: Building a Plan**
```dart
final plan = Plan(
  title: 'Bug Fix',
  description: 'Investigate and fix the login issue',
  entries: [
    PlanEntry(
      content: 'Reproduce the bug in tests',
      priority: PlanEntryPriority.high,
      status: PlanEntryStatus.completed,
    ),
    PlanEntry(
      content: 'Apply fix to auth_service.dart',
      priority: PlanEntryPriority.high,
      status: PlanEntryStatus.inProgress,
    ),
  ],
);
```

---

## Tool Calls & Diffs

Models for representing agent-invoked tools and proposed file changes.

### ToolCall
Information about a tool invocation.

- **toolCallId**: `String` - Unique identifier for this tool call.
- **status**: `ToolCallStatus` - Current status (`pending`, `inProgress`, `completed`, `failed`, `cancelled`).
- **title**: `String?` - Human-readable title of what the tool is doing.
- **kind**: `ToolKind?` - Category (e.g., `read`, `edit`, `execute`).
- **locations**: `List<ToolCallLocation>?` - Affected file paths.
- **rawInput**: `dynamic` - Parameters sent to the tool.
- **rawOutput**: `dynamic` - Results returned by the tool.

### Diff
A collection of changes proposed for a file.

- **id**: `String` - Unique identifier for the diff.
- **status**: `DiffStatus` - Current status (`started`, `applied`, `rejected`, `error`).
- **uri**: `String?` - URI of the file being modified.
- **changes**: `List<DiffChange>` - List of specific line changes.
- **description**: `String?` - Description of the change.

---

## Session Updates (AcpUpdate)

Updates are streamed from the agent to communicate progress within a session.

| Type | Description |
| :--- | :--- |
| **PlanUpdate** | Contains the current execution plan. |
| **MessageDelta** | A chunk of message content (text or thoughts). |
| **ToolCallUpdate** | Progress update for a tool call. |
| **DiffUpdate** | A proposed file diff. |
| **AvailableCommandsUpdate** | List of commands currently available. |
| **TurnEnded** | Indicates the current prompt turn is complete. |
| **ModeUpdate** | Indicates a change in the session mode. |
| **UnknownUpdate** | Fallback for unclassified updates. |

---

## Enums

### ToolCallStatus
- `pending` - Awaiting execution or approval.
- `inProgress` - Currently running.
- `completed` - Finished successfully.
- `failed` - Terminated with an error.
- `cancelled` - Stopped by the user or client.

### PlanEntryStatus
- `pending` - Not yet started.
- `inProgress` - Active.
- `completed` - Finished.

### StopReason
Used in `TurnEnded` to indicate why a turn finished.
- `endTurn` - Natural completion.
- `maxTokens` - Hit token limit.
- `maxTurnRequests` - Hit request limit.
- `cancelled` - Explicitly cancelled.
- `refusal` - Agent refused to answer.
- `other` - Unknown reason.

### ToolKind
- `read`, `edit`, `delete`, `move`, `search`, `execute`, `think`, `fetch`, `other`.
