# Seven messengers, and what Sakina should take from each

Researched August 2026. Figures are from public reporting and move constantly —
treat the shape as durable and the numbers as approximate.

The seven were chosen for what they teach a national messenger with super-app
ambitions, not for size. Three are the incumbents Sakina has to survive
(Telegram, WhatsApp, Signal); three are super-apps that already made the
transition Sakina wants to make (WeChat, LINE, KakaoTalk); one is the closest
analogue that exists (Zalo).

---

## First: the market has changed under this project

Three findings matter more than anything in the comparison table, and one of
them invalidates an assumption in the original architecture doc.

### 1. WhatsApp leads in Tajikistan, not Telegram

A 2022 survey put **WhatsApp first at 46%, with imo second**. Telegram is not the
incumbent here the way it is in Russia or Iran. `docs/ARCHITECTURE.md` says
Telegram "won Central Asia on bad connections" — that is directionally right
about *why* apps win here and wrong about *which* app won. imo's presence is the
more interesting signal: it is a thin, low-bandwidth video-calling app that
spread through migrant communities on cheap phones. It won on weight, which is
the same bet Sakina is making.

### 2. The Tajikistan–Russia link is breaking right now

- **WhatsApp has been fully blocked in Russia since February 2026**; Telegram is
  heavily throttled. Roskomnadzor began restricting calls on both in August 2025.
- Russia is pushing **MAX**, a state messenger from VK — preinstalled by law on
  every phone sold there since September 2025, not end-to-end encrypted, with
  government services, ID and payments bundled in.

Tajikistan has one of the world's highest remittance-to-GDP ratios and a large
share of working-age men in Russia. The country's most-used messenger is blocked
at one end of its most important conversation. **That is the opening, and it has
a clock on it.**

### 3. Tajikistan already launched a state messenger — and it does not work

**ORIZ**, from TojikTelecom, launched 12 November 2025. Messaging, voice and
video, groups, channels, unlimited file sharing, servers inside Tajikistan,
Tajik/Russian/English, on both stores plus desktop and web. Explicitly aimed in
part at migrants in Russia.

Two things about it:

- **Execution is poor.** Asia-Plus journalists testing it at launch found chat
  and calling simply inactive, with calls returning errors.
- **No privacy story.** No indication of end-to-end encryption and no published
  privacy policy, against the backdrop of MAX being analysed as a data-collection
  tool with security-service access.

This cuts three ways, and all three should change the plan:

1. **The positioning is taken and then abandoned.** "Domestic messenger, data
   stays in Tajikistan" is now the state's slogan. Sakina cannot win by saying
   the same thing louder. It wins on the thing ORIZ conspicuously lacks: *it
   actually works*, and it treats users as customers rather than subjects.
2. **The regulatory direction is confirmed.** Data localisation, a state interest
   in domestic messaging, and an appetite to steer users onto approved platforms.
   Plan for in-country hosting and for the possibility that a private messenger
   attracts attention rather than indifference.
3. **The bar is low and the window is open.** A launched national messenger that
   fails on first use has spent the government's credibility, not Sakina's.

---

## The seven

### Telegram — the operating model to copy

~1B MAU, ~500M DAU. Revenue $870M in H1 2025, up 65% year on year, from Premium
(~15M subscribers), ads in large channels with a 50% revenue share to owners, and
Stars/TON. Five data centres. **About 30 engineers.**

That headcount is the finding. A billion-user messenger runs on a team smaller
than most Series A startups, because the architecture is boring and consistent: a
custom protocol (MTProto) optimised for multi-datacentre operation, no
end-to-end encryption on cloud chats so the server can do sync and search
cheaply, and features that are mostly compositions of the same message bus.

**Take:** the whole shape. Small team, cloud chats not E2EE by default, secret
chats opt-in, everything-is-a-message-type. Sakina's `seq`-based sync and open
`message.type` enum are already this model. Also take the channel revenue
share — paying creators is what pulled Telegram's content ecosystem into
existence, and Tajikistan's Telegram channel culture is the audience to poach.

**Do not take:** the 30-engineer security posture. That headcount is regularly
cited as a red flag, and a payments app cannot run that thin.

### WhatsApp — the incumbent to displace, and the reliability bar

2B+ users, ~40B messages/day. Erlang on the BEAM, a modified XMPP via ejabberd,
Mnesia; one connection per lightweight process, **2M+ concurrent connections per
server**, famously ~50 engineers at 1B users. Free to users; Meta monetises the
Business Platform and ads in Status/Channels. In 2026 it added usernames (so
phone numbers need not be shared), matured multi-device, and moved to
post-quantum key exchange (PQXDH).

**Take:** the reliability standard, and the honest warning that Node will not get
you to WhatsApp's per-node concurrency. `docs/ARCHITECTURE.md` already flags the
gateway as the piece to rewrite in Go; Erlang's numbers are why that is a real
plan and not a hedge. Also take **usernames** — for a country where a phone
number is tied to a Russian or Tajik SIM that may change, username-first identity
is more robust than WhatsApp's original design.

