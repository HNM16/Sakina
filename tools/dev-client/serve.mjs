#!/usr/bin/env node
/**
 * Serves tools/dev-client on :4002. No dependencies, no build step.
 *
 * It exists because `file://` pages get a null origin, which makes CORS and
 * WebSocket behaviour differ from anything real. Serving over http keeps the
 * dev client honest about what a browser will actually do.
 */
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const port = Number(process.env.DEV_CLIENT_PORT ?? 4002);

createServer(async (req, res) => {
  try {
    const html = await readFile(join(here, "index.html"));
    res.writeHead(200, {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "no-store",
    });
    res.end(html);
  } catch (err) {
    res.writeHead(500).end(String(err));
  }
}).listen(port, "0.0.0.0", () => {
  console.log(`dev client:  http://localhost:${port}`);
  console.log("open it in two tabs, sign in with two different emails");
});
