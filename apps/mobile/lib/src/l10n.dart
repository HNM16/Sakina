import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Strings, in Tajik first.
///
/// A lookup table rather than generated ARB files, because M0 has fifteen
/// strings and the build-time codegen is not yet earning its keep. The point of
/// having it on day one is the discipline: no literal user-facing text in a
/// widget, ever. Swapping this for `flutter_localizations` + ARB later is then a
/// mechanical change instead of an audit of every screen.
///
/// Tajik (тоҷикӣ) is the default; Russian is widely used in Dushanbe and by
/// migrant users. Uzbek and English come after M1.
class L10n {
  const L10n(this.locale);

  final Locale locale;

  static const supportedLocales = [
    Locale('tg'),
    Locale('ru'),
    Locale('en'),
  ];

  static L10n of(BuildContext context) => L10n(Localizations.localeOf(context));

  static const _strings = <String, Map<String, String>>{
    'app_name': {'tg': 'Сакина', 'ru': 'Сакина', 'en': 'Sakina'},
    'phone_title': {
      'tg': 'Рақами телефон',
      'ru': 'Номер телефона',
      'en': 'Phone number',
    },
    'phone_hint': {
      'tg': 'Рақами худро ворид кунед',
      'ru': 'Введите ваш номер',
      'en': 'Enter your number',
    },
    'continue': {'tg': 'Идома', 'ru': 'Продолжить', 'en': 'Continue'},
    'code_title': {'tg': 'Рамзи тасдиқ', 'ru': 'Код подтверждения', 'en': 'Confirmation code'},
    'code_hint': {
      'tg': 'Рамзи 6-рақамаро ворид кунед',
      'ru': 'Введите 6-значный код',
      'en': 'Enter the 6-digit code',
    },
    'chats': {'tg': 'Сӯҳбатҳо', 'ru': 'Чаты', 'en': 'Chats'},
    'no_chats': {
      'tg': 'Ҳанӯз сӯҳбате нест',
      'ru': 'Пока нет чатов',
      'en': 'No chats yet',
    },
    'message_hint': {'tg': 'Паём...', 'ru': 'Сообщение...', 'en': 'Message...'},
    'connecting': {'tg': 'Пайвастшавӣ...', 'ru': 'Подключение...', 'en': 'Connecting...'},
    'offline': {'tg': 'Офлайн', 'ru': 'Не в сети', 'en': 'Offline'},
    'typing': {'tg': 'менависад...', 'ru': 'печатает...', 'en': 'typing...'},
    'sign_out': {'tg': 'Баромад', 'ru': 'Выйти', 'en': 'Sign out'},
    'new_chat': {'tg': 'Сӯҳбати нав', 'ru': 'Новый чат', 'en': 'New chat'},
    'peer_id_hint': {
      'tg': 'ID-и корбарро ворид кунед',
      'ru': 'Введите ID пользователя',
      'en': 'Enter a user ID',
    },
    'error_generic': {
      'tg': 'Хатогӣ рух дод',
      'ru': 'Произошла ошибка',
      'en': 'Something went wrong',
    },
  };

  String t(String key) {
    final entry = _strings[key];
    if (entry == null) return key;
    return entry[locale.languageCode] ?? entry['tg'] ?? key;
  }
}

/// Flutter ships no Tajik locale.
///
/// `GlobalMaterialLocalizations` covers ~80 languages and `tg` is not one of
/// them, so declaring `Locale('tg')` as supported trips an assertion at startup
/// and, in release, leaves built-in widget strings ("Cancel", "Paste", the date
/// picker) unlocalised. Every Tajik Flutter app hits this on day one.
///
/// These delegates claim `tg` and serve Russian for the framework's own strings
/// — the pragmatic fallback, since Russian is already the second language of the
/// audience. Sakina's own copy still comes from [L10n] in Tajik. The proper fix
/// is contributing a Tajik ARB upstream to flutter_localizations; until then
/// this keeps the framework honest instead of silently English.
class _TajikMaterialDelegate extends LocalizationsDelegate<MaterialLocalizations> {
  const _TajikMaterialDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'tg';

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      GlobalMaterialLocalizations.delegate.load(const Locale('ru'));

  @override
  bool shouldReload(_TajikMaterialDelegate old) => false;
}

class _TajikCupertinoDelegate extends LocalizationsDelegate<CupertinoLocalizations> {
  const _TajikCupertinoDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'tg';

  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      GlobalCupertinoLocalizations.delegate.load(const Locale('ru'));

  @override
  bool shouldReload(_TajikCupertinoDelegate old) => false;
}

class _TajikWidgetsDelegate extends LocalizationsDelegate<WidgetsLocalizations> {
  const _TajikWidgetsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'tg';

  @override
  Future<WidgetsLocalizations> load(Locale locale) =>
      GlobalWidgetsLocalizations.delegate.load(const Locale('ru'));

  @override
  bool shouldReload(_TajikWidgetsDelegate old) => false;
}

/// Order matters: the Tajik delegates must come before the global ones so they
/// win for `tg` and defer for everything else.
const localizationDelegates = <LocalizationsDelegate<dynamic>>[
  _TajikMaterialDelegate(),
  _TajikCupertinoDelegate(),
  _TajikWidgetsDelegate(),
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];
