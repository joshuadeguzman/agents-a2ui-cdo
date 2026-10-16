import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the bundled fonts (and Material icons from the Flutter SDK) so
/// goldens show real text instead of Ahem boxes.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await _loadFamily('GoogleSansFlex', [
    'assets/fonts/GoogleSansFlex-Regular.ttf',
    'assets/fonts/GoogleSansFlex-Medium.ttf',
    'assets/fonts/GoogleSansFlex-SemiBold.ttf',
    'assets/fonts/GoogleSansFlex-Bold.ttf',
  ]);
  final File? icons = _materialIcons();
  if (icons != null) await _loadFamily('MaterialIcons', [icons.path]);
  await testMain();
}

Future<void> _loadFamily(String family, List<String> paths) async {
  final FontLoader loader = FontLoader(family);
  for (final String p in paths) {
    final File f = File(p);
    if (!f.existsSync()) continue;
    loader.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
  }
  await loader.load();
}

File? _materialIcons() {
  final List<String> roots = [?Platform.environment['FLUTTER_ROOT']];
  // flutter_tester lives in <flutter>/bin/cache/artifacts/engine/<platform>/.
  final Directory exeDir = File(Platform.resolvedExecutable).parent;
  roots.add(exeDir.parent.parent.parent.parent.parent.path);
  for (final String root in roots) {
    final File f = File(
      '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (f.existsSync()) return f;
  }
  return null;
}
