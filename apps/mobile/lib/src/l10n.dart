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
    'send': {'ru': 'Отправить', 'tg': 'Фиристодан', 'en': 'Send'},
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

    // ---------------------------------------------------------------------
    // Groups, channels, attachments and the language picker.
    //
    // Written in all three, not machine-translated. Where Tajik and Russian
    // differ in length the Tajik is the one to size buttons against — it is
    // reliably the longest, which is why CLAUDE.md says to check layouts
    // against it.
    // ---------------------------------------------------------------------
    'language': {'ru': 'Язык', 'tg': 'Забон', 'en': 'Language'},
    'language_system': {
      'ru': 'Как на телефоне',
      'tg': 'Мисли телефон',
      'en': 'Match my phone',
    },
    'saved_messages': {
      'ru': 'Избранное',
      'tg': 'Захирашуда',
      'en': 'Saved messages',
    },

    'new_chat': {'ru': 'Новый чат', 'tg': 'Сӯҳбати нав', 'en': 'New chat'},
    'new_group': {'ru': 'Новая группа', 'tg': 'Гурӯҳи нав', 'en': 'New group'},
    'new_channel': {'ru': 'Новый канал', 'tg': 'Шабакаи нав', 'en': 'New channel'},
    'join_channel': {
      'ru': 'Подписаться на канал',
      'tg': 'Обуна ба шабака',
      'en': 'Join a channel',
    },

    'group_name': {'ru': 'Название группы', 'tg': 'Номи гурӯҳ', 'en': 'Group name'},
    'group_name_hint': {'ru': 'Наша семья', 'tg': 'Оилаи мо', 'en': 'Our family'},
    'channel_name': {'ru': 'Название канала', 'tg': 'Номи шабака', 'en': 'Channel name'},
    'channel_name_hint': {
      'ru': 'Новости Душанбе',
      'tg': 'Хабарҳои Душанбе',
      'en': 'Dushanbe news',
    },
    'chat_description': {'ru': 'Описание', 'tg': 'Тавсиф', 'en': 'Description'},
    'chat_description_hint': {
      'ru': 'Необязательно',
      'tg': 'Ихтиёрӣ',
      'en': 'Optional',
    },
    'channel_handle': {'ru': 'Публичная ссылка', 'tg': 'Пайванди оммавӣ', 'en': 'Public link'},
    'channel_handle_help': {
      'ru': 'Латиница, цифры и _. Так канал найдут по ссылке.',
      'tg': 'Ҳарфҳои лотинӣ, рақамҳо ва _. Бо ин пайванд шабакаро меёбанд.',
      'en': 'Latin letters, digits and _. This is how people find the channel.',
    },
    'channel_handle_invalid': {
      'ru': 'От 5 до 32 символов: a-z, 0-9 и _',
      'tg': 'Аз 5 то 32 аломат: a-z, 0-9 ва _',
      'en': '5 to 32 characters: a-z, 0-9 and _',
    },
    'channel_private_note': {
      'ru': 'Без ссылки канал будет закрытым — подписчиков добавляете вы.',
      'tg': 'Бе пайванд шабака пӯшида мешавад — обуначиёнро шумо илова мекунед.',
      'en': 'Without a link the channel stays private and you add subscribers yourself.',
    },

    'members': {'ru': 'Участники', 'tg': 'Аъзоён', 'en': 'Members'},
    'subscribers': {'ru': 'Подписчики', 'tg': 'Обуначиён', 'en': 'Subscribers'},
    'add_people': {'ru': 'Добавить людей', 'tg': 'Илова кардани одамон', 'en': 'Add people'},
    'add_by_id': {
      'ru': 'Вставьте id пользователя',
      'tg': 'Идентификатори корбарро гузоред',
      'en': 'Paste a user id',
    },
    'no_one_yet': {
      'ru': 'Пока никого. Добавьте хотя бы одного человека.',
      'tg': 'Ҳанӯз касе нест. Ақаллан як нафарро илова кунед.',
      'en': 'Nobody yet. Add at least one person.',
    },
    'owner_role': {'ru': 'Владелец', 'tg': 'Соҳиб', 'en': 'Owner'},
    'admin_role': {'ru': 'Администратор', 'tg': 'Мудир', 'en': 'Admin'},
    'leave_chat': {'ru': 'Выйти', 'tg': 'Баромадан', 'en': 'Leave'},
    'left_chat': {'ru': 'Вы вышли', 'tg': 'Шумо баромадед', 'en': 'You left'},
    'undo': {'ru': 'Отменить', 'tg': 'Бекор кардан', 'en': 'Undo'},

    'create': {'ru': 'Создать', 'tg': 'Сохтан', 'en': 'Create'},
    'cancel': {'ru': 'Отмена', 'tg': 'Бекор', 'en': 'Cancel'},
    'retry': {'ru': 'Повторить', 'tg': 'Такрор', 'en': 'Try again'},

    'read_only_channel': {
      'ru': 'Только администраторы могут писать здесь',
      'tg': 'Танҳо мудирон метавонанд дар ин ҷо нависанд',
      'en': 'Only admins can post here',
    },

    'attach': {'ru': 'Прикрепить', 'tg': 'Замима кардан', 'en': 'Attach'},
    'a_photo': {'ru': 'Фото', 'tg': 'Сурат', 'en': 'Photo'},
    'a_video': {'ru': 'Видео', 'tg': 'Видео', 'en': 'Video'},
    'a_file': {'ru': 'Файл', 'tg': 'Файл', 'en': 'File'},
    'attachment': {'ru': 'Вложение', 'tg': 'Замима', 'en': 'Attachment'},
    'from_camera': {'ru': 'Камера', 'tg': 'Камера', 'en': 'Camera'},
    'from_gallery': {'ru': 'Галерея', 'tg': 'Галерея', 'en': 'Gallery'},
    'uploading': {'ru': 'Отправка…', 'tg': 'Фиристодан…', 'en': 'Uploading…'},
    'upload_failed': {
      'ru': 'Не удалось отправить',
      'tg': 'Фиристодан нашуд',
      'en': "Couldn't send that",
    },
    'file_too_large': {
      'ru': 'Файл слишком большой',
      'tg': 'Файл хеле калон аст',
      'en': 'That file is too large',
    },
    'mobile_data_warning': {
      'ru': 'Большой файл. Отправить по мобильному интернету?',
      'tg': 'Файли калон. Тавассути интернети мобилӣ фиристода шавад?',
      'en': 'Large file. Send over mobile data?',
    },
    'send_anyway': {'ru': 'Отправить', 'tg': 'Фиристодан', 'en': 'Send'},
    'system_event': {'ru': 'Событие', 'tg': 'Рӯйдод', 'en': 'Update'},

    'loading': {'ru': 'Загрузка…', 'tg': 'Боркунӣ…', 'en': 'Loading…'},
    'nothing_here': {'ru': 'Пока пусто', 'tg': 'Ҳанӯз холӣ', 'en': 'Nothing here yet'},

    // Message actions and replies (backlog A7/A8).
    'reply': {'ru': 'Ответить', 'tg': 'Ҷавоб додан', 'en': 'Reply'},
    'copy': {'ru': 'Копировать', 'tg': 'Нусха бардоштан', 'en': 'Copy'},
    'copied': {'ru': 'Скопировано', 'tg': 'Нусха бардошта шуд', 'en': 'Copied'},
    'message_unavailable': {
      'ru': 'Сообщение недоступно',
      'tg': 'Паём дастрас нест',
      'en': 'Message unavailable',
    },
    'you': {'ru': 'Вы', 'tg': 'Шумо', 'en': 'You'},
    'someone': {'ru': 'Кто-то', 'tg': 'Касе', 'en': 'Someone'},
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