**The opportunity:** it is blocked where a third of the audience works.

### WeChat — the destination, and the trap

1.43B users. **945M mini-program users, 4.3M mini-programs**, average user
touching ~9.8 of them; >95% of Chinese companies run one. WeChat Pay: ~935M
users, ~40% of China's mobile payments, 1.3B+ transactions/day. Daily services —
transport, utilities, food — are 32% of top mini-program traffic.

**Take:** the architecture insight that everything is a message type and every
merchant is an account. That is why `users.kind` and the open `message.type` enum
exist in the schema already. Also take the sequencing: **WeChat Pay launched in
2013, two years after the messenger, and only took off after Red Packets in
2014** — a *social* feature, not a financial one. Payments inside a conversation
beat payments in a tab.

**The trap:** WeChat's ecosystem is a function of China's scale, regulatory
structure and mobile-first leapfrog. Tajikistan has ~10M people. The mini-program
platform is an M3+ idea, and copying its surface area early would produce a
worse messenger with a bigger settings screen.

### LINE — how a super-app wins a small market

~182–230M MAU concentrated in four countries: Japan 100M+, Thailand 54M (80%+ of
the country), Taiwan 22M (**92% penetration**, the highest per-capita anywhere).
Monetisation leans on stickers, ads and content — 510M stickers sent per day.

**This is the most encouraging case study here.** LINE did not win globally; it
won *completely* in a handful of markets by being culturally native. Taiwan at 92%
is the existence proof that a national messenger can reach near-total penetration
against WhatsApp and Messenger.

**Take:** stickers, seriously. They read as frivolous and they are a primary
revenue line and the strongest cultural-fit lever available. Tajik-language
stickers, Navruz sets, local humour, recognisable Dushanbe references — cheap to
make, impossible for WhatsApp to match, and they are what makes an app feel
*ours*. For 10k users this is arguably the single highest-leverage feature after
reliable messaging.

### KakaoTalk — the closest thing to Sakina's end state

49M MAU in South Korea, **~95% of the population**. KakaoPay ~40M users;
KakaoBank 26.7M customers and 20M MAU by end-2025 — a full licensed bank grown
out of a chat app. Kakao group revenue KRW 8.1T (~$6.1B) in 2025.

**This is the roadmap Sakina is describing, executed.** Messenger → payments →
licensed bank → everything else. It is also the honest timeline: KakaoTalk
launched 2010, KakaoPay 2014, KakaoBank 2017. **Seven years from messenger to
bank**, in a country with far more developed financial infrastructure.

**Take:** the sequence and the patience. Also the specific insight that near-total
national penetration is what makes the financial products work — KakaoBank is
viable because KakaoTalk is universal, not the reverse. Get to being the default
messenger first; the payments layer is a consequence, not a strategy.

### Zalo — the direct analogue, including its recent stumble

Vietnam. **98% usage among Vietnamese mobile users vs Facebook Messenger's 88%**;
51% preference share against Facebook's 21% and Messenger's 20%. Built by VNG
from 2012, deliberately "mobile-first, minimal features, speed and reliability"
to differentiate from WeChat and LINE. Early architecture: C/C++ and Java,
event-based I/O, HAProxy, Nginx, PostgreSQL/MySQL, connection servers at 1M
concurrent connections and 200k messages/second. Documented lessons: avoid HTTP
long-polling, optimise for large payloads rather than small ones, custom memory
allocator to avoid fragmentation.

**This is the playbook.** A national messenger that beat Facebook *in its own
country* by being faster and more local, then became a super-app. Their stated
differentiator — minimal features, speed, reliability — is exactly Sakina's M0.

**And the warning:** in early 2026 Zalo fell out of Google Play's top 200 and
dropped to 8th on the App Store, attributed to policy changes and user
frustration. Dominance built on being the pleasant local option is *lost* by
becoming the annoying local option. Whatever Sakina does with monetisation,
ads or state cooperation, this is the failure mode.

### Signal — the benchmark, not the model

The Signal Protocol's double ratchet is what WhatsApp, Google Messages and
Messenger all licensed. Two ideas worth studying regardless of whether Sakina
ever ships E2EE:

- **Sealed sender** — the server cannot see who sent a message. Clients derive a
  delivery token from their profile key and prove knowledge of it to send.
- **Private contact discovery** — matching your address book against registered
  users inside an attested SGX enclave, so the server never learns your contacts.

**Take:** the contact-discovery design, at M1. Phone-book matching is the single
most privacy-sensitive thing a messenger does, and "upload the address book in
plaintext" is the default everyone regrets. Even without enclaves, hashed
identifiers with a per-deployment salt is a large improvement and is the right
default for a country where who-knows-whom is sensitive information.

**Not the model:** Signal's threat model is incompatible with a licensed payments
platform, and its funding model (a nonprofit foundation) is not available here.

---

## What this changes

