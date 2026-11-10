import { loadEnv } from "./env.js";
import { startGateway } from "./server.js";

const env = loadEnv();
const gateway = await startGateway(env);

for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.on(signal, () => {
    void gateway.close().then(() => process.exit(0));
  });
}
