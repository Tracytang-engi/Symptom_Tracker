// AudioService：语音备注录制功能预留接口
// 注意：录音绝不会被压力按钮自动触发，必须由用户手动点麦克风按钮

// abstract = 抽象类：只定义接口（方法签名），不提供实现，由子类实现
abstract class AudioService {
  Future<bool> startRecording();  // 开始录音；返回 false 表示无权限
  Future<String?> stopRecording(); // 停止录音；返回文件路径，失败返回 null
  bool get isRecording;            // get = 只读属性，当前是否正在录音
  Future<void> uploadRecording(String filePath, String eventId);  // 上传到云端（未实现）
}

// implements = 实现接口（必须实现 abstract class 的所有方法）
class LocalAudioService implements AudioService {
  bool _isRecording = false;     // _ 开头 = 私有，外部不可直接访问

  @override
  bool get isRecording => _isRecording;  // 暴露只读版本

  @override
  Future<bool> startRecording() async {
    // TODO(P1)：用 record 包实现
    // final recorder = AudioRecorder();
    // if (!await recorder.hasPermission()) return false;
    // await recorder.start(...);
    _isRecording = true;
    return true;
  }

  @override
  Future<String?> stopRecording() async {
    // TODO(P1)：用 record 包实现
    _isRecording = false;
    return null;  // 返回 null 表示存根（stub）未实现
  }

  @override
  Future<void> uploadRecording(String filePath, String eventId) async {
    // TODO(P2)：上传到云存储
    throw UnimplementedError('Cloud upload is not yet available.');  // 抛出异常告知调用者未实现
  }
}
