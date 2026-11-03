// GENERATED-STYLE FILE (matches Flutter Intl / intl_utils output).
// Regenerate with the Flutter Intl plugin after editing lib/l10n/*.arb.
// ignore_for_file: non_constant_identifier_names, lines_longer_than_80_chars

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class S {
  S();

  static S? _current;

  static S get current {
    assert(_current != null,
        'No instance of S was loaded. Try to initialize the S delegate before accessing S.current.');
    return _current!;
  }

  static const AppLocalizationDelegate delegate = AppLocalizationDelegate();

  static Future<S> load(Locale locale) {
    final name = (locale.countryCode?.isEmpty ?? false)
        ? locale.languageCode
        : locale.toString();
    final localeName = Intl.canonicalizedLocale(name);
    return Future.value(S()).then((instance) {
      Intl.defaultLocale = localeName;
      S._current = instance;
      return instance;
    });
  }

  static S of(BuildContext context) => Localizations.of<S>(context, S)!;

  String get appTitle => Intl.message('Speed Map', name: 'appTitle', desc: '', args: []);
  String get speedUnit => Intl.message('km/h', name: 'speedUnit', desc: '', args: []);
  String get waitingForGps => Intl.message('Waiting for GPS signal…', name: 'waitingForGps', desc: '', args: []);
  String get locationServicesDisabled => Intl.message('Location services are disabled.', name: 'locationServicesDisabled', desc: '', args: []);
  String get permissionDenied => Intl.message('Location permission denied.', name: 'permissionDenied', desc: '', args: []);
  String get permissionDeniedForever => Intl.message('Location permission permanently denied. Enable it in system settings.', name: 'permissionDeniedForever', desc: '', args: []);
  String get retry => Intl.message('Retry', name: 'retry', desc: '', args: []);
}

class AppLocalizationDelegate extends LocalizationsDelegate<S> {
  const AppLocalizationDelegate();

  List<Locale> get supportedLocales => const <Locale>[Locale.fromSubtags(languageCode: 'en')];

  @override
  bool isSupported(Locale locale) => supportedLocales.any((l) => l.languageCode == locale.languageCode);

  @override
  Future<S> load(Locale locale) => S.load(locale);

  @override
  bool shouldReload(AppLocalizationDelegate old) => false;
}
