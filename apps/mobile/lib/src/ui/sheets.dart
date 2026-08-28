import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api_client.dart';
import '../l10n.dart';
import '../layout.dart';
import '../models.dart';
import '../motion.dart';
import '../theme.dart';
import 'create_chat_screen.dart';

/// What "new chat" offers.
///
/// A list, not a row of cards. The test in the design-tells catalogue is
/// whether a fifth option would get a fifth slot — it would, because contact
/// discovery, saved messages and nearby people are all on the roadmap, and a
/// three-across grid would then have to be redesigned to hold four things.
/// Content decided the shape.
Future<ChatSummary?> showNewChatSheet(
  BuildContext context, {
  required ApiClient api,
  required String selfId,
  required Future<ChatSummary?> Function() onDirectChat,
}) {
  return showModalBottomSheet<ChatSummary>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final l10n = L10n.of(sheetContext);
      final layout = SakinaLayout.of(sheetContext);

      Future<void> push(Widget screen) async {
        final result = await Navigator.of(sheetContext).push<ChatSummary>(
          SakinaPageRoute<ChatSummary>(builder: (_) => screen),
        );
        if (sheetContext.mounted) Navigator.of(sheetContext).pop(result);
      }

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              // Icons here carry the distinction between the options, which is
              // the whole information content of this sheet. They are not
              // decoration.
              leading: const Icon(Icons.person_outline),
              title: Text(l10n.t('new_chat')),
              minTileHeight: SakinaLayout.tapTarget,
              onTap: () async {
                final chat = await onDirectChat();
                if (sheetContext.mounted) Navigator.of(sheetContext).pop(chat);
              },
            ),
            ListTile(
              leading: const Icon(Icons.group_outlined),
              title: Text(l10n.t('new_group')),
              minTileHeight: SakinaLayout.tapTarget,
              onTap: () => push(
                CreateChatScreen(api: api, kind: 'group', selfId: selfId),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.campaign_outlined),
              title: Text(l10n.t('new_channel')),
              minTileHeight: SakinaLayout.tapTarget,
              onTap: () => push(
                CreateChatScreen(api: api, kind: 'channel', selfId: selfId),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.alternate_email),
              title: Text(l10n.t('join_channel')),
              minTileHeight: SakinaLayout.tapTarget,
              onTap: () async {
                final chat = await showJoinChannelDialog(sheetContext, api: api);
                if (sheetContext.mounted) Navigator.of(sheetContext).pop(chat);
              },
            ),
            SizedBox(height: layout.gap),
          ],
        ),
      );
    },
  );
}

/// Subscribing to a public channel by its handle.
Future<ChatSummary?> showJoinChannelDialog(
  BuildContext context, {
  required ApiClient api,
}) {
  return showDialog<ChatSummary>(
    context: context,
    builder: (dialogContext) => _JoinChannelDialog(api: api),
  );
}

class _JoinChannelDialog extends StatefulWidget {
  const _JoinChannelDialog({required this.api});
  final ApiClient api;

  @override
  State<_JoinChannelDialog> createState() => _JoinChannelDialogState();
}

class _JoinChannelDialogState extends State<_JoinChannelDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final chat = await widget.api.joinChannel(_controller.text.trim());
      if (!mounted) return;
      Navigator.of(context).pop(chat);
    } on ApiException catch (err) {
      if (!mounted) return;
      setState(() => _error = err.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return AlertDialog(
      title: Text(l10n.t('join_channel')),
      content: TextField(
        controller: _controller,
        autofocus: true,
        autocorrect: false,
        keyboardType: TextInputType.url,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_@]')),
          LengthLimitingTextInputFormatter(33),
        ],
        onSubmitted: (_) => _join(),
        decoration: InputDecoration(
          prefixText: '@',
          hintText: 'dushanbe_news',
          errorText: _error,
          errorMaxLines: 2,
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.t('cancel')),
        ),
        FilledButton(
          onPressed: _busy ? null : _join,
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.t('join_channel')),
        ),
      ],
    );
  }
}

/// The language picker.
///
/// Endonymic: every language is named in itself. "Russian" written in English
/// is no help to someone who only reads Tajik, which is why every real language
/// switcher on earth works this way.
Future<void> showLanguageSheet(
  BuildContext context, {
  required String? current,
  required Future<void> Function(String? code) onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final l10n = L10n.of(sheetContext);
      final layout = SakinaLayout.of(sheetContext);

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: layout.gutter),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  l10n.t('language'),
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
              ),
            ),
            SizedBox(height: layout.gap),
            for (final code in L10n.supportedLocales.map((l) => l.languageCode))
              RadioListTile<String?>(
                value: code,
                groupValue: current,
                title: Text(L10n.languageNames[code] ?? code),
                onChanged: (value) async {
                  await onChanged(value);
                  if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                },
              ),
            RadioListTile<String?>(
              value: null,
              groupValue: current,
              title: Text(l10n.t('language_system')),
              onChanged: (value) async {
                await onChanged(value);
                if (sheetContext.mounted) Navigator.of(sheetContext).pop();
              },
            ),
            SizedBox(height: layout.gap),
          ],
        ),
      );
    },
  );
}

/// Choosing what kind of attachment to send.
///
/// Camera before gallery for photos and video, because the common case in a
/// family chat is something happening right now.
Future<AttachChoice?> showAttachSheet(BuildContext context) {
  return showModalBottomSheet<AttachChoice>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final l10n = L10n.of(sheetContext);
      final layout = SakinaLayout.of(sheetContext);

      Widget option(IconData icon, String label, AttachChoice choice) => ListTile(
            leading: Icon(icon),
            title: Text(label),
            minTileHeight: SakinaLayout.tapTarget,
            onTap: () => Navigator.of(sheetContext).pop(choice),
          );

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            option(Icons.photo_camera_outlined, l10n.t('from_camera'), AttachChoice.camera),
            option(Icons.photo_outlined, l10n.t('from_gallery'), AttachChoice.photo),
            option(Icons.videocam_outlined, l10n.t('a_video'), AttachChoice.video),
            option(Icons.attach_file, l10n.t('a_file'), AttachChoice.file),
            SizedBox(height: layout.gap),
          ],
        ),
      );
    },
  );
}

enum AttachChoice { camera, photo, video, file }

/// The mobile-data confirmation.
///
/// Shown only above [MediaService.confirmAboveBytes]. Data costs real money in
/// this market, and a silent 30MB upload is a bill somebody did not agree to —
/// but asking about every 200KB photo would train the dialog away within a
/// week, which is the failure mode confirmation dialogs always have.
Future<bool> confirmLargeUpload(
  BuildContext context, {
  required String humanSize,
}) async {
  final l10n = L10n.of(context);
  final palette = SakinaPalette.of(context);

  final proceed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.t('mobile_data_warning')),
      content: Text(
        humanSize,
        style: Theme.of(dialogContext).textTheme.titleMedium?.copyWith(color: palette.saffron),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.t('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.t('send_anyway')),
        ),
      ],
    ),
  );
  return proceed ?? false;
}
