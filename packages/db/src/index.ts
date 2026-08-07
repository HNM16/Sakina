import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import * as schema from "./schema.js";

export * from "./schema.js";
export { schema };

export type Database = ReturnType<typeof createDb>["db"];
export type Sql = ReturnType<typeof postgres>;

export function createDb(url: string, options: { max?: number } = {}) {
  const sql = postgres(url, {
    max: options.max ?? 10,
    // Postgres timestamps come back as Date; we convert to epoch ms at the edge.
    transform: { undefined: null },
  });
  const db = drizzle(sql, { schema });
  return { db, sql };
}
