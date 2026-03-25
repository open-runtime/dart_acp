# Security Module Quickstart

## 1. Overview
The Security module provides path validation and boundary enforcement to prevent unauthorized file system access outside of an approved workspace. It features the `WorkspaceJail` utility, which safely resolves, canonicalizes, and verifies paths to ensure they remain within the designated workspace root.

Key features include:
- **Path Canonicalization:** Resolves symbolic links and dot segments (`.` and `..`) to find the actual file location.
- **Boundary Enforcement:** Ensures that resolved paths are always within the specified workspace root.
- **URI Support:** Natively handles `file://` URIs and cross-platform path normalization.
- **Platform Awareness:** Correctly handles both Windows and POSIX path formats.

## 2. Import
To use the `WorkspaceJail` utility, import it from the security package:

```dart
import 'package:dart_acp/src/security/workspace_jail.dart';
```

## 3. Setup
Create an instance of `WorkspaceJail` by providing an absolute path to the designated workspace root.

```dart
import 'dart:io';
import 'package:dart_acp/src/security/workspace_jail.dart';

void main() {
  // The workspaceRoot MUST be an absolute path (throws ArgumentError otherwise).
  final workspaceRoot = Directory.current.absolute.path;
  
  // Resolver that enforces that paths remain within a workspace root.
  final jail = WorkspaceJail(
    workspaceRoot: workspaceRoot,
  );
  
  // Canonical workspace root.
  print('Jail initialized at: ${jail.workspaceRoot}');
}
```

## 4. Common Operations

### Enforce Workspace Boundaries
Safely resolve a relative or absolute path, ensuring it stays within the workspace.

```dart
try {
  // Resolve a path relative to [workspaceRoot] if needed and ensure it
  // remains within the workspace. Throws [FileSystemException] if outside.
  final safePath = await jail.resolveAndEnsureWithin('docs/README.md');
  print('Safe path: $safePath');
  
  // This will throw a FileSystemException because it points outside the workspaceRoot.
  await jail.resolveAndEnsureWithin('../../etc/passwd');
} on FileSystemException catch (e) {
  print('Access denied: ${e.message}');
}
```

### Forgiving Path Resolution
Resolve a path relative to the workspace root without strictly enforcing the boundary. This is useful for read-anywhere configurations where you still want relative paths to resolve against the workspace.

```dart
// Resolve path relative to workspace if relative, but do not enforce
// workspace boundary. Useful for read-anywhere modes.
final forgivenPath = await jail.resolveForgiving('../outside_workspace_file.txt');
print('Resolved to: $forgivenPath');
```

### Check if Path is Within Workspace
Check if a given path is safely contained within the workspace root without modifying or accessing it directly.

```dart
// Return true if [path] is within the workspace root.
final isSafe = await jail.isWithinWorkspace('/absolute/path/to/check.txt');

if (isSafe) {
  print('The path is safe to access.');
} else {
  print('The path is outside the workspace root!');
}
```

## 5. Configuration
The `WorkspaceJail` behavior is configured at runtime via the `workspaceRoot` constructor argument:
- **workspaceRoot:** Must be a valid, absolute path string.
- **Symbolic Links:** The jail automatically resolves symbolic links to prevent "symlink races" or escaping via links.
- **Normalization:** It handles `file://` URIs and ensures consistent path separators across different operating systems.

## 6. Related Modules
- **Providers:** The `FsProvider` typically integrates `WorkspaceJail` to validate paths before performing file system operations.
- **Session:** The session management lifecycle manages the active `workspaceRoot` provided to the jail during session initialization.
