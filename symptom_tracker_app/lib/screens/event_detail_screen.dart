import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/pain_event.dart';
import '../providers/ble_provider.dart';
import '../providers/events_provider.dart';
import '../providers/settings_provider.dart';
import '../services/audio_service.dart';
import '../widgets/pressure_curve_chart.dart';
import '../widgets/tag_selector.dart';

// EventDetailScreen：单次事件详情页
// 包括：压力曲线图、统计数字、标签编辑、文字备注、语音备注
class EventDetailScreen extends ConsumerStatefulWidget {
  final PainEvent event;
  const EventDetailScreen({super.key, required this.event});

  @override
  ConsumerState<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends ConsumerState<EventDetailScreen> {
  late PainEvent _event;
  late TextEditingController _noteCtrl;
  final AudioService _audio = AudioService();
  bool _phoneRecording = false;
  String? _playingPath;

  @override
  void initState() {
    super.initState();
    _event = widget.event;
    _noteCtrl = TextEditingController(text: _event.textNote);
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    _audio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 跟随 provider 刷新（下载完成后路径会更新）
    final live = ref.watch(eventsProvider).where((e) => e.id == _event.id);
    if (live.isNotEmpty) _event = live.first;

    final deviceSettings = ref.watch(deviceSettingsProvider);
    final activeDownloadPath = ref.watch(activeDeviceFileTransferPathProvider);
    final primary = Theme.of(context).colorScheme.primary;
    final dateStr = DateFormat('MMM d, yyyy  HH:mm').format(_event.startTime);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Episode Detail'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: _confirmDelete,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dateStr,
                style: TextStyle(color: primary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Duration: ${_event.formattedDuration}',
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pressure Curve',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 12),
                    PressureCurveChart(
                        event: _event, deviceSettings: deviceSettings),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                    child: _Stat(
                        label: 'Peak',
                        value: _event.peakForcePercent,
                        icon: Icons.arrow_upward)),
                const SizedBox(width: 8),
                Expanded(
                    child: _Stat(
                        label: 'Average',
                        value: _event.meanForcePercent,
                        icon: Icons.show_chart)),
                const SizedBox(width: 8),
                Expanded(
                    child: _Stat(
                        label: 'Samples',
                        value: '${_event.rawSamples.length}',
                        icon: Icons.data_array)),
              ],
            ),
            const SizedBox(height: 16),
            _Section(
              title: 'Tags',
              trailing: TextButton(
                onPressed: _editTags,
                child: const Text('Edit'),
              ),
              child: _event.tags.isEmpty
                  ? const Text('No tags yet',
                      style: TextStyle(color: Colors.grey))
                  : Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children:
                          _event.tags.map((t) => Chip(label: Text(t))).toList(),
                    ),
            ),
            const SizedBox(height: 12),
            _Section(
              title: 'Notes',
              child: TextField(
                controller: _noteCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Add a note...',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => _saveNote(),
              ),
            ),
            const SizedBox(height: 12),
            _Section(
              title: 'Voice Notes',
              trailing: IconButton(
                tooltip: _phoneRecording ? 'Stop' : 'Record on phone',
                icon: Icon(
                  _phoneRecording ? Icons.stop_circle : Icons.mic,
                  color: _phoneRecording ? Colors.red : primary,
                ),
                onPressed: _togglePhoneRecord,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_phoneRecording)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text('Recording… (no time limit)',
                          style: TextStyle(color: Colors.red, fontSize: 13)),
                    ),
                  if (_event.pendingDeviceRecPaths.isNotEmpty) ...[
                    Text('On device (not downloaded)',
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 12)),
                    const SizedBox(height: 4),
                    ..._event.pendingDeviceRecPaths.map((p) {
                      final isDownloading = activeDownloadPath == p;
                      final anotherDownloadActive =
                          activeDownloadPath != null && !isDownloading;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.cloud_download_outlined),
                        title: Text(p, style: const TextStyle(fontSize: 13)),
                        trailing: isDownloading
                            ? const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Text('Downloading…'),
                                ],
                              )
                            : TextButton(
                                onPressed: anotherDownloadActive
                                    ? null
                                    : () => _downloadDevicePath(p),
                                child: Text(anotherDownloadActive
                                    ? 'Waiting'
                                    : 'Download'),
                              ),
                      );
                    }),
                    const SizedBox(height: 8),
                  ],
                  if (_event.voiceNotePaths.isEmpty &&
                      _event.pendingDeviceRecPaths.isEmpty &&
                      !_phoneRecording)
                    const Text('No voice notes yet',
                        style: TextStyle(color: Colors.grey)),
                  ..._event.voiceNotePaths.asMap().entries.map((entry) {
                    final i = entry.key;
                    final path = entry.value;
                    final name = path.split(RegExp(r'[\\/]')).last;
                    final playing = _playingPath == path;
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        playing ? Icons.stop : Icons.play_arrow,
                        color: primary,
                      ),
                      title: Text('Clip ${i + 1}',
                          style: const TextStyle(fontSize: 14)),
                      subtitle: Text(name,
                          style: const TextStyle(fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      onTap: () => _togglePlay(path),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () => _deleteVoice(path),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _togglePhoneRecord() async {
    if (_phoneRecording) {
      final path = await _audio.stopRecording();
      setState(() => _phoneRecording = false);
      if (path == null || !mounted) return;
      final paths = List<String>.from(_event.voiceNotePaths)..add(path);
      final updated = _event.copyWith(voiceNotePaths: paths);
      await ref.read(eventsProvider.notifier).updateEvent(updated);
      setState(() => _event = updated);
    } else {
      final ok = await _audio.startRecording();
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission required')),
        );
        return;
      }
      setState(() => _phoneRecording = true);
    }
  }

  Future<void> _togglePlay(String path) async {
    if (_playingPath == path) {
      await _audio.stopPlayback();
      setState(() => _playingPath = null);
      return;
    }
    await _audio.play(path);
    setState(() => _playingPath = path);
  }

  Future<void> _deleteVoice(String path) async {
    await _audio.deleteLocal(path);
    final paths = List<String>.from(_event.voiceNotePaths)..remove(path);
    final updated = _event.copyWith(voiceNotePaths: paths);
    await ref.read(eventsProvider.notifier).updateEvent(updated);
    if (_playingPath == path) _playingPath = null;
    setState(() => _event = updated);
  }

  Future<void> _downloadDevicePath(String remotePath) async {
    final xfer = ref.read(deviceFileTransferProvider);
    final local = await xfer.downloadAndSave(remotePath);
    if (local == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Download failed (missing file, timeout, or SPIFFS full). '
              'Try Settings → BLE → Clear device storage.',
            ),
          ),
        );
      }
      return;
    }
    final paths = List<String>.from(_event.voiceNotePaths);
    if (!paths.contains(local)) paths.add(local);
    final pending = List<String>.from(_event.pendingDeviceRecPaths)
      ..remove(remotePath);
    final updated = _event.copyWith(
      voiceNotePaths: paths,
      pendingDeviceRecPaths: pending,
    );
    await ref.read(eventsProvider.notifier).updateEvent(updated);
    if (mounted) setState(() => _event = updated);
  }

  Future<void> _editTags() async {
    final result = await TagSelector.show(context, _event.tags);
    if (result == null || !mounted) return;

    final updated = _event.copyWith(tags: result);
    await ref.read(eventsProvider.notifier).updateEvent(updated);
    setState(() => _event = updated);
  }

  Future<void> _saveNote() async {
    final text = _noteCtrl.text;
    final updated = text.isEmpty
        ? _event.copyWith(clearTextNote: true)
        : _event.copyWith(textNote: text);
    await ref.read(eventsProvider.notifier).updateEvent(updated);
    _event = updated;
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Episode'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await ref.read(eventsProvider.notifier).deleteEvent(_event.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    }
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _Stat({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: color, fontSize: 16)),
            Text(label,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _Section({required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
