import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/router/router.dart';
import 'core/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await initializeDateFormatting('fr_FR');
  initAuthNotifier();
  await MobileAds.instance.initialize();
  runApp(const ProviderScope(child: BlaBlaCase()));
}

class BlaBlaCase extends StatelessWidget {
  const BlaBlaCase({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'BlaBlaCase',
      theme: appTheme,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
