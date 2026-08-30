import { z } from "zod";

const Env = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  API_PORT: z.coerce.number().int().positive().default(4000),
  API_HOST: z.string().default("0.0.0.0"),
  DATABASE_URL: z.string().default("postgres://sakina:sakina@localhost:5432/sakina"),
  JWT_SECRET: z.string().min(16).default("dev-only-secret-change-me-please"),
  OTP_PEPPER: z.string().min(16).default("dev-only-pepper-change-me-please"),
  /** When true the API returns the OTP in the response so you can log in without SMS. */
  OTP_DEV_MODE: z
    .string()
    .default("true")
    .transform((v) => v === "true"),
  CORS_ORIGIN: z.string().default("*"),
  /**
   * Used only to publish chat changes onto the gateway's fan-out channel, so
   * that being added to a group shows up on an already-connected phone. The API
   * never subscribes.
   */
  REDIS_URL: z.string().default("redis://localhost:6379"),

  EMAIL_PROVIDER: z.enum(["console", "resend", "http"]).default("console"),
  RESEND_API_KEY: z.string().optional(),
  EMAIL_FROM: z.string().default("Sakina <no-reply@sakina.tj>"),
  EMAIL_HTTP_URL: z.string().optional(),
  EMAIL_HTTP_AUTHORIZATION: z.string().optional(),

  /** Comma-separated extra disposable domains, on top of the built-in list. */
  DISPOSABLE_EMAIL_DOMAINS: z.string().default(""),
  /** When set, ONLY these domains may register. Empty means any domain. */
  ALLOWED_EMAIL_DOMAINS: z.string().default(""),

  /** Invite-only is the strongest anti-abuse lever and the growth loop. */
  REQUIRE_INVITE: z
    .string()
    .default("false")
    .transform((v) => v === "true"),
  INVITES_PER_USER: z.coerce.number().int().nonnegative().default(5),
  MAX_SIGNUPS_PER_DEVICE: z.coerce.number().int().positive().default(3),
  MAX_SIGNUPS_PER_IP: z.coerce.number().int().positive().default(20),
  SIGNUP_WINDOW_HOURS: z.coerce.number().int().positive().default(24),
  /** Seconds between code requests for one identity. 0 disables, for tests only. */
  OTP_RESEND_COOLDOWN_SECONDS: z.coerce.number().int().nonnegative().default(60),

  SMS_PROVIDER: z.enum(["stub", "telegram", "http"]).default("stub"),
  TELEGRAM_GATEWAY_TOKEN: z.string().optional(),
  TELEGRAM_GATEWAY_SENDER: z.string().optional(),
  SMS_HTTP_URL: z.string().optional(),
  SMS_HTTP_AUTHORIZATION: z.string().optional(),
  SMS_HTTP_SENDER_ID: z.string().optional(),

  /**
   * Reserved identity/code pairs that skip delivery, in every environment.
   * Format: "qa@sakina.tj:000000,+992000000001:111111".
   *
   * Kept out of dev-mode gating on purpose: App Store and Play reviewers cannot
   * receive a Tajik SMS, so production needs at least one working pair or the
   * app gets rejected for an un-signin-able account.
   */
  TEST_IDENTITIES: z.string().default(""),

  // -------------------------------------------------------------------------
  // Media storage
  // -------------------------------------------------------------------------
  /**
   * `local` writes to disk and serves through this API with a signed URL. It
   * needs no infrastructure, which is what makes the whole upload path testable
   * on a laptop — the same reason PUSH_PROVIDER has a console mode.
   * `s3` is MinIO in production.
   */
  STORAGE_PROVIDER: z.enum(["local", "s3"]).default("local"),
  STORAGE_LOCAL_DIR: z.string().default(".data/media"),
  /** Absolute base for signed media URLs. Must be reachable by the phone, not by the server. */
  STORAGE_PUBLIC_BASE: z.string().default("http://127.0.0.1:4000"),
  S3_ENDPOINT: z.string().default("http://127.0.0.1:9000"),
  S3_REGION: z.string().default("us-east-1"),
  S3_BUCKET: z.string().default("sakina-media"),
  S3_ACCESS_KEY_ID: z.string().optional(),
  S3_SECRET_ACCESS_KEY: z.string().optional(),
  S3_FORCE_PATH_STYLE: z
    .string()
    .default("true")
    .transform((v) => v === "true"),
});

export type Env = z.infer<typeof Env>;

export function loadEnv(source: NodeJS.ProcessEnv = process.env): Env {
  const parsed = Env.safeParse(source);
  if (!parsed.success) {
    console.error("invalid environment:", parsed.error.flatten().fieldErrors);
    process.exit(1);
  }

  if (parsed.data.NODE_ENV === "production") {
    if (parsed.data.OTP_DEV_MODE) {
      throw new Error("OTP_DEV_MODE must be false in production");
    }
    if (parsed.data.JWT_SECRET.startsWith("dev-only")) {
      throw new Error("JWT_SECRET must be set in production");
    }
    if (parsed.data.OTP_PEPPER.startsWith("dev-only")) {
      throw new Error("OTP_PEPPER must be set in production");
    }
    if (parsed.data.EMAIL_PROVIDER === "console") {
      throw new Error("EMAIL_PROVIDER must not be 'console' in production");
    }
  }

  if (parsed.data.SMS_PROVIDER === "telegram" && !parsed.data.TELEGRAM_GATEWAY_TOKEN) {
    throw new Error("TELEGRAM_GATEWAY_TOKEN is required when SMS_PROVIDER=telegram");
  }
  if (parsed.data.SMS_PROVIDER === "http" && !parsed.data.SMS_HTTP_URL) {
    throw new Error("SMS_HTTP_URL is required when SMS_PROVIDER=http");
  }
  if (parsed.data.EMAIL_PROVIDER === "resend" && !parsed.data.RESEND_API_KEY) {
    throw new Error("RESEND_API_KEY is required when EMAIL_PROVIDER=resend");
  }
  if (parsed.data.EMAIL_PROVIDER === "http" && !parsed.data.EMAIL_HTTP_URL) {
    throw new Error("EMAIL_HTTP_URL is required when EMAIL_PROVIDER=http");
  }

  return parsed.data;
}
