import 'package:flutter/material.dart';

import 'app.dart';
import 'catalog/image_asset.dart';
import 'config.dart';
import 'deep_link.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ImageAssets.load();
  runApp(
    SiargaoApp(
      config: AppConfig.fromEnvironment(),
      link: DeepLink.fromUri(Uri.base),
    ),
  );
}
