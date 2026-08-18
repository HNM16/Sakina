import { DEFAULT_LOCALE } from "@sakina/protocol";

/**
 * Verification-code delivery over email.
 *
 * Email is the identity that works right now, from anywhere, with no operator
 * relationship and no Tajik SIM. It is a stopgap with a real cost — email is a
 * weaker identity than a phone number and invites the duplicate-account problem
 * that identity.ts and signup.ts exist to contain — but it unblocks building
 * and a closed beta today.
 *
 * Deliverability is the thing that will actually bite. A code that lands in
 * spam is a user who cannot sign in, and Gmail/Yandex/Mail.ru are unforgiving
 * of new sending domains. Before any real beta: set up SPF, DKIM and DMARC on
 * the sending domain, warm it slowly, and send verification mail from a
 * different subdomain than anything marketing ever touches.
 */
export interface EmailProvider {
  readonly name: string;
  sendOtp(to: string, code: string, locale?: string): Promise<void>;
}

export class EmailDeliveryError extends Error {
  constructor(
    message: string,
    readonly provider: string,
  ) {
    super(message);
    this.name = "EmailDeliveryError";
  }
}

/** Development only. The API returns the code to the caller instead. */
export class ConsoleEmailProvider implements EmailProvider {
  readonly name = "console";

  async sendOtp(to: string, code: string): Promise<void> {
    console.log(`[email:console] code ${code} for ${to} (not sent)`);
  }
}

interface OtpCopy {
  subject: string;
  body: (code: string) => string;
}

/** Russian first, then Tajik, then English — the same order as the app. */
const COPY: Record<string, OtpCopy> = {
  ru: {
    subject: "Код входа в Сакина",
    body: (code) =>
      `Ваш код подтверждения: ${code}\n\nКод действителен 10 минут.\nЕсли вы его не запрашивали, просто проигнорируйте это письмо.`,
  },
  tg: {
    subject: "Рамзи вуруд ба Сакина",
    body: (code) =>
      `Рамзи тасдиқи шумо: ${code}\n\nИн рамз 10 дақиқа эътибор дорад.\nАгар шумо онро дархост накарда бошед, ин номаро нодида гиред.`,
  },
  en: {
    subject: "Your Sakina sign-in code",
    body: (code) =>
      `Your verification code is ${code}\n\nIt expires in 10 minutes.\nIf you did not request it, you can ignore this email.`,
  },
};

function copyFor(locale: string | undefined): OtpCopy {
  return COPY[locale ?? DEFAULT_LOCALE] ?? COPY.ru!;
}

export interface ResendOptions {
  apiKey: string;
  from: string;
  baseUrl?: string;
}

/**
 * Resend. Chosen as the first real implementation because it is an HTTP call
 * rather than an SMTP conversation, which keeps this dependency-free.
 * Postmark, SES and Mailgun all take the same shape.
 */
export class ResendEmailProvider implements EmailProvider {
  readonly name = "resend";

  constructor(private readonly options: ResendOptions) {}

  async sendOtp(to: string, code: string, locale?: string): Promise<void> {
    const copy = copyFor(locale);
    const baseUrl = this.options.baseUrl ?? "https://api.resend.com";

    const response = await fetch(`${baseUrl}/emails`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${this.options.apiKey}`,
      },
      body: JSON.stringify({
        from: this.options.from,
        to: [to],
        subject: copy.subject,
        text: copy.body(code),
      }),
    });

    if (!response.ok) {
      throw new EmailDeliveryError(
        `resend returned ${response.status}: ${await response.text()}`,
        this.name,
      );
    }
  }
}

export interface SmtpishOptions {
  /** Endpoint accepting `{ to, subject, text }`. */
  url: string;
  authorization?: string | undefined;
  from?: string | undefined;
}

/** Generic JSON-over-HTTP sender, for whatever provider ends up being cheapest. */
export class HttpEmailProvider implements EmailProvider {
  readonly name = "http";

  constructor(private readonly options: SmtpishOptions) {}

  async sendOtp(to: string, code: string, locale?: string): Promise<void> {
    const copy = copyFor(locale);

    const response = await fetch(this.options.url, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        ...(this.options.authorization ? { authorization: this.options.authorization } : {}),
      },
      body: JSON.stringify({
        to,
        subject: copy.subject,
        text: copy.body(code),
        ...(this.options.from ? { from: this.options.from } : {}),
      }),
    });

    if (!response.ok) {
      throw new EmailDeliveryError(`email endpoint returned ${response.status}`, this.name);
    }
  }
}
