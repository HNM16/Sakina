import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Strings, Russian first.
///
/// A lookup table rather than generated ARB files, because M0 has fifteen
/// strings and the build-time codegen is not yet earning its keep. The point of
/// having it on day one is the discipline: no literal user-facing text in a
/// widget, ever. Swapping this for `flutter_localizations` + ARB later is then a
/// mechanical change instead of an audit of every screen.
///
/// Russian is the default, Tajik second, English third. That ordering is a
/// product decision, not a linguistic one: Russian is the language the whole
/// target audience can read — in Dushanbe, across the generations that were
/// schooled in it, and above all among the migrant workers in Russia who are a
/// large share of who this app is for. Tajik is the language of the country and
/// the reason the font choice is non-negotiable (ғ ӣ қ ӯ ҳ ҷ), so it is one tap
/// away rather than buried. English is for the diaspora and for us.
///
/// A user whose phone is set to neither lands on Russian, because guessing
/// Tajik for a Kazakh or Uzbek phone helps nobody. [supportedLocales] is
/// ordered, and Flutter's resolution falls through to the first entry, so the
/// order below IS the policy.
class L10n {
  const L10n(this.locale);

  final Locale locale;

  static const supportedLocales = [
    Locale('ru'),
    Locale('tg'),
    Locale('en'),
  ];

  /// The language names, each written in its own language. Never translate
  /// these — a picker that says "Russian" to someone who only reads Tajik is
  /// useless, which is why every real language switcher on earth is endonymic.
  static const languageNames = <String, String>{
    'ru': 'Русский',
    'tg': 'Тоҷикӣ',
    'en': 'English',
  };

  static const fallbackLanguage = 'ru';

  static L10n of(BuildContext context) => L10n(Localizations.localeOf(context));

  static const _strings = <String, Map<String, String>>{
    'app_name': {'tg': 'Сакина', 'ru': 'Сакина', 'en': 'Sakina'},
    'sign_in_subtitle': {
      'tg': 'Барои вуруд почтаи электронии худро ворид кунед',
      'ru': 'Введите вашу почту, чтобы войти',
      'en': 'Enter your email to sign in',
    },
    'email_title': {
      'tg': 'Почтаи электронӣ',
      'ru': 'Электронная почта',
      'en': 'Email',
    },
    'email_hint': {
      'tg': 'nekruz@example.com',
      'ru': 'nekruz@example.com',
      'en': 'nekruz@example.com',
    },
    'email_invalid': {
      'tg': 'Суроғаи почта нодуруст аст',
      'ru': 'Неверный адрес почты',
      'en': "That doesn't look like an email address",
    },
    'code_sent_to': {
      'tg': 'Мо рамзро фиристодем ба',
      'ru': 'Мы отправили код на',
      'en': 'We sent a code to',
    },
    'change_email': {
      'tg': 'Тағйири суроға',
      'ru': 'Изменить адрес',
      'en': 'Change address',
    },
    'invite_title': {
      'tg': 'Рамзи даъват',
      'ru': 'Код приглашения',
      'en': 'Invite code',
    },
    'invite_hint': {
      'tg': 'Аз дӯсте, ки аллакай дар Сакина аст',
      'ru': 'От друга, который уже в Сакина',
      'en': 'From a friend already on Sakina',
    },
    'phone_title': {
      'tg': 'Рақами телефон',
      'ru': 'Номер телефона',
      'en': 'Phone number',
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
    'push_new_message': {
      'tg': 'Паёми нав',
      'ru': 'Новое сообщение',
      'en': 'New message',
    },
    'notifications_off': {
      'tg': 'Огоҳиномаҳо хомӯшанд',
      'ru': 'Уведомления выключены',
      'en': 'Notifications are off',
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
    return entry[locale.languageCode] ?? entry[fallbackLanguage] ?? key;
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
