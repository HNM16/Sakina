import { SignJWT, importPKCS8 } from "jose";
import { connect as connectHttp2, constants as http2 } from "node:http2";

/**
 * Push notifications.
 *
 * The reason this exists at all: when the app is closed, the WebSocket is dead.
 * The OS killed it, and no amount of protocol design changes that. Delivery to
 * a closed app has to go through the platform push services, and there is no
 * alternative — a background socket is not something Android or iOS will let an
 * app keep.
 *
 * ## What is in the payload, and what is deliberately not
 *
 * The payload carries a chat id and a sequence number. It does **not** carry
 * message text. Two reasons, both firm:
 *
 *   1. Message content in a push payload is message content handed to Google
 *      and Apple. There is no version of that which is compatible with the
 *      privacy position in docs/BANS.md.
 *   2. It breaks the moment end-to-end encryption arrives, and reworking the
 *      notification path then is worse than doing it right now.
 *
 * So the notification says "new message", the client wakes, opens its socket,
 * syncs by seq, and — on iOS via a Notification Service Extension, on Android
 * before posting the notification — rewrites the text locally. Signal works
 * this way for the same reason.
 *
 * A generic alert body is still included rather than sending a silent,
 * data-only push. Silent pushes are throttled hard by iOS and unreliable in
 * Android's Doze; a user-visible notification that arrives is worth more than a
 * perfectly minimal one that does not.
 */

export interface PushMessage {
  token: string;
  /** Localised generic title/body. Never the message text. */
  title: string;
  body: string;
  /** Woken client uses these to sync. Values must be strings — FCM requires it. */
  data: Record<string, string>;
  /** Badge count for iOS, when known. */
  badge?: number | undefined;
  collapseKey?: string | undefined;
}

export type PushOutcome =
  | { status: "sent" }
  /** The token is dead — unregistered, uninstalled, wrong environment. Retire it. */
  | { status: "unregistered"; reason: string }
  /** Transient. Worth retrying later; do not count against the token. */
  | { status: "failed"; reason: string };

export interface PushProvider {
  readonly name: string;
  send(message: PushMessage): Promise<PushOutcome>;
  close?(): Promise<void>;
}

/** Generic copy, in the same three languages as the app. Never message content. */
const COPY: Record<string, { title: string; body: string; bodyGroup: string }> = {
  tg: { title: "Сакина", body: "Паёми нав", bodyGroup: "Паёми нав дар гурӯҳ" },
  ru: { title: "Сакина", body: "Новое сообщение", bodyGroup: "Новое сообщение в группе" },
  en: { title: "Sakina", body: "New message", bodyGroup: "New message in a group" },
};

export function pushCopy(locale: string | undefined, isGroup = false) {
  const copy = COPY[locale ?? "tg"] ?? COPY.tg!;
  return { title: copy.title, body: isGroup ? copy.bodyGroup : copy.body };
}

// ---------------------------------------------------------------------------
// Development
// ---------------------------------------------------------------------------

/**
 * Records instead of sending. This is what makes push testable without a
 * Firebase project, an Apple developer account, or a physical handset — see
 * services/worker/scripts/push-smoke.mjs.
 */
export class ConsolePushProvider implements PushProvider {
  readonly name = "console";
  readonly sent: Array<PushMessage & { at: number }> = [];

  constructor(private readonly limit = 100) {}

  async send(message: PushMessage): Promise<PushOutcome> {
    // A token nobody registered is treated as dead, so the retirement path is
    // exercised in development rather than discovered in production.
    if (message.token.startsWith("dead-")) {
      return { status: "unregistered", reason: "simulated dead token" };
    }

    this.sent.push({ ...message, at: Date.now() });
    if (this.sent.length > this.limit) this.sent.shift();

    console.log(`[push:console] -> ${message.token.slice(0, 24)} ${JSON.stringify(message.data)}`);
    return { status: "sent" };
  }
}

// ---------------------------------------------------------------------------
// FCM (Android)
// ---------------------------------------------------------------------------

export interface FcmOptions {
  projectId: string;
  clientEmail: string;
  /** PEM contents of the service account private key. */
  privateKey: string;
  baseUrl?: string;
  tokenUrl?: string;
}

