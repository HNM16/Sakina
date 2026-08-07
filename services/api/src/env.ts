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
  }

  return parsed.data;
}
