#!/usr/bin/env node
/**
 * Fills a local backend with enough to look at.
 *
 *   pnpm seed:demo
 *
 * Three users, three chats and a handful of Tajik messages, created through
 * the real HTTP API and the real websocket gateway — not inserted into
 * Postgres behind their backs, so what comes out is shaped exactly like
 * production data. It prints an address and a code you can sign in with.
 *
 * Written for looking at the Flutter client with actual content in it. An
 * empty chat list tells you nothing about whether a chat list works.
 *
 * Needs the stack up: postgres, redis, `pnpm db:migrate`, and the api and
 * gateway running with OTP_DEV_MODE=true.
 */
import WebSocket from 'ws';
import { randomUUID } from 'node:crypto';
const API = 'http://127.0.0.1:4000', WS = 'ws://127.0.0.1:4001/ws';

const j = async (m, p, body, tok) => {
  const r = await fetch(API + p, {
    method: m,
    headers: { 'content-type': 'application/json', ...(tok ? { authorization: `Bearer ${tok}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const t = await r.text();
  if (!r.ok) throw new Error(`${m} ${p} -> ${r.status} ${t}`);
  return t ? JSON.parse(t) : {};
};

async function signIn(email, name) {
  const deviceId = randomUUID();
  const { dev_code } = await j('POST', '/v1/auth/otp/request', { identity: { kind: 'email', value: email }, locale: 'ru' });
  const res = await j('POST', '/v1/auth/otp/verify', {
    identity: { kind: 'email', value: email }, code: dev_code,
    device: { device_id: deviceId, platform: 'android', name },
  });
  return { id: res.user.id, token: res.tokens.access_token, deviceId, code: dev_code, email };
}

function connect(session) {
  const socket = new WebSocket(WS);
  const send = (f) => socket.send(JSON.stringify(f));
  return new Promise((resolve, reject) => {
    socket.on('error', reject);
    socket.on('message', (raw) => {
      const f = JSON.parse(raw.toString());
      if (f.t === 'ready') resolve({ socket, send });
    });
    socket.on('open', () => send({ t: 'hello', d: { v: 1, token: session.token, device_id: session.deviceId } }));
  });
}

const a = await signIn(`nekruz${Date.now() % 100000}@sakina.tj`, 'Nekruz phone');
const b = await signIn(`nozanin${Date.now() % 100000}@sakina.tj`, 'Nozanin phone');
const c = await signIn(`daler${Date.now() % 100000}@sakina.tj`, 'Daler phone');
console.log('users ok');

const chatB = await j('POST', '/v1/chats', { kind: 'direct', peer_id: b.id }, a.token);
const chatC = await j('POST', '/v1/chats', { kind: 'direct', peer_id: c.id }, a.token);
const group = await j('POST', '/v1/chats', { kind: 'group', title: 'Оила', member_ids: [b.id, c.id] }, a.token);
console.log('chats ok');

const sockA = await connect(a), sockB = await connect(b), sockC = await connect(c);
const say = (sock, chatId, text) =>
  new Promise((res) => {
    sock.send({ t: 'send', d: { client_id: randomUUID(), chat_id: chatId, payload: { type: 'text', text } } });
    setTimeout(res, 320);
  });

await say(sockB, chatB.id, 'Салом! Ту дар кучоӣ?');
await say(sockA, chatB.id, 'Дар роҳам, бист дақиқа');
await say(sockB, chatB.id, 'Ба хона кай меоӣ? Кӯдакон пурсиданд.');
await say(sockA, chatB.id, 'Соати ҳашт мешавад');
await say(sockC, chatC.id, 'Пулро гирифтам, раҳмати калон');
await say(sockC, group.id, 'Расмҳои тӯйро фиристодам');
await say(sockB, group.id, 'Ташаккур! Хеле зебо шудаанд');
console.log('messages ok');

for (const s of [sockA, sockB, sockC]) s.socket.close();
console.log(JSON.stringify({ signInAs: a.email, devCode: a.code }, null, 2));
process.exit(0);
