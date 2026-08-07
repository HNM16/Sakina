# Interface: Telegram-shaped, Nielsen-checked

Two constraints, and they mostly agree with each other.

**Telegram-shaped**, because familiarity is free adoption. Every target user
already knows how a messenger works, and every gratuitous difference is a tax
paid by someone deciding whether to switch. Sakina should feel like an app they
already know how to use — chat list, tap to open, bubbles right for mine and left
for theirs, input pinned to the bottom.

**Nielsen-checked**, because "looks like Telegram" is not the same as "navigates
well," and copying a layout without understanding why it works produces something
that resembles the original and frustrates people.

Where the two conflict, familiarity usually wins for layout and Nielsen wins for
flow. A user who cannot find a button is annoyed; a user who cannot get *out* of
a screen uninstalls.

---

## The ten heuristics, applied

Each one lists what is already built, and what is still owed. `→` marks work not
yet done.

### 1. Visibility of system status

The user should never wonder whether something happened.

- **Connection state is in the app bar**, not a dialog — `chat_list_screen.dart`
  shows a `connecting` / `offline` strip when the socket is down. It is status,
  not an error, because the app stays fully usable offline. A modal here would be
  a lie about severity.
- **Every message carries its delivery state** — clock while pending, tick when
  the server assigns a `seq`, error icon on failure (`chat_screen.dart`). This is
  what the whole `seq` design in `docs/PROTOCOL.md` exists to make honest. On a
  bad connection this single icon is the most-read pixel in the app.
- **The sign-in button becomes a spinner** while a request is in flight.
- → Typing indicators exist on the wire and render, but "sending photo…" and
  upload progress arrive with media in M1.

### 2. Match between the system and the real world

- **Tajik first**, then Russian, then English. Not a machine translation — the
  strings in `l10n.dart` are written, and error messages say what happened in
  plain language rather than naming an error code.
- **Tajik Cyrillic sorts correctly**, via the ICU collation in the database. Under
  the C locale, ғ ӣ қ ӯ ҳ ҷ sort wrongly and contact lists come out scrambled —
  a small detail that makes an app feel foreign in about two seconds.
- → Dates and times in Tajik conventions, not `intl` defaults.

### 3. User control and freedom

The heuristic that catches the worst bugs.

- **The sign-in flow has a working back action.** The first version disabled the
  address field once the code was sent — a typo'd address was then unrecoverable
  on the very first screen a user ever sees. Now there is an explicit back step
  and a "change address" link. This is the single most valuable fix in this
  document.
- → **Undo, not confirm.** Deleting a message or leaving a group should happen
  immediately with a few seconds to undo, rather than a confirmation dialog.
  Confirmation dialogs are trained away within a week; undo is not.
- → Cancel an in-flight upload. Retry a failed send from the bubble itself.

### 4. Consistency and standards

- **Material 3 defaults**, respected rather than fought. Native back gestures,
  system share sheet, standard text selection.
- **Telegram's spatial conventions**: chat list → chat, back returns to the list,
  own messages right and others left, composer at the bottom.
- One meaning per icon across the app. A tick always means delivered.

### 5. Error prevention

Better than good error messages.

- **The email address is checked for shape before the request goes out** — the
  common typo is caught without a round trip.
- **Invite field appears only when it becomes relevant** (when the server says
  the deployment is invite-only), rather than sitting there confusing everyone.
- **Sends are idempotent by construction.** Double-tapping send on a slow
  connection cannot produce two messages, because the client reuses `client_id`
  and the server dedups. The class of error is designed out rather than warned
  about.
- → Warn before sending a large file on mobile data. Data costs real money here.

### 6. Recognition rather than recall

- **The code screen shows the address the code went to.** Nobody should have to
  remember what they typed thirty seconds ago in a different app.
- **`autofillHints.oneTimeCode`** lets the OS offer the code, so it need not be
  memorised across an app switch at all.
- → Recently-used contacts at the top of the new-chat sheet. Right now the sheet
  asks for a user ID, which is pure recall and is the worst screen in the app —
  it exists only because contact discovery is an M1 feature.

### 7. Flexibility and efficiency of use

- → Swipe to reply, long-press for the action menu, pinned chats, archive.
- → **Usernames.** WhatsApp added them in 2026, and they matter more here: a user
  switching between a Tajik and a Russian SIM keeps their identity. The schema
  already has the column.
- Beginners and experts differ sharply in this audience — some users are on their
  first smartphone. Defaults must work with zero configuration; power features
  must be discoverable but never required.

### 8. Aesthetic and minimalist design

- Zalo's own account of beating Facebook in Vietnam: "mobile-first, minimal
  features, speed and reliability." Every additional element competes with the
  message list for attention and with the CPU for frames.
- **Target device is a cheap, low-RAM Android**, not a flagship. Animations
  should be short and cheap. Test on the worst phone available.
- No feature earns a permanent home in the navigation until it is used weekly.

### 9. Help users recognise, diagnose and recover from errors

- Server errors are **domain errors with human messages** — "that invite code has
  been used up", not `FORBIDDEN_403`. The `DomainError` type exists to keep this
  the path of least resistance.
- A failed send **stays in the conversation** marked failed rather than
  disappearing. The message is not lost, and the recovery is obvious.
- → Tapping a failed message should retry it. Currently it only shows the state.

### 10. Help and documentation

- The app should need none for its core loop, and it currently does not.
- → An in-app FAQ for the questions this specific audience will actually ask:
  who runs Sakina, where the data is stored, how it differs from a state
  messenger, whether it works from Russia. `docs/GROWTH.md` notes users *will*
  ask; not having a straight answer is a trust problem, not a documentation gap.

---

## Screens: current and planned

| Screen | State | Notes |
| --- | --- | --- |
| Sign in — address | Built | Validation, error inline, autofill |
| Sign in — code | Built | Back action, shows target address, invite field when needed |
| Chat list | Built | Connection strip, unread badges, sorted by recency |
| Chat | Built | Bubbles, delivery state, typing indicator |
| New chat | Placeholder | Asks for a user ID — replaced by contact discovery in M1 |
| Profile / settings | → M1 | Display name, username, avatar, language, devices |
| Group creation | → M1 | The atomic unit of adoption; see `docs/GROWTH.md` |
| Media viewer | → M1 | |
| Stickers | → M1 | Higher priority than it looks — see the LINE case in the analysis |

## The rule that outranks all of this

The UI reads only from local SQLite; the network layer's only job is to write
into it (`chat_repository.dart`). Every heuristic above assumes the interface
responds instantly whether or not there is a connection. Break that rule and no
amount of interface polish will save the experience on a Tajik mobile network.
