## 0.1.3

- Expose spawned agent `pid` and `exitCode` future on `StdioTransport` for deterministic host process management.
- Prevent transport shutdown (e.g. killed agent process) from surfacing as an uncaught async error in hosts by handling JSON-RPC peer listen errors.

## 0.1.1

- Fix issues with ACP services

## 0.1.0

- Initial version.
