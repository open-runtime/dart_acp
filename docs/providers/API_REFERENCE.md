# Providers API Reference

The Providers module defines the abstraction layers for system-level operations such as file system access, terminal management, and permission handling. These abstractions allow the ACP client to enforce security policies (like workspace jails) and provide custom implementations for different environments.

---

### 1. Classes

#### **PermissionOptions**
Structured permission request options sent to a `PermissionProvider` when an agent requests a sensitive operation.

*   **Fields:**
    *   `String title` - Display title of the permission prompt.
    *   `String rationale` - Rationale for the permission request provided by the agent.
    *   `List<String> options` - Display-only option names provided by the agent (e.g., "Allow once", "Always allow").
    *   `String sessionId` - Owning session identifier.
    *   `String toolName` - Agent-provided tool name (e.g., `write_file`).
    *   `String? toolKind` - Tool kind (`read`, `edit`, `execute`, etc.), if provided.
*   **Constructors:**
    *   `PermissionOptions({required String title, required String rationale, required List<String> options, required String sessionId, required String toolName, String? toolKind})`
*   **Example:**
    ```dart
    final options = PermissionOptions(
      title: 'Allow File Write',
      rationale: 'The agent needs to update the project configuration.',
      options: ['Allow', 'Deny'],
      sessionId: 'session-123',
      toolName: 'write_file',
      toolKind: 'edit',
    );
    ```

#### **PermissionProvider**
Abstract interface for answering permission requests. Implement this to provide custom UI prompts or policy-based auto-approval.

*   **Methods:**
    *   `Future<PermissionOutcome> request(PermissionOptions options)` - Returns a decision (`allow`, `deny`, or `cancelled`) for the given request.

#### **DefaultPermissionProvider**
A standard implementation of `PermissionProvider` that uses a simple default policy or a custom callback.

*   **Fields:**
    *   `PermissionCallback? onRequest` - Optional callback invoked to determine the outcome.
*   **Constructors:**
    *   `DefaultPermissionProvider({PermissionCallback? onRequest})`
*   **Methods:**
    *   `Future<PermissionOutcome> request(PermissionOptions options)` - If `onRequest` is provided, it is invoked; otherwise, it allows `read` operations and denies others by default.
*   **Example:**
    ```dart
    import 'package:dart_acp/dart_acp.dart';

    final provider = DefaultPermissionProvider(
      onRequest: (options) async {
        if (options.toolKind == 'read') return PermissionOutcome.allow;
        // Trigger a UI prompt here...
        return PermissionOutcome.deny;
      },
    );
    ```

#### **FsProvider**
Abstraction for file system operations exposed to agents.

*   **Methods:**
    *   `Future<String> readTextFile(String path, {int? line, int? limit})` - Reads a text file. `line` (1-based) and `limit` (number of lines) constrain the returned range.
    *   `Future<void> writeTextFile(String path, String content)` - Writes text content to a file.

#### **DefaultFsProvider**
Implementation of `FsProvider` that enforces a **workspace jail**, preventing agents from writing outside the project root.

*   **Fields:**
    *   `String workspaceRoot` - The absolute path to the workspace root directory.
    *   `bool allowReadOutsideWorkspace` - When true, allows reading files outside the root (writes are still denied).
*   **Constructors:**
    *   `DefaultFsProvider({required String workspaceRoot, bool allowReadOutsideWorkspace = false})`
*   **Example:**
    ```dart
    import 'package:dart_acp/dart_acp.dart';
    import 'dart:io';

    final fs = DefaultFsProvider(
      workspaceRoot: Directory.current.path,
      allowReadOutsideWorkspace: true, // Allow reading system files, but not writing
    );

    // Read lines 10-20
    final snippet = await fs.readTextFile('lib/main.dart', line: 10, limit: 10);
    ```

#### **TerminalProcessHandle**
Handle for a managed terminal process, providing access to its output and lifecycle.

*   **Fields:**
    *   `String terminalId` - Unique terminal identifier.
    *   `Process process` - The underlying `dart:io` `Process` instance.
*   **Methods:**
    *   `String currentOutput()` - Returns the currently buffered output (stdout + stderr) as a String.
    *   `Future<int> waitForExit()` - Returns the process exit code when it terminates.
    *   `Future<void> kill()` - Terminates the process with `SIGTERM`.
    *   `Future<void> release()` - Cancels stream subscriptions and releases internal resources.

#### **TerminalProvider**
Interface for creating and managing interactive or one-off terminal processes.

*   **Methods:**
    *   `Future<TerminalProcessHandle> create({required String sessionId, required String command, List<String> args, String? cwd, Map<String, String>? env})` - Spawns a new process.
    *   `Future<String> currentOutput(TerminalProcessHandle handle)` - Reads buffered output.
    *   `Future<int> waitForExit(TerminalProcessHandle handle)` - Waits for exit.
    *   `Future<void> kill(TerminalProcessHandle handle)` - Kills the process.
    *   `Future<void> release(TerminalProcessHandle handle)` - Releases resources.

#### **DefaultTerminalProvider**
Standard implementation using `dart:io` `Process`. It handles shell invocation automatically (using `cmd.exe` on Windows and `bash`/`sh` on Unix) if no explicit arguments are provided.

*   **Example:**
    ```dart
    import 'package:dart_acp/dart_acp.dart';

    final terminal = DefaultTerminalProvider();
    final handle = await terminal.create(
      sessionId: 'session-456',
      command: 'npm install', // Invoked via shell
      cwd: './my-app',
    );

    final exitCode = await terminal.waitForExit(handle);
    final logs = await terminal.currentOutput(handle);
    await terminal.release(handle);
    ```

---

### 2. Enums

#### **PermissionOutcome**
The result of a permission request.

*   `allow` - The operation is permitted.
*   `deny` - The operation is denied.
*   `cancelled` - The request was cancelled (e.g., the user closed the prompt or the session ended).

---

### 3. Typedefs

#### **PermissionCallback**
A function signature for handling permission requests programmatically.

*   `Future<PermissionOutcome> Function(PermissionOptions options)`
