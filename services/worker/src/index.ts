import { loadEnv } from "./env.js";
import { startWorker } from "./worker.js";

const env = loadEnv();
const worker = await startWorker(env);

for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.on(signal, () => {
    void worker.close().then(() => process.exit(0));
  });
}
