import 'package:flutter/foundation.dart';
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
      // Web reads the page query. iOS and Android have no page URL, so the
      // same query can come from --dart-define=DEEP_LINK=tab=home.
      link: DeepLink.fromUri(
        kIsWeb
            ? Uri.base
            : Uri(query: const String.fromEnvironment('DEEP_LINK')),
      ),
    ),
  );
}
