import 'package:flutter/material.dart';

import '../../../l10n.dart';
import '../../empty_state.dart';

/// The call log.
///
/// ## What this is
///
/// Deliberately empty, and honestly so. `docs/CALLS.md` is the design — WebRTC,
/// the signalling frames, the CGNAT problem that actually decides the
/// architecture — and it says plainly: *"Not built. Target: M2."* There is no
/// signalling, no peer connection and no call history, so there is nothing to
/// list. A screen full of invented calls would be a lie told to ourselves.
///
/// ## Where the work goes
///
/// The seams, in the order `docs/CALLS.md` sets out:
///
///  1. **A `CallService`** beside `PushService` in `lib/src/`, owning the peer
///     connection and the `call.*` socket frames. It belongs there, not here,
///     because an incoming call has to ring with this screen closed.
///  2. **A `calls` field on [SectionScope]** carrying that service in. Nullable
///     until it exists, which is what lets this screen ask honestly.
///  3. **A `CallLogEntry` model and store table**, alongside messages — the log
///     is local history and must survive offline like everything else.
///  4. **This screen**: swap [EmptyState] for a list when the service is
///     non-null, and keep the empty state for the genuinely-no-calls case.
///  5. **A call screen** pushed onto this section's own navigator, so it
///     behaves like every other push in the app.
///
/// Nothing above touches another section. That is the point of the boundary.
class CallsScreen extends StatelessWidget {
  const CallsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('calls'))),
      body: EmptyState(
        icon: Icons.call_outlined,
        title: l10n.t('calls_empty_title'),
        body: l10n.t('calls_empty_body'),
      ),
    );
  }
}
