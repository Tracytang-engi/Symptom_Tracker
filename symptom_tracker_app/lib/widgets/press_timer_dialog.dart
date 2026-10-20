import 'dart:async';
import 'package:flutter/material.dart';

class PressTiming {
  final DateTime startedAt;
  final Duration duration;
  const PressTiming(this.startedAt, this.duration);
}

class PressTimerDialog extends StatefulWidget {
  const PressTimerDialog({super.key});
  @override
  State<PressTimerDialog> createState() => _PressTimerDialogState();
}

class _PressTimerDialogState extends State<PressTimerDialog>
    with WidgetsBindingObserver {
  final _watch = Stopwatch();
  Timer? _ticker;
  DateTime? _started;
  int? _pointer;
  bool _interrupted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _start() {
    if (_watch.isRunning) return;
    _started = DateTime.now();
    _watch
      ..reset()
      ..start();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
    setState(() => _interrupted = false);
  }

  void _finish() {
    if (!_watch.isRunning) return;
    _watch.stop();
    _ticker?.cancel();
    _pointer = null;
    Navigator.pop(context, PressTiming(_started!, _watch.elapsed));
  }

  void _cancelPress() {
    if (!_watch.isRunning) return;
    _ticker?.cancel();
    _watch
      ..stop()
      ..reset();
    _pointer = null;
    setState(() => _interrupted = true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _cancelPress();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _watch.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recording = _watch.isRunning;
    return AlertDialog(
      title: const Text('Press duration'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${(_watch.elapsedMilliseconds / 1000).toStringAsFixed(1)} s',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 16),
          Semantics(
            button: true,
            label: recording ? 'Stop recording' : 'Start recording',
            onTap: () => recording ? _finish() : _start(),
            child: Listener(
              key: const ValueKey('press-timer-pad'),
              behavior: HitTestBehavior.opaque,
              onPointerDown: (event) {
                if (_pointer != null) return;
                _pointer = event.pointer;
                _start();
              },
              onPointerUp: (event) {
                if (event.pointer == _pointer) _finish();
              },
              onPointerCancel: (event) {
                if (event.pointer == _pointer) _cancelPress();
              },
              child: Container(
                constraints: const BoxConstraints(minHeight: 120),
                width: double.infinity,
                alignment: Alignment.center,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: recording
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(recording ? 'Release to save' : 'Hold to record',
                    textAlign: TextAlign.center),
              ),
            ),
          ),
          if (_interrupted) ...[
            const SizedBox(height: 12),
            const Text('Recording cancelled. No entry saved.'),
          ],
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        )
      ],
    );
  }
}
