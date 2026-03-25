# Providers Module Quickstart

## 1. Overview
The Providers module defines the abstraction layers for file system access, terminal command execution, and permission prompting within an agentic environment. It provides default implementations with built-in security features, such as workspace jailing for file operations and sensible default policies for tool permissions.

## 2. Import
The most common way to use the providers is to import the main library:
```dart
import 'package:dart_acp/dart_acp.dart';
```

Or you can import the specific provider headers:
```dart
import 'package:dart_acp/src/providers/fs_provider.dart';
import 'package:dart_acp/src/providers/permission_provider.dart';
import 'package:dart_acp/src/providers/terminal_provider.dart';
```

## 3. Setup
You can instantiate the default providers directly. They are designed to be immediately usable with standard configurations.

```dart
// 1. Setup File System Provider (enforces a workspace jail)
final fsProvider = DefaultFsProvider(
  workspaceRoot: '/home/user/workspace',
  allowReadOutsideWorkspace: false, // Strict jail (default)
);

// 2. Setup Permission Provider (with optional callback override)
final permissionProvider = DefaultPermissionProvider(
  onRequest: (options) async {
    // Custom permission logic (e.g., prompt the user)
    // options.title, options.rationale, options.toolName, etc.
    return PermissionOutcome.allow;
  },
);

// 3. Setup Terminal Provider (uses system shell by default)
final terminalProvider = DefaultTerminalProvider();
```

## 4. Common Operations

### Reading and Writing Files (`FsProvider`)
All operations are resolved relative to the `workspaceRoot`.

```dart
// Read a file within the workspace root
// Throws FileSystemException if the file is missing or outside jail
final content = await fsProvider.readTextFile('lib/main.dart');

// Read a specific line range (e.g., 5 lines starting from line 10)
final snippet = await fsProvider.readTextFile(
  'lib/main.dart',
  line: 10,  // 1-based starting line
  limit: 5,  // Number of lines to return
);

// Write to a file (will throw FileSystemException if outside workspace)
// Automatically creates parent directories if they don't exist.
await fsProvider.writeTextFile('output/log.txt', 'Process completed.');
```

### Requesting Permissions (`PermissionProvider`)
The `PermissionProvider` acts as the gatekeeper for agent-initiated tools.

```dart
final options = PermissionOptions(
  title: 'Delete File',
  rationale: 'The agent wants to delete temporary files to clean up.',
  options: ['Allow', 'Deny'],
  sessionId: 'session_123',
  toolName: 'fs.delete',
  toolKind: 'write',
);

final outcome = await permissionProvider.request(options);

switch (outcome) {
  case PermissionOutcome.allow:
    print('Permission granted!');
    break;
  case PermissionOutcome.deny:
    print('Permission denied by user or policy.');
    break;
  case PermissionOutcome.cancelled:
    print('The permission prompt was cancelled before a decision was made.');
    break;
}
```

### Running Terminal Commands (`TerminalProvider`)
The `TerminalProvider` manages OS processes, buffering their output for asynchronous retrieval.

```dart
// Create a terminal process with specific environment and directory
final handle = await terminalProvider.create(
  sessionId: 'session_123',
  command: 'ls',
  args: ['-la'],
  cwd: '/home/user/workspace',
  env: {'DEBUG': 'true'},
);

// Check terminal ID if needed
print('Started terminal: ${handle.terminalId}');

// Read the buffered output at any time
final output = await terminalProvider.currentOutput(handle);
print('Current Output:\n$output');

// Kill the process if it's taking too long
// await terminalProvider.kill(handle);

// Wait for the process to exit and get the status code
final exitCode = await terminalProvider.waitForExit(handle);
print('Process exited with code: $exitCode');

// Clean up resources and subscriptions
await terminalProvider.release(handle);
```

## 5. Configuration and Details

### Workspace Jail (`DefaultFsProvider`)
- **Write Safety**: Writes are *strictly* constrained within `workspaceRoot`. Attempting to write via `../` outside the root will throw a `FileSystemException`.
- **Read Flexibility**: By setting `allowReadOutsideWorkspace: true`, the provider can read system files or files outside the project, while still blocking all external writes.

### Default Permissions (`DefaultPermissionProvider`)
- **Default Policy**: If no `onRequest` callback is provided, the default provider implements a simple security policy:
  - **Allow**: Any `toolKind` matching 'read' or `toolName` containing 'read'.
  - **Deny**: All other operations (write, execute, delete, etc.).

### Terminal Execution (`DefaultTerminalProvider`)
- **Shell Invocations**: If `args` is empty, the provider runs the command through a shell (`bash -lc` or `sh -c` on Unix; `cmd.exe /C` on Windows).
- **Direct Execution**: If `args` is provided, the command is executed directly as a process.
- **Output Buffering**: Stdout and Stderr are merged into a single UTF-8 buffer (using `allowMalformed: true` to prevent crashes on binary data).

## 6. Related Modules
- **Security**: The `DefaultFsProvider` relies on `WorkspaceJail` to safely resolve paths and prevent directory traversal attacks.
- **Session Manager**: Typically coordinates the providers during an active ACP session.