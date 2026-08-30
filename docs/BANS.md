# Making a ban stick

The goal, stated the way it was asked: when someone is banned and comes back
with a new address, the server should know it is still them.

This is achievable, with real limits. What follows is what actually works on
current Android and iOS — the folklore in this area is a decade out of date and
most advice found online describes APIs that no longer exist.

---

## What is *not* available

Worth clearing first, because it is where everyone starts.

| | Status |
| --- | --- |
| **IMEI** | Requires `READ_PRIVILEGED_PHONE_STATE`, granted only to system and carrier apps. Not available to a Play Store app on Android 10+. |
| **Serial number** | Same. `Build.getSerial()` is privileged. |
| **MAC address** | Returns `02:00:00:00:00:00` since Android 6. Randomised per-network since Android 10. |
| **iOS device ID / UDID** | Removed in 2013. Nothing has replaced it. |
| **iOS fingerprinting** | Explicitly prohibited by App Store review. Apple rejects apps that build device fingerprints from hardware characteristics. |

**Anyone offering "physical phone information" from a normal app is describing
2015.** Attempting it now yields nothing on Android and gets the app rejected on
iOS.

## What *is* available

### Android — `Settings.Secure.ANDROID_ID` (SSAID)

The good one. Since Android 8 it is scoped to the app signing key, the user
profile and the device, which means:

- **Survives uninstall and reinstall** as long as the signing key is unchanged
- **Survives OS updates**
- Different for every app, so it is not a cross-app tracking identifier
- **Cleared by a factory reset**, and changed if the signing key rotates

That is precisely the property needed: a ban outlives deleting the app.

### iOS — DeviceCheck

Apple's sanctioned answer, and it exists for exactly this purpose. Two bits of
storage per device, per developer, held on Apple's servers:

- **Survives uninstall, reinstall and OS upgrade**
- Cleared only by a factory reset
- Two bits — enough to say "this device is banned", and nothing else

Two bits sounds absurdly small until you notice the question being asked is a
yes/no. `identifierForVendor` is *not* a substitute: it resets the moment the
user removes every app from the vendor, which is one tap for a single-app
developer.

### Both — attestation

- **Play Integrity API** (Android) and **App Attest** (iOS) verify the request
  came from a genuine, unmodified copy of the app on an untampered device.

They give no stable identifier, but they answer a different and important
question: *is the client lying to us?* Without attestation, a modified client
can simply send a made-up SSAID and walk past every check here. Attestation is
what makes the rest of this real rather than decorative.

---

## What is implemented

`packages/core/src/repo/bans.ts`, `packages/db/src/schema.ts`

- `device_fingerprints` — one row per device seen, storing a **peppered HMAC**
  of the platform identifier. The raw value is never stored: matching does not
  need it, and a table of real device identifiers is a tracking database we have
  no business holding.
- `device_fingerprint_users` — which accounts have been seen on which hardware.
  This is the propagation graph.
- `bans` — against a user or a device, with a reason, optional expiry, and a
  `liftedAt` rather than deletion, because "has this person been banned before"
  is a question moderation will need answered.
- `assertNotBanned()` runs on every sign-in, **checking the device before the
  account** — the whole point is the case where the account is new and only the
  hardware is recognised.
- `banUserAndDevices()` bans the account, every device it has used, and every
  other account seen on those devices.

**One hop, not transitive.** Two accounts sharing a phone is normal — a family,
a shared handset, a resold device. Walking the graph further would eventually
ban a village.

Refusals say "this device is not allowed to use Sakina" and nothing more.
A precise message is a free hint about exactly what to change next time.

### What it actually stops

Verified in `services/api/scripts/ban-smoke.ts`:

| Evasion attempt | Result |
| --- | --- |
| Sign back in with the banned account | Refused |
| **New email, app reinstalled, same phone** | **Refused** |
| Third address, same phone | Refused |
| Factory reset (new SSAID) | **Gets through** |
| A different phone | Gets through |
| No attestation at all (web) | Signs in, untracked |
| An unrelated device | Unaffected |

The last three rows are the honest ceiling — **for everyone, Snapchat
included.** Snapchat's own reputation here came from aggressive fingerprinting
that would now be rejected by Apple, and determined users still get past it with
a factory reset or a second phone. The realistic goal is to make evasion cost
real effort, not to make it impossible. Someone willing to factory-reset their
phone for each ban is not the problem an anti-abuse system is sized for.

Note that a missing attestation **never blocks sign-in**. The web client has no
such identifier, and an old Android may fail to read SSAID. Degrading to "less
trusted" is correct; refusing to let someone in because their phone did not
answer a question is not.

---

## The stronger lever, for this product specifically

Hardware identity is the weakest of the tools available here. For an
invite-only network of five to ten thousand people, **the invite graph is worth
more than any fingerprint.**

Every account is vouched for by an existing account, and that edge is recorded.
So when someone is banned:

- the code they used is known, and so is who created it
- an inviter whose invitees are repeatedly banned can lose invite privileges
- rejoining requires convincing a real person to spend one of their five invites
  on you, knowing it counts against them

That is social cost, and it scales better than technical countermeasures because
it does not depend on winning an arms race against a modified APK. It is also
already built — `invite_codes.createdBy` and `invite_redemptions` carry the
graph.

**Recommendation:** run invite-only through the beta, and wire "inviter
accountability" before "better fingerprinting". The second is a treadmill; the
first is a property of the network.

---

## Client work still needed

The server side is done. The Flutter client does not yet collect attestation:

- **Android** — read `Settings.Secure.ANDROID_ID` via a small platform channel,
  send it as `attestation.source = "android_id"`.
- **iOS** — `DCDevice.current.generateToken()`, send as
  `source = "devicecheck"`. Requires a server-side call to Apple's DeviceCheck
  API with an App Store Connect key to read and set the bits.
- **Both** — Play Integrity / App Attest tokens in `attestation.integrity_token`,
  verified server-side. Without this a modified client can fabricate the
  identifier, so treat unattested fingerprints as advisory rather than
  authoritative.

## Privacy, since this is surveillance-adjacent

Worth being deliberate about, in a country where a state messenger has just
launched amid surveillance concerns (`docs/COMPETITIVE-ANALYSIS.md`). Sakina's
position is that it treats users as customers rather than subjects, and that has
to be true in the schema, not only in the pitch.

- **Only hashes are stored.** No raw device identifiers, ever.
- **Scoped identifiers only.** SSAID and DeviceCheck are per-app by design; they
  cannot be correlated with any other company's data.
- **Used for one purpose.** Enforcing bans. Not analytics, not ad targeting, not
  building a graph of who owns which phone.
- **IP addresses are hashed** too, for the signup counters.
- **Bans are appealable and liftable**, and lifting is a first-class operation
  rather than a manual database edit.

Say all of this in the privacy policy. Users in this market will ask who is
behind Sakina and where the data goes, and having a straight answer is part of
the product.
