import { z } from "zod";

const Env = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  GATEWAY_PORT: z.coerce.number().int().positive().default(4001),
  GATEWAY_HOST: z.string().default("0.0.0.0"),
  DATABASE_URL: z.string().default("postgres://sakina:sakina@localhost:5432/sakina"),
  REDIS_URL: z.string().default("redis://localhost:6379"),
  JWT_SECRET: z.string().min(16).default("dev-only-secret-change-me-please"),
  /** Sends allowed per connection per window. Cheap insurance against a runaway client. */
  SEND_RATE_LIMIT: z.coerce.number().int().positive().default(30),
  SEND_RATE_WINDOW_MS: z.coerce.number().int().positive().default(10_000),
});

export type Env = z.infer<typeof Env>;

export function loadEnv(source: NodeJS.ProcessEnv = process.env): Env {
  const parsed = Env.safeParse(source);
  if (!parsed.success) {
    console.error("invalid environment:", parsed.error.flatten().fieldErrors);
    process.exit(1);
  }
  if (parsed.data.NODE_ENV === "production" && parsed.data.JWT_SECRET.startsWith("dev-only")) {
    throw new Error("JWT_SECRET must be set in production");
  }
  return parsed.data;
}
