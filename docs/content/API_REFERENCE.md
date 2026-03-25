# Content API Reference

The Content module handles the representation and parsing of message content in the ACP (Agent Control Protocol). It supports various content types such as text, images, and resource references, and provides utilities for building content from user prompts.

### 1. Classes

#### ContentBlock
Abstract base class for all content blocks in a message.

- **Methods**:
  - `Map<String, dynamic> toJson()`: Converts the content block to a JSON-serializable map for wire transmission.
  - `static ContentBlock fromJson(Map<String, dynamic> json)`: Factory method that creates a specific `ContentBlock` subclass based on the `type` field in the JSON.

#### TextContent
A content block containing plain text.

- **Properties**:
  - `String text`: The actual text content.
- **Constructors**:
  - `TextContent({required String text})`: Creates a new text content block.
- **Example**:
  ```dart
  import 'package:dart_acp/dart_acp.dart';

  final textBlock = TextContent(text: 'Hello from ACP!');
  ```

#### ImageContent
A content block containing an image.

- **Properties**:
  - `String mimeType`: MIME type of the image (e.g., 'image/png', 'image/jpeg').
  - `String data`: Base64-encoded image data.
- **Constructors**:
  - `ImageContent({required String mimeType, required String data})`: Creates a new image content block.
- **Example**:
  ```dart
  import 'package:dart_acp/dart_acp.dart';

  final imageBlock = ImageContent(
    mimeType: 'image/png',
    data: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BHAAtfAv0pCvsAAAAASUVORK5CYII=',
  );
  ```

#### ResourceContent
A content block representing a link to a resource, such as a local file or a remote URL.

- **Properties**:
  - `String uri`: URI of the resource.
  - `String? title`: Optional human-readable title for the resource.
  - `String? mimeType`: Optional MIME type of the resource.
- **Constructors**:
  - `ResourceContent({required String uri, String? title, String? mimeType})`: Creates a new resource link content block.
- **Example**:
  ```dart
  import 'package:dart_acp/dart_acp.dart';

  final resourceBlock = ResourceContent(
    uri: 'file:///path/to/source.dart',
    title: 'source.dart',
    mimeType: 'text/x-dart',
  );
  ```

#### UnknownContent
A content block for unknown or unrecognized types, ensuring forward compatibility with future ACP extensions.

- **Properties**:
  - `Map<String, dynamic> data`: The raw JSON data for the unknown content type.
- **Constructors**:
  - `UnknownContent(Map<String, dynamic> data)`: Creates an unknown content block with the provided raw data.

#### ContentBuilder
A utility class for building content blocks from user prompt strings, specifically supporting @-mentions.

- **Methods**:
  - `static List<Map<String, dynamic>> buildFromPrompt(String prompt, {String? workspaceRoot})`: Parses a prompt string and returns a list of content blocks (as maps). It automatically extracts @-mentions and converts them into `resource_link` blocks.
- **Supported @-mention formats**:
  - Files: `@file.txt` or `@"path with spaces/file.txt"`
  - URLs: `@https://example.com/file`
  - Tilde expansion: `@~/Documents/file.txt`
- **Example**:
  ```dart
  import 'package:dart_acp/src/content/content_builder.dart';

  final prompt = 'Please review @main.dart and compare it with @https://docs.example.com/api';
  final blocks = ContentBuilder.buildFromPrompt(prompt, workspaceRoot: '/home/user/project');
  // Returns a list containing:
  // 1. A text block with the original prompt
  // 2. A resource_link block for main.dart
  // 3. A resource_link block for the URL
  ```

### 2. Enums

*(No public enums defined in this module)*

### 3. Extensions

*(No public extensions defined in this module)*

### 4. Top-Level Functions

*(No public top-level functions defined in this module)*