import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';  // 状态管理
import 'providers/ble_provider.dart';
import 'services/storage_service.dart';
import 'services/post_event_service.dart';
import 'services/sos_service.dart';
import 'app.dart';

void main() async {                          // async = 异步函数，内部可以用 await
  WidgetsFlutterBinding.ensureInitialized(); // Flutter 引擎初始化，必须在 runApp 前调用（在 main 里用 async 时必加）

  await StorageService.init();               // await = 等待异步操作完成再继续；Hive 初始化

  final postEventService = PostEventService();
  await postEventService.init();             // 初始化本地通知权限

  final sosService = SosService();
  await sosService.init();                   // SOS 通知渠道与权限

  runApp(
    ProviderScope(                           // ProviderScope = Riverpod 的全局容器，必须包在最外层
      overrides: [
        // 把已初始化的服务注入，避免重复 init
        sosServiceProvider.overrideWithValue(sosService),
        postEventServiceProvider.overrideWithValue(postEventService),
      ],
      child: const _AppWrapper(),
    ),
  );
}

class _AppWrapper extends StatelessWidget {  // StatelessWidget = 无状态 Widget（内容固定，不变化）
  const _AppWrapper();

  @override
  Widget build(BuildContext context) {       // @override = 重写父类方法；build = 描述 UI 长什么样
    return const SymptomTrackerApp();
  }
}
