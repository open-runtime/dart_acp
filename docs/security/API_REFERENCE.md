# Security API Reference

The Security module provides tools for enforcing workspace boundaries and safely resolving file paths. It is designed to prevent path traversal attacks and ensure that an agent only operates within its authorized workspace.

## Importing Security

The security tools are exported from the main package:

```dart
import 'package:dart_acp/dart_acp.dart';
```

Or can be imported directly:

```dart
import 'package:dart_acp/src/security/workspace_jail.dart';
```

---

## Path Enforcement

### WorkspaceJail
Resolver that enforces that paths remain within a workspace root. It handles symlink resolution and path normalization to prevent traversal beyond the specified root directory.

- **workspaceRoot**: `String` - The canonical workspace root. This path must be absolute.

#### Constructors
- **WorkspaceJail({required String workspaceRoot})**
  - Create a jail rooted at `workspaceRoot`.
  - Throws an `ArgumentError` if `workspaceRoot` is not an absolute path.

#### Methods
- **resolveAndEnsureWithin(String path)** -> `Future<String>`
  - Resolve a path relative to `workspaceRoot` if needed and ensure it remains within the workspace.
  - This method resolves symbolic links and normalizes the path to its canonical form before checking boundaries.
  - Throws `FileSystemException` if the path resolves to a location outside the workspace.
- **resolveForgiving(String path)** -> `Future<String>`
  - Resolve path relative to workspace if relative, but do not enforce workspace boundary.
  - Useful for read-anywhere modes where the agent may need to see system files or other locations while still preferring the workspace root as a base.
- **isWithinWorkspace(String path)** -> `Future<bool>`
  - Return true if `path` is within the workspace root after canonicalization.

**Example: Using WorkspaceJail**

```dart
final jail = WorkspaceJail(workspaceRoot: '/home/user/my_project');

try {
  // Safe resolution of relative paths
  final safePath = await jail.resolveAndEnsureWithin('src/main.dart');
  print('Resolved: $safePath'); // /home/user/my_project/src/main.dart

  // Throws if path traversal is attempted
  await jail.resolveAndEnsureWithin('../../../etc/passwd');
} on FileSystemException catch (e) {
  print('Access Denied: ${e.message}');
}

// Check if a path is inside
final isInside = await jail.isWithinWorkspace('/var/log/syslog');
print('Inside workspace: $isInside'); // false
```

---

## Enums

*(No public enums are defined in this module)*

## Extensions

*(No public extensions are defined in this module)*

## Top-Level Functions

*(No public top-level functions are defined in this module)*