/**
 * Firebase Cloud Messaging, HTTP v1.
 *
 * The legacy server-key API was shut down in 2024, so this is the only option:
 * OAuth2 with a service account. Implemented directly rather than through the
 * Firebase Admin SDK, which is a very large dependency for one HTTP call — and
 * the token exchange is a signed JWT we can already produce with `jose`.
 */
export class FcmPushProvider implements PushProvider {
  readonly name = "fcm";

  private accessToken: string | null = null;
  private accessTokenExpiresAt = 0;

  constructor(private readonly options: FcmOptions) {}

  private async getAccessToken(): Promise<string> {
    // Refreshed a minute early so a token cannot expire mid-flight.
    if (this.accessToken && Date.now() < this.accessTokenExpiresAt - 60_000) {
      return this.accessToken;
    }

    const tokenUrl = this.options.tokenUrl ?? "https://oauth2.googleapis.com/token";
    const key = await importPKCS8(this.options.privateKey.replace(/\\n/g, "\n"), "RS256");

    const assertion = await new SignJWT({
      scope: "https://www.googleapis.com/auth/firebase.messaging",
    })
      .setProtectedHeader({ alg: "RS256" })
      .setIssuer(this.options.clientEmail)
      .setSubject(this.options.clientEmail)
      .setAudience(tokenUrl)
      .setIssuedAt()
      .setExpirationTime("1h")
      .sign(key);

    const res = await fetch(tokenUrl, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion,
      }),
    });

    if (!res.ok) throw new Error(`fcm token exchange failed: ${res.status} ${await res.text()}`);

    const json = (await res.json()) as { access_token: string; expires_in: number };
    this.accessToken = json.access_token;
    this.accessTokenExpiresAt = Date.now() + json.expires_in * 1000;
    return this.accessToken;
  }

  async send(message: PushMessage): Promise<PushOutcome> {
    let accessToken: string;
    try {
      accessToken = await this.getAccessToken();
    } catch (err) {
      return { status: "failed", reason: String(err) };
    }

    const baseUrl = this.options.baseUrl ?? "https://fcm.googleapis.com";
    const url = `${baseUrl}/v1/projects/${this.options.projectId}/messages:send`;

    const res = await fetch(url, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify({
        message: {
          token: message.token,
          notification: { title: message.title, body: message.body },
          data: message.data,
          android: {
            // High priority is what gets through Doze. Without it, a phone that
            // has been idle in a pocket simply does not ring — and the target
            // market runs aggressive battery managers on top of that.
            priority: "HIGH",
            ...(message.collapseKey ? { collapse_key: message.collapseKey } : {}),
            notification: { default_sound: true },
          },
        },
      }),
    });

    if (res.ok) return { status: "sent" };

    const text = await res.text();

    // 404 UNREGISTERED and 400 INVALID_ARGUMENT on the token both mean the
    // token is gone for good. Everything else is worth retrying.
    if (res.status === 404 || text.includes("UNREGISTERED") || text.includes("InvalidRegistration")) {
      return { status: "unregistered", reason: text.slice(0, 200) };
    }

    return { status: "failed", reason: `${res.status} ${text.slice(0, 200)}` };
  }
}

// ---------------------------------------------------------------------------
// APNs (iOS)
// ---------------------------------------------------------------------------

export interface ApnsOptions {
  /** Apple Developer team id. */
  teamId: string;
  /** Key id of the .p8 signing key. */
  keyId: string;
  /** PEM contents of the .p8 key. */
  privateKey: string;
  /** App bundle id, sent as apns-topic. */
  bundleId: string;
  /** Sandbox for development builds; production for TestFlight and the store. */
  environment?: "production" | "sandbox";
}

/**
 * Apple Push Notification service, HTTP/2 with token-based auth.
 *
 * APNs requires HTTP/2, which `fetch` will not do, so this uses node:http2
 * directly. Auth is an ES256 JWT — Apple accepts no other algorithm — that
 * stays valid for an hour and must be refreshed at least every hour or Apple
 * starts rejecting with ExpiredProviderToken.
 */
