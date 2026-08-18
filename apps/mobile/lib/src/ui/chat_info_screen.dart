import 'package:flutter/material.dart';

import '../api_client.dart';
import '../chat_repository.dart';
import '../l10n.dart';
import '../layout.dart';
import '../models.dart';
import '../theme.dart';

/// Who is in this chat, and what you are allowed to do about it.
///
/// One screen for groups and channels; a direct chat never opens it, because
/// "the two of you" is not a list that needs managing.
///
/// The heuristic that shaped this screen is #3, user control and freedom.
/// Leaving is the destructive action here, and it uses **undo rather than
/// confirm** — `docs/UX.md` argues the case: a confirmation dialog is trained
/// away within a week of daily use, and an undo is not. So Leave happens
/// immediately and offers a few seconds to take it back.
class ChatInfoScreen extends StatefulWidget {
  const ChatInfoScreen({
    super.key,
    required this.repository,
    required this.chatId,
  });

  final ChatRepository repository;
  final String chatId;

  @override
  State<ChatInfoScreen> createState() => _ChatInfoScreenState();
}

class _ChatInfoScreenState extends State<ChatInfoScreen> {
  List<ChatMember>? _members;
  int _total = 0;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  ChatSummary? get _chat {
    for (final chat in widget.repository.chats) {
      if (chat.id == widget.chatId) return chat;
    }
    return null;
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final page = await widget.repository.api.listMembers(widget.chatId);
      if (!mounted) return;
      setState(() {
        _members = page.members;
        _total = page.total;
      });
    } on ApiException catch (err) {
      if (!mounted) return;
      setState(() => _error = err.message);
    }
  }

  Future<void> _guard(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await _load();
    } on ApiException catch (err) {
      if (mounted) setState(() => _error = err.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addMember() async {
    final l10n = L10n.of(context);
    final controller = TextEditingController();

    final id = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.t('add_people')),
        content: TextField(
          controller: controller,
          autofocus: true,
          autocorrect: false,
          decoration: InputDecoration(hintText: l10n.t('add_by_id')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(l10n.t('add_people')),
          ),
        ],
      ),
    );
    controller.dispose();

    if (id == null || id.isEmpty) return;
    await _guard(() => widget.repository.api.addMembers(widget.chatId, [id]));
  }

  /// Leave, with a window to take it back.
  ///
  /// The rejoin on undo is a real request, not a local rollback — the server
  /// already removed us. It only works for a channel with a public handle or a
  /// chat we can be re-added to, so if it fails the message says so rather than
  /// pretending the undo worked.
  Future<void> _leave() async {
    final l10n = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final chat = _chat;

    await _guard(() => widget.repository.api.removeMember(
          widget.chatId,
          widget.repository.selfId,
        ));
    if (!mounted) return;

    final username = chat?.username;
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.t('left_chat')),
        duration: const Duration(seconds: 6),
        action: username == null
            ? null
            : SnackBarAction(
                label: l10n.t('undo'),
                onPressed: () async {
                  try {
                    await widget.repository.api.joinChannel(username);
                    await widget.repository.resync();
                  } on ApiException catch (err) {
                    messenger.showSnackBar(SnackBar(content: Text(err.message)));
                  }
                },
              ),
      ),
    );
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final layout = SakinaLayout.of(context);
    final palette = SakinaPalette.of(context);
    final chat = _chat;
    final members = _members;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t(chat?.isChannel ?? false ? 'subscribers' : 'members')),
      ),
      floatingActionButton: (chat?.isAdmin ?? false)
          ? FloatingActionButton(
              onPressed: _busy ? null : _addMember,
              tooltip: l10n.t('add_people'),
              child: const Icon(Icons.person_add_outlined),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: layout.screenPadding,
          children: [
            if (chat != null) ...[
              Center(child: ChorkhonaMark(size: 56)),
              SizedBox(height: layout.gap),
              Text(
                chat.displayTitle(
                  widget.repository.selfId,
                  savedLabel: l10n.t('saved_messages'),
                ),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (chat.username != null)
                Text(
                  '@${chat.username}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: palette.saffron),
                ),
              if (chat.description != null && chat.description!.isNotEmpty) ...[
                SizedBox(height: layout.gap),
                Text(chat.description!, textAlign: TextAlign.center),
              ],
              SizedBox(height: layout.gap * 2),
            ],

            if (_error != null)
              // An error state with a way out, not a dead end.
              Padding(
                padding: EdgeInsets.only(bottom: layout.gap),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, size: 18, color: palette.anor),
                    SizedBox(width: layout.gap / 2),
                    Expanded(
                      child: Text(
                        _error!,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: palette.anor),
                      ),
                    ),
                    TextButton(onPressed: _load, child: Text(l10n.t('retry'))),
                  ],
                ),
              ),

            if (members == null)
              // Loading, sized roughly like the list it replaces so the screen
              // does not jump when the rows arrive.
              Padding(
                padding: EdgeInsets.symmetric(vertical: layout.gap * 3),
                child: const Center(child: CircularProgressIndicator()),
              )
            else if (members.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: layout.gap * 3),
                child: Text(
                  l10n.t('no_one_yet'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: palette.muted),
                ),
              )
            else ...[
              Text(
                '$_total ${l10n.t(chat?.isChannel ?? false ? 'subscribers' : 'members').toLowerCase()}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              SizedBox(height: layout.gap / 2),
              for (final member in members)
                _MemberTile(
                  key: ValueKey(member.user.id),
                  member: member,
                  isSelf: member.user.id == widget.repository.selfId,
                  // Only the owner may change roles; an admin who can mint
                  // admins can lock the owner out of their own channel.
                  canManage: (chat?.role == 'owner') && !_busy,
                  onPromote: () => _guard(() => widget.repository.api
                      .setRole(widget.chatId, member.user.id, 'admin')),
                  onDemote: () => _guard(() => widget.repository.api
                      .setRole(widget.chatId, member.user.id, 'member')),
                  onRemove: () => _guard(() => widget.repository.api
                      .removeMember(widget.chatId, member.user.id)),
                ),
            ],

            SizedBox(height: layout.gap * 2),
            if (chat != null && !chat.isDirect)
              OutlinedButton(
                onPressed: _busy ? null : _leave,
                style: OutlinedButton.styleFrom(
                  foregroundColor: palette.anor,
                  minimumSize: const Size.fromHeight(SakinaLayout.tapTarget),
                ),
                child: Text(l10n.t('leave_chat')),
              ),
            SizedBox(height: layout.gap),
          ],
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    super.key,
    required this.member,
    required this.isSelf,
    required this.canManage,
    required this.onPromote,
    required this.onDemote,
    required this.onRemove,
  });

  final ChatMember member;
  final bool isSelf;
  final bool canManage;
  final VoidCallback onPromote;
  final VoidCallback onDemote;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final layout = SakinaLayout.of(context);
    final palette = SakinaPalette.of(context);

    final name = member.user.displayName;
    final isOwner = member.role == 'owner';

    return ListTile(
      contentPadding: EdgeInsets.zero,
      minTileHeight: SakinaLayout.tapTarget + 8,
      leading: SizedBox(
        width: layout.avatarSize,
        height: layout.avatarSize,
        child: CircleAvatar(
          backgroundColor: palette.line,
          child: Text(name.isEmpty ? '?' : name.substring(0, 1).toUpperCase()),
        ),
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: member.role == 'member'
          ? null
          : Text(
              l10n.t(isOwner ? 'owner_role' : 'admin_role'),
              // Saffron is the rare-warmth colour and this is one of the rare
              // places that earns it: it marks the person who can act.
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: palette.saffron),
            ),
      // The owner cannot be demoted or removed here, and there is nothing to do
      // to yourself from this row — Leave is its own button at the bottom.
      trailing: !canManage || isOwner || isSelf
          ? null
          : PopupMenuButton<String>(
              tooltip: l10n.t('members'),
              onSelected: (value) => switch (value) {
                'promote' => onPromote(),
                'demote' => onDemote(),
                _ => onRemove(),
              },
              itemBuilder: (context) => [
                if (member.role == 'member')
                  PopupMenuItem(value: 'promote', child: Text(l10n.t('admin_role')))
                else
                  PopupMenuItem(value: 'demote', child: Text(l10n.t('members'))),
                PopupMenuItem(value: 'remove', child: Text(l10n.t('leave_chat'))),
              ],
            ),
    );
  }
}
