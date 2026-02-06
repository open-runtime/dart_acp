import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:stream_channel/stream_channel.dart';

/// Wraps a process's stdio as a line-delimited JSON StreamChannel.
class LineJsonChannel {
  /// Create a line-delimited channel around [process].
  LineJsonChannel(this.process, {void Function(String)? onStderr, this.onInboundLine, this.onOutboundLine}) {
    _stdoutSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            if (line.trim().isEmpty) return;
            onInboundLine?.call(line);
            _controller.local.sink.add(line);
          },
          onError: (e) {
            // Log but don't crash on stdout errors
            _log.warning('stdout error: $e');
          },
        );
    // Always drain stderr to prevent subprocess blocking, even if no callback
    _stderrSub = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            // Always consume the data to prevent blocking
            onStderr?.call(line);
          },
          onError: (e) {
            // Log but don't crash on stderr errors
            _log.warning('stderr error: $e');
          },
        );

    _controller.local.stream.listen((out) {
      // Each outgoing payload is one JSON-RPC message; append newline
      onOutboundLine?.call(out);
      try {
        process.stdin.add(utf8.encode(out));
        process.stdin.add([0x0A]);
        // Flush to ensure immediate delivery
        unawaited(
          process.stdin.flush().then<void>(
            (_) {},
            onError: (Object e) {
              _log.fine('stdin flush error (process may have exited): $e');
            },
          ),
        );
      } on Object catch (e) {
        // Process has likely exited. Do NOT inject into the inbound stream —
        // json_rpc_2's Server may be performing an active addStream on the
        // paired sink, causing "Bad state: StreamSink is bound to a stream".
        // The process exit will be detected by StdioTransport's exitCode
        // monitoring for proper cleanup.
        _log.fine('stdin write error (process likely dead): $e');
      }
    });
  }

  static final Logger _log = Logger('dart_acp.rpc.channel');

  /// Underlying process.
  final Process process;
  final StreamChannelController<String> _controller = StreamChannelController();
  late final StreamSubscription _stdoutSub;
  late final StreamSubscription _stderrSub;

  /// Callback invoked for raw inbound lines.
  final void Function(String line)? onInboundLine;

  /// Callback invoked for raw outbound lines.
  final void Function(String line)? onOutboundLine;

  /// Exposed stream channel used by the JSON-RPC peer.
  StreamChannel<String> get channel => _controller.foreign;

  /// Dispose resources, flush stdin, and close the channel.
  Future<void> dispose() async {
    await _stdoutSub.cancel();
    await _stderrSub.cancel();
    try {
      await process.stdin.flush();
    } on Object {
      // Process may have already exited; stdin flush is best-effort.
    }
    // Signal to the JSON-RPC peer that the channel is done, so Peer.listen()
    // completes instead of hanging forever.
    await _controller.local.sink.close();
  }
}