export class ApnsPushProvider implements PushProvider {
  readonly name = "apns";

  private jwt: string | null = null;
  private jwtIssuedAt = 0;
  private session: ReturnType<typeof connectHttp2> | null = null;

  constructor(private readonly options: ApnsOptions) {}

  private get host(): string {
    return this.options.environment === "sandbox"
      ? "https://api.sandbox.push.apple.com"
      : "https://api.push.apple.com";
  }

  private async getJwt(): Promise<string> {
    // Apple rejects tokens older than an hour; refresh at 50 minutes.
    if (this.jwt && Date.now() - this.jwtIssuedAt < 50 * 60_000) return this.jwt;

    const key = await importPKCS8(this.options.privateKey.replace(/\\n/g, "\n"), "ES256");

    this.jwt = await new SignJWT({})
      .setProtectedHeader({ alg: "ES256", kid: this.options.keyId })
      .setIssuer(this.options.teamId)
      .setIssuedAt()
      .sign(key);

    this.jwtIssuedAt = Date.now();
    return this.jwt;
  }

  private getSession() {
    // One HTTP/2 connection, reused. Apple explicitly asks providers not to
    // open a connection per notification.
    if (this.session && !this.session.closed && !this.session.destroyed) return this.session;
    this.session = connectHttp2(this.host);
    this.session.on("error", () => {
      this.session = null;
    });
    return this.session;
  }

  async send(message: PushMessage): Promise<PushOutcome> {
    let jwt: string;
    try {
      jwt = await this.getJwt();
    } catch (err) {
      return { status: "failed", reason: String(err) };
    }

    const payload = JSON.stringify({
      aps: {
        alert: { title: message.title, body: message.body },
        sound: "default",
        ...(message.badge !== undefined ? { badge: message.badge } : {}),
        // Lets a Notification Service Extension replace the generic body with
        // the real text after fetching it — the whole point of not putting
        // content in the payload.
        "mutable-content": 1,
      },
      ...message.data,
    });

    return new Promise<PushOutcome>((resolve) => {
      const session = this.getSession();

      const req = session.request({
        [http2.HTTP2_HEADER_METHOD]: "POST",
        [http2.HTTP2_HEADER_PATH]: `/3/device/${message.token}`,
        authorization: `bearer ${jwt}`,
        "apns-topic": this.options.bundleId,
        "apns-push-type": "alert",
        "apns-priority": "10",
        ...(message.collapseKey ? { "apns-collapse-id": message.collapseKey } : {}),
        "content-type": "application/json",
        "content-length": Buffer.byteLength(payload),
      });

      let status = 0;
      let body = "";

      req.on("response", (headers) => {
        status = Number(headers[http2.HTTP2_HEADER_STATUS] ?? 0);
      });
      req.setEncoding("utf8");
      req.on("data", (chunk) => (body += chunk));

      req.on("end", () => {
        if (status === 200) return resolve({ status: "sent" });
        // 410 Gone, and 400 BadDeviceToken, both mean retire it.
        if (status === 410 || body.includes("BadDeviceToken") || body.includes("Unregistered")) {
          return resolve({ status: "unregistered", reason: body.slice(0, 200) });
        }
        resolve({ status: "failed", reason: `${status} ${body.slice(0, 200)}` });
      });

      req.on("error", (err) => resolve({ status: "failed", reason: String(err) }));

      req.end(payload);
    });
  }

  async close(): Promise<void> {
    this.session?.close();
    this.session = null;
  }
}

/** Routes to whichever provider a device is registered with. */
export class PushRouter implements PushProvider {
  readonly name = "router";

  constructor(private readonly providers: Partial<Record<"fcm" | "apns", PushProvider>>) {}

  async sendVia(provider: "fcm" | "apns", message: PushMessage): Promise<PushOutcome> {
    const target = this.providers[provider];
    if (!target) return { status: "failed", reason: `no ${provider} provider configured` };
    return target.send(message);
  }

  async send(): Promise<PushOutcome> {
    return { status: "failed", reason: "use sendVia" };
  }

  async close(): Promise<void> {
    await Promise.allSettled(Object.values(this.providers).map((p) => p?.close?.()));
  }
}
