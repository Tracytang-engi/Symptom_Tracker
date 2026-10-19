import 'dart:io';
import 'dart:typed_data';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final output = Directory('/tmp/sensatrace-ipad-screenshots');
  await output.create(recursive: true);
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      final data = ByteData.sublistView(Uint8List.fromList(bytes));
      if (bytes.length < 24 || data.getUint32(0) != 0x89504e47) {
        throw StateError('Screenshot is not a PNG: $name');
      }
      final width = data.getUint32(16);
      final height = data.getUint32(20);
      if (!((width == 2064 && height == 2752) ||
          (width == 2048 && height == 2732))) {
        throw StateError('Unexpected iPad portrait size: $width x $height');
      }
      await File('${output.path}/$name.png').writeAsBytes(bytes);
      stdout.writeln('Saved $name: $width x $height');
      return true;
    },
  );
}
