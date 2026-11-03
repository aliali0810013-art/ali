import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/settings/business_identity_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BusinessIdentityStore.instance.ensureLoaded();
  runApp(const NizamiApp());
}
