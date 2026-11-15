import 'package:flutter/material.dart';

import '../../../l10n.dart';
import '../../empty_state.dart';

/// The discovery surface.
///
/// ## Why it is empty rather than a grid
///
/// `docs/DIFFERENTIATION.md` names *"a crowded super-app launcher on day one"*
/// as a thing not to do: the mini-app grid is what this looks like **after**
/// people already open the app daily, and *"shipping the grid first is how you
/// get an app that does eleven things badly."* So the tab exists — the shape of
/// the app is settled early, and moving a tab later is far more disruptive than
/// filling one — and its content waits.
///
/// ## Where the work goes
///
/// This screen is built to grow by **addition**, not by rewrite. The intended
/// shape is a `CustomScrollView` of independent slivers, each one a self
/// contained feature that can land, be reordered, or be pulled without the
/// others noticing:
///
///  1. **Search** over the user's own chats and public channels. The API is
///     already there — `ApiClient.joinChannel` resolves a handle — so this is
///     the first slice worth shipping, and the only one that is useful before
///     there is any content at all.
///  2. **Channels to follow.** Needs a directory endpoint that does not exist.
///  3. **Posts and video.** A feed, its own model, and a decision about ranking
///     that is a product question rather than a UI one.
///  4. **The mini-app grid**, last, per the doc above.
///
/// Each of those is a `Sliver` added to the list below and a field added to
/// [SectionScope] if it needs a new client. None of them require touching
/// Chats, Calls or Profile — which is the whole reason the sections are split
/// the way they are.
class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('explore'))),
      // A CustomScrollView already, with one sliver, so the first real feature
      // is an insertion rather than a restructure.
      body: CustomScrollView(
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.explore_outlined,
              title: l10n.t('explore_empty_title'),
              body: l10n.t('explore_empty_body'),
            ),
          ),
        ],
      ),
    );
  }
}
