import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:siargao_genui/a2ui/a2ui_surface_view.dart';
import 'package:siargao_genui/a2ui/surface_session.dart';
import 'package:siargao_genui/catalog/catalog_schemas.g.dart';
import 'package:siargao_genui/theme/app_theme.dart';

/// Wraps [child] in the app theme on a page colored background.
Widget themed(Widget child, {double width = 800}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );
}

/// Sets the test view size in logical pixels.
void setViewSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Builds the three A2UI messages for a surface.
List<Map<String, Object?>> surfaceMessages(
  String surfaceId,
  List<Map<String, Object?>> components, [
  Map<String, Object?> data = const {},
]) => [
  {
    'version': 'v0.9',
    'createSurface': {'surfaceId': surfaceId, 'catalogId': siargaoCatalogId},
  },
  {
    'version': 'v0.9',
    'updateComponents': {'surfaceId': surfaceId, 'components': components},
  },
  {
    'version': 'v0.9',
    'updateDataModel': {'surfaceId': surfaceId, 'path': '/', 'value': data},
  },
];

/// A root Stack around one component with id `c`.
List<Map<String, Object?>> single(
  Map<String, Object?> component, [
  Map<String, Object?> data = const {},
]) => surfaceMessages('test', [
  {
    'id': 'root',
    'component': 'Stack',
    'children': ['c'],
  },
  {'id': 'c', ...component},
], data);

/// Pumps a surface for [messages] and returns its session. Actions are
/// appended to [actions] when given.
Future<SurfaceSession> pumpSurface(
  WidgetTester tester,
  List<Map<String, Object?>> messages, {
  List<SurfaceAction>? actions,
  double width = 800,
}) async {
  setViewSize(tester, Size(width + 48, 2400));
  final SurfaceSession session = SurfaceSession()..apply(messages);
  addTearDown(session.dispose);
  await tester.pumpWidget(
    themed(
      A2uiSurfaceView(session: session, onAction: actions?.add),
      width: width,
    ),
  );
  await tester.pumpAndSettle();
  return session;
}

/// Reads a JSON file relative to the app directory.
Object? readJsonFile(String path) => jsonDecode(File(path).readAsStringSync());

/// An [AssetBundle] that serves files from the app directory, for tests
/// that load fixtures the way the app does.
class DiskAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final File f = File(key);
    if (!f.existsSync()) throw FlutterError('Asset not found: $key');
    return ByteData.sublistView(f.readAsBytesSync());
  }
}
