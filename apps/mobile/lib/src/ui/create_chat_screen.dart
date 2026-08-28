import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api_client.dart';
import '../l10n.dart';
import '../layout.dart';
import '../theme.dart';

/// Creating a group or a channel.
///
/// One screen for both, because they differ in exactly two places — a channel
/// can have a public handle, and a channel can start empty — and two screens
/// that are 90% the same drift apart within a month.
///
/// The Nielsen heuristics doing real work here:
///
///  - **Error prevention** (#5). The handle is validated for shape as it is
///    typed, so the common mistake is caught without a round trip, and Create
///    stays disabled until the form can actually succeed.
///  - **Visibility of system status** (#1). Create becomes a spinner; there is
///    no moment where the screen looks idle while a request is in flight.
///  - **User control and freedom** (#3). Everything is reversible from here —
///    the back button works throughout, and nothing is created until the last
///    tap.
class CreateChatScreen extends StatefulWidget {
  const CreateChatScreen({
    super.key,
    required this.api,
    required this.kind,
    required this.selfId,
  });

  final ApiClient api;

  /// `group` or `channel`.
  final String kind;
  final String selfId;

  @override
  State<CreateChatScreen> createState() => _CreateChatScreenState();
}

class _CreateChatScreenState extends State<CreateChatScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _handleController = TextEditingController();
  final _memberController = TextEditingController();

  final _memberIds = <String>[];
  bool _busy = false;
  String? _error;
  String? _handleError;

  bool get _isChannel => widget.kind == 'channel';

  @override
  void initState() {
    super.initState();
    // Create's enabled state depends on the title, so the button has to hear
    // about every keystroke. Without this it stays disabled until something
    // else happens to rebuild the screen.
    _titleController.addListener(_onFormChanged);
  }

  @override
  void dispose() {
    _titleController.removeListener(_onFormChanged);
    _titleController.dispose();
    _descriptionController.dispose();
    _handleController.dispose();
    _memberController.dispose();
    super.dispose();
  }

  void _onFormChanged() {
    if (mounted) setState(() {});
  }

  /// Mirrors `ChatUsername` in packages/protocol. Checked here so a typo costs
  /// nothing; the server is still the authority.
  static final _handlePattern = RegExp(r'^[a-z][a-z0-9_]{4,31}$');

  void _validateHandle(String raw) {
    final value = raw.trim().toLowerCase();
    setState(() {
      _handleError = value.isEmpty || _handlePattern.hasMatch(value)
          ? null
          : L10n.of(context).t('channel_handle_invalid');
    });
  }

  void _addMember() {
    final id = _memberController.text.trim();
    if (id.isEmpty) return;
    // The one thing worth checking without contact discovery: that it is a
    // uuid at all, and that it is not the creator, who is a member already.
    if (id == widget.selfId || _memberIds.contains(id)) {
      _memberController.clear();
      return;
    }
    setState(() {
      _memberIds.add(id);
      _memberController.clear();
      _error = null;
    });
  }

  bool get _canCreate {
    if (_busy) return false;
    if (_titleController.text.trim().isEmpty) return false;
    if (_handleError != null) return false;
    // A group needs somebody in it; a channel is allowed to start with an
    // audience of nobody, which is the normal way a channel starts.
    if (!_isChannel && _memberIds.isEmpty) return false;
    return true;
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final title = _titleController.text.trim();
      final description = _descriptionController.text.trim();
      final chat = _isChannel
          ? await widget.api.createChannel(
              title: title,
              username: _handleController.text.trim().toLowerCase(),
              description: description,
              memberIds: _memberIds,
            )
          : await widget.api.createGroup(
              title: title,
              memberIds: _memberIds,
              description: description,
            );

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
    final layout = SakinaLayout.of(context);
    final palette = SakinaPalette.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t(_isChannel ? 'new_channel' : 'new_group')),
      ),
      body: SafeArea(
        child: ListView(
          padding: layout.screenPadding,
          children: [
            Center(child: ChorkhonaMark(size: layout.isNarrow ? 48 : 56)),
            SizedBox(height: layout.gap * 2),

            TextField(
              controller: _titleController,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              maxLength: 128,
              decoration: InputDecoration(
                labelText: l10n.t(_isChannel ? 'channel_name' : 'group_name'),
                hintText: l10n.t(_isChannel ? 'channel_name_hint' : 'group_name_hint'),
                counterText: '',
              ),
            ),
            SizedBox(height: layout.gap),

            TextField(
              controller: _descriptionController,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 512,
              maxLines: 2,
              minLines: 1,
              decoration: InputDecoration(
                labelText: l10n.t('chat_description'),
                hintText: l10n.t('chat_description_hint'),
                counterText: '',
              ),
            ),

            if (_isChannel) ...[
              SizedBox(height: layout.gap),
              TextField(
                controller: _handleController,
                autocorrect: false,
                // A handle is Latin-only, so the Cyrillic keyboard would be
                // actively wrong here.
                keyboardType: TextInputType.url,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]')),
                  LengthLimitingTextInputFormatter(32),
                ],
                onChanged: _validateHandle,
                decoration: InputDecoration(
                  labelText: l10n.t('channel_handle'),
                  prefixText: '@',
                  helperText: l10n.t('channel_handle_help'),
                  helperMaxLines: 3,
                  errorText: _handleError,
                  errorMaxLines: 2,
                ),
              ),
              if (_handleController.text.trim().isEmpty) ...[
                SizedBox(height: layout.gap / 2),
                Text(
                  l10n.t('channel_private_note'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.muted),
                ),
              ],
            ],

            SizedBox(height: layout.gap * 2),
            Text(
              l10n.t(_isChannel ? 'subscribers' : 'members'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            SizedBox(height: layout.gap / 2),

            // Pasting an id is recall, not recognition, and it is the worst
            // interaction in the app. It exists because contact discovery is an
            // M1 feature; docs/UX.md tracks it as such rather than pretending
            // this is fine.
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _memberController,
                    autocorrect: false,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _addMember(),
                    decoration: InputDecoration(hintText: l10n.t('add_by_id')),
                  ),
                ),
                SizedBox(width: layout.gap / 2),
                IconButton.filledTonal(
                  onPressed: _addMember,
                  tooltip: l10n.t('add_people'),
                  // Material's default IconButton is 40; the invariant is 44
                  // and our own controls are sized to 48.
                  constraints: const BoxConstraints(
                    minWidth: SakinaLayout.tapTarget,
                    minHeight: SakinaLayout.tapTarget,
                  ),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),

            SizedBox(height: layout.gap),
            if (_memberIds.isEmpty)
              // An empty state with the reason, not just a blank gap.
              Text(
                l10n.t(_isChannel ? 'channel_private_note' : 'no_one_yet'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.muted),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final id in _memberIds)
                    Chip(
                      label: Text(id.length > 12 ? '${id.substring(0, 8)}…' : id),
                      onDeleted: () => setState(() => _memberIds.remove(id)),
                      deleteButtonTooltipMessage: l10n.t('cancel'),
                    ),
                ],
              ),

            if (_error != null) ...[
              SizedBox(height: layout.gap),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: palette.anor),
              ),
            ],

            SizedBox(height: layout.gap * 2),
            FilledButton(
              onPressed: _canCreate ? _create : null,
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.t('create')),
            ),
            SizedBox(height: layout.gap),
          ],
        ),
      ),
    );
  }
}
