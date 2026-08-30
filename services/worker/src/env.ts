import { z } from "zod";

const Env = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  WORKER_PORT: z.coerce.number().int().positive().default(4003),
  WORKER_HOST: z.string().default("0.0.0.0"),
  DATABASE_URL: z.string().default("postgres://sakina:sakina@localhost:5432/sakina"),
  REDIS_URL: z.string().default("redis://localhost:6379"),

  /**
   * `console` records pushes instead of sending them, which is what makes the
   * whole path testable without a Firebase project, an Apple developer account
   * or a physical handset.
   */
  PUSH_PROVIDER: z.enum(["console", "real"]).default("console"),

  // FCM (Android). The legacy server-key API was shut down in 2024, so this is
  // a service account and nothing else will do.
  FCM_PROJECT_ID: z.string().optional(),
  FCM_CLIENT_EMAIL: z.string().optional(),
  FCM_PRIVATE_KEY: z.string().optional(),

  // APNs (iOS). Token-based auth with a .p8 key.
  APNS_TEAM_ID: z.string().optional(),
  APNS_KEY_ID: z.string().optional(),
  APNS_PRIVATE_KEY: z.string().optional(),
  APNS_BUNDLE_ID: z.string().default("tj.sakina.app"),
  APNS_ENVIRONMENT: z.enum(["production", "sandbox"]).default("sandbox"),

  /** Exposes recently sent pushes at /dev/pushes. Never enabled in production. */
  PUSH_DEV_INSPECT: z
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
    if (parsed.data.PUSH_PROVIDER === "console") {
      throw new Error("PUSH_PROVIDER must be 'real' in production");
    }
    if (parsed.data.PUSH_DEV_INSPECT) {
      throw new Error("PUSH_DEV_INSPECT must be false in production");
    }
  }

  if (parsed.data.PUSH_PROVIDER === "real") {
    const hasFcm = parsed.data.FCM_PROJECT_ID && parsed.data.FCM_CLIENT_EMAIL && parsed.data.FCM_PRIVATE_KEY;
    const hasApns = parsed.data.APNS_TEAM_ID && parsed.data.APNS_KEY_ID && parsed.data.APNS_PRIVATE_KEY;
    if (!hasFcm && !hasApns) {
      throw new Error("PUSH_PROVIDER=real needs FCM_* or APNS_* credentials");
    }
  }

  return parsed.data;
}
