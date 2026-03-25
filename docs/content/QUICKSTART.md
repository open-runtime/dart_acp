# Content Module Quickstart

## 1. Overview
The Content module provides utilities for parsing user prompts and converting them into structured content blocks. Its primary features include:
- **`ContentBuilder`**: Extracts `@-mentions` for files and URLs, automatically resolves paths (including tilde expansion), and detects MIME types.
- **`ContentBlock` Hierarchy**: Structured models for `text`, `image`, and `resource_link` blocks that form the basis of ACP message payloads.

## 2. Import
To use the `ContentBuilder` and related models, import them into your Dart project:

```dart
// To use the ContentBuilder utility
import 'package:dart_acp/src/content/content_builder.dart';

// To use structured content block models
import 'package:dart_acp/dart_acp.dart';
```

## 3. Setup
The `ContentBuilder` class provides static utility methods for processing user text. The content models (`TextContent`, `ImageContent`, `ResourceContent`) are immutable and can be instantiated directly using named arguments.

## 4. Common Operations

### Parsing Prompts with @-Mentions
Extract local file mentions and URLs from a user's prompt and convert them into structured resource links.

```dart
final prompt = 'Summarize @README.md and check @https://example.com/api';
final blocks = ContentBuilder.buildFromPrompt(prompt);

// Resulting `blocks` will contain:
// 1. TextContent: 'Summarize @README.md and check @https://example.com/api'
// 2. ResourceContent (file): uri: 'file:///.../README.md', mimeType: 'text/markdown'
// 3. ResourceContent (URL): uri: 'https://example.com/api', mimeType: 'application/json'
```

### Supported Mentions
`ContentBuilder` supports several formats for referencing external context:
- **Files**: `@file.txt` or `@"path/with spaces/file.dart"`
- **Home Directory**: `@~/config.yaml` (automatically expands to the user's home directory)
- **URLs**: `@https://github.com/zed-industries/agent-client-protocol`

### Specifying a Custom Workspace Root
By default, relative file paths are resolved against the current working directory. Provide a `workspaceRoot` to override this:

```dart
final blocks = ContentBuilder.buildFromPrompt(
  'Review @src/app.dart', 
  workspaceRoot: '/home/user/project',
);
```

## 5. Manual Content Creation
While `ContentBuilder` handles parsing, you can also construct content blocks manually using the model classes.

### Text Content
Represent plain text messages or assistant responses.

```dart
final textBlock = TextContent(
  text: 'Hello! How can I help you today?',
);
```

### Image Content
Send base64-encoded images for analysis.

```dart
final imageBlock = ImageContent(
  mimeType: 'image/png',
  data: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB...', // Base64 data
);
```

### Resource Content (Resource Link)
Reference files or URLs explicitly.

```dart
final resourceLink = ResourceContent(
  uri: 'file:///path/to/script.py',
  title: 'script.py',
  mimeType: 'text/x-python',
);
```

## 6. Stop Reasons
When a prompt turn completes, the agent reports a `StopReason` to indicate why it stopped:

- **`StopReason.endTurn`**: The model finished successfully.
- **`StopReason.maxTokens`**: Hit the model's token limit.
- **`StopReason.maxTurnRequests`**: Too many tool calls in one turn.
- **`StopReason.cancelled`**: The client cancelled the request.
- **`StopReason.refusal`**: The agent refused to continue.

## 7. Configuration
The primary configuration for content processing is the `workspaceRoot` parameter in `ContentBuilder.buildFromPrompt()`:
- **`workspaceRoot`**: An optional `String`. When provided, relative paths from `@-mentions` are resolved against this directory. Defaults to `Directory.current.path`.

## 8. Related Modules
- **Models**: The `lib/src/models/content_types.dart` file defines the structured classes used by this module.
- **Transport / Session**: These modules consume the structured content lists to send messages over the ACP channel.
