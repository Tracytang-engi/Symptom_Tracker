import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

/// 手机端语音备注：录制（无时长上限 M2）+ 播放 + 删除本地文件
class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  bool _isRecording = false;

  bool get isRecording => _isRecording;
  bool get isPlaying => _player.state == PlayerState.playing;

  Future<bool> startRecording() async {
    if (_isRecording) return false;
    if (!await _recorder.hasPermission()) return false;

    final dir = await getApplicationDocumentsDirectory();
    final voiceDir = Directory('${dir.path}/voice_notes');
    if (!await voiceDir.exists()) {
      await voiceDir.create(recursive: true);
    }

    final path =
        '${voiceDir.path}/phone_${const Uuid().v4()}.m4a';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: path,
    );
    _isRecording = true;
    return true;
  }

  /// 停止录音，返回本地文件路径；失败返回 null
  Future<String?> stopRecording() async {
    if (!_isRecording) return null;
    final path = await _recorder.stop();
    _isRecording = false;
    if (path == null || path.isEmpty) return null;
    if (!File(path).existsSync()) return null;
    return path;
  }

  Future<void> play(String filePath) async {
    await _player.stop();
    await _player.play(DeviceFileSource(filePath));
  }

  Future<void> stopPlayback() async {
    await _player.stop();
  }

  Future<void> deleteLocal(String filePath) async {
    final f = File(filePath);
    if (await f.exists()) await f.delete();
  }

  Future<void> dispose() async {
    if (_isRecording) await _recorder.stop();
    await _recorder.dispose();
    await _player.dispose();
  }
}
