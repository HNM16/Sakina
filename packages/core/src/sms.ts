/**
 * Verification-code delivery.
 *
 * OTP delivery to +992 is a procurement problem before it is a code problem, so
 * this is an interface with several implementations rather than one hard-wired
 * vendor. Pick with `SMS_PROVIDER`.
 *
 * The routes, roughly in the order a project like this needs them:
 *
 *  1. `stub`    — nothing is sent; the API returns the code in the response.
 *                 Local development only.
 *  2. Reserved test numbers (see `parseTestNumbers` in otp.ts) — fixed pairs
 *                 that bypass delivery in every environment, including
 *                 production. Required for App Store review; also how you sign
 *                 in while nowhere near a Tajik SIM.
 *  3. `telegram` — Telegram's Gateway API, ~$0.01 per delivered code against
 *                 roughly $0.05–0.10 for international SMS to Tajikistan. Works
 *                 from anywhere today, needs no operator relationship, and codes
 *                 to your own number are free. Its one real limitation is also
 *                 an argument for it here: it only reaches people who already
 *                 have Telegram, which in this market is most of them.
 *  4. An international aggregator — fine for a beta of a few hundred, and
 *                 priced out of a free messenger's signup funnel at scale.
 *  5. `Tcell` / `Megafon Tajikistan` / `Babilon-M` / `ZET-Mobile` direct, at
 *                 launch. Cheapest and most reliable, and the only one that
 *                 needs a contract negotiated on the ground. Plan flash-call
 *                 verification here too — a dropped call whose last digits are
 *                 the code, far cheaper than SMS and already familiar regionally.
 */
export interface SmsProvider {
  readonly name: string;
  sendOtp(phone: string, code: string): Promise<void>;
}

/** Development only. The API hands the code back to the caller instead. */
export class StubSmsProvider implements SmsProvider {
  readonly name = "stub";

  async sendOtp(phone: string, code: string): Promise<void> {
    console.log(`[sms:stub] code ${code} for ${phone} (not sent)`);
  }
}

export class SmsDeliveryError extends Error {
  constructor(
    message: string,
    readonly provider: string,
  ) {
    super(message);
    this.name = "SmsDeliveryError";
  }
}

export interface TelegramGatewayOptions {
  token: string;
  /** Shown as the sender. Must be a username the Gateway account controls. */
  senderUsername?: string | undefined;
  /** Seconds before an undelivered message is abandoned; the fee is refunded. */
  ttlSeconds?: number;
  baseUrl?: string;
}

/**
 * Telegram Gateway API.
 *
 * NOTE: verify the field names against https://core.telegram.org/gateway/api
 * before putting real money behind this — the shape below could not be fetched
 * from the build environment and is written from documentation, not from a live
 * call. The surrounding logic (own code, own hashing, our OTP table) does not
 * depend on Telegram's own verification flow, so a mismatch surfaces as a clean
 * delivery failure rather than a broken login.
 */
export class TelegramGatewaySmsProvider implements SmsProvider {
  readonly name = "telegram";

  constructor(private readonly options: TelegramGatewayOptions) {}

  async sendOtp(phone: string, code: string): Promise<void> {
    const baseUrl = this.options.baseUrl ?? "https://gatewayapi.telegram.org";

    const response = await fetch(`${baseUrl}/sendVerificationMessage`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${this.options.token}`,
      },
      body: JSON.stringify({
        phone_number: phone,
        // Sakina generates and hashes its own code; Telegram is a transport
        // here, not the source of truth for verification.
        code,
        ttl: this.options.ttlSeconds ?? 300,
        ...(this.options.senderUsername
          ? { sender_username: this.options.senderUsername }
          : {}),
      }),
    });

    const body = (await response.json()) as { ok?: boolean; error?: string };

    if (!response.ok || body.ok !== true) {
      throw new SmsDeliveryError(
        body.error ?? `gateway returned ${response.status}`,
        this.name,
      );
    }
  }
}

export interface HttpSmsProviderOptions {
  /** Endpoint that accepts a JSON POST of `{ to, text }`. */
  url: string;
  /** Sent as `Authorization` verbatim, e.g. "Bearer …" or "Basic …". */
  authorization?: string | undefined;
  senderId?: string | undefined;
  /** `{code}` is substituted. Keep it short — operators bill per segment. */
  template?: string;
}

/**
 * A generic JSON-over-HTTP sender, which is what most regional aggregators and
 * Tajik operator gateways actually expose. Adapting one usually means setting a
 * URL and a header rather than writing a new class.
 */
export class HttpSmsProvider implements SmsProvider {
  readonly name = "http";

  constructor(private readonly options: HttpSmsProviderOptions) {}

  async sendOtp(phone: string, code: string): Promise<void> {
    const template = this.options.template ?? "Sakina: {code}";

    const response = await fetch(this.options.url, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        ...(this.options.authorization
          ? { authorization: this.options.authorization }
          : {}),
      },
      body: JSON.stringify({
        to: phone,
        text: template.replace("{code}", code),
        ...(this.options.senderId ? { from: this.options.senderId } : {}),
      }),
    });

    if (!response.ok) {
      throw new SmsDeliveryError(
        `sms endpoint returned ${response.status}`,
        this.name,
      );
    }
  }
}