**Confirmed by the research.** The message-bus-with-open-types architecture is
what all three super-apps actually are. Bandwidth discipline is what imo, Zalo
and Telegram all won on. Small teams genuinely do run large messengers. Cloud
chats not E2EE by default is the only model compatible with the payments
roadmap — Telegram, WeChat, LINE, KakaoTalk and MAX all made the same call.

**Changed by the research.**

1. **The competitor is WhatsApp, not Telegram** — and its blockage in Russia is
   the wedge. Priority shifts toward anything serving the diaspora conversation:
   reliable delivery on Russian networks, cheap voice, eventually remittances.
2. **ORIZ exists, so "domestic messenger" is no longer differentiating.** Sakina's
   position has to be quality and trust, not nationality. That also means being
   ready to explain how Sakina differs from a state messenger, because users will
   ask.
3. **Stickers move up the roadmap.** Currently unlisted; on LINE's evidence they
   belong in M1 alongside media. They are the cheapest cultural moat available.
4. **Usernames move up.** WhatsApp added them in 2026 for good reason, and for an
   audience switching between Tajik and Russian SIMs they matter more here.
5. **Contact discovery needs a privacy design before it is built**, per Signal.
6. **Payments-in-conversation, not payments-in-a-tab.** WeChat's Red Packet
   lesson: the feature that broke through was social, not financial.

**Sequencing, from KakaoTalk and Zalo.** Neither started with payments. Both won
the messenger completely first, in one country, on speed and local fit. Seven
years to a bank is the realistic clock. The 5–10k user target is the right size
of first step; see `docs/GROWTH.md`.

---

## Sources

- [Telegram statistics — Business of Apps](https://www.businessofapps.com/data/telegram-statistics/) · [DemandSage](https://www.demandsage.com/telegram-statistics/) · [Telegram's 30 engineers — TechCrunch](https://techcrunch.com/2024/06/24/experts-say-telegrams-30-engineers-team-is-a-security-red-flag)
- [WhatsApp architecture — ByteByteGo](https://blog.bytebytego.com/p/how-whatsapp-handles-40-billion-messages) · [Erlang at scale](https://scalewithchintan.com/blog/whatsapp-erlang-architecture-2-billion-users)
- [WeChat statistics — Business of Apps](https://www.businessofapps.com/data/wechat-statistics/) · [Mini-programs overseas growth](https://super-apps.ai/blogs/wechat-mini-programs-see-40-overseas-transaction-growth-signaling-global-super-app-expansion)
- [LINE statistics — Business of Apps](https://www.businessofapps.com/data/line-statistics/) · [The Japanese super-app that outsmarted global giants](https://globis.eu/the-japanese-app-line/)
- [Kakao super-app model](https://digitalinasia.com/kakao-super-app-model/) · [KakaoBank](https://en.wikipedia.org/wiki/KakaoBank) · [Kakao IR, Feb 2026](https://t1.kakaocdn.net/kakaocorp/admin/ir/results-announcement/5962.pdf)
- [Zalo vs Facebook in Vietnam — Q&Me](https://qandme.net/en/report/facebook-vs-zalo-in-Vietnam.html) · [Zalo remains Vietnam's most-used app](https://english.mst.gov.vn/zalo-remains-vietnams-most-used-messaging-app-197157664.htm) · [Why Zalo is no longer Vietnam's favourite — Vietcetera](https://vietcetera.com/en/why-zalo-is-no-longer-vietnams-favorite-messaging-app) · [Zalo real-time architecture](https://slideshare.net/Zalo_app/experience-lessons-from-architecture-of-zalo-real-time-system)
- [Signal: sealed sender](https://signal.org/blog/sealed-sender/) · [Signal: private contact discovery](https://signal.org/blog/private-contact-discovery/)
- [ORIZ launch — bne IntelliNews](https://www.intellinews.com/tajikistan-launches-national-messenger-app-oriz-in-important-step-towards-digital-independence-411154) · [ORIZ surveillance concerns — The Diplomat](https://thediplomat.com/2025/12/tajikistan-launches-national-messenger-oriz-amid-surveillance-concerns/) · [Asia-Plus first test](https://asiaplustj.info/en/news/tajikistan/society/20251113/tajikistan-launches-its-first-national-messaging-app-oriz) · [Communication Service of Tajikistan](https://cs.gov.tj/en/national-messenger-oriz-an-important-step-toward-tajikistans-digital-independence/)
- [Most popular messengers in Tajikistan 2022 — Statista](https://www.statista.com/statistics/1403810/tajikistan-most-popular-messengers/)
- [Russia's Max and the WhatsApp block — France24](https://www.france24.com/en/live-news/20260323-russia-s-max-the-unencrypted-super-app-being-forced-on-citizens) · [Russian internet censorship 2026 — Zona Media](https://en.zona.media/article/2026/04/07/russian_internet_censorship_2026)
- [Telegram Gateway API](https://core.telegram.org/gateway)
