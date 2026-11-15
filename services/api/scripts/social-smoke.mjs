#!/usr/bin/env node
/**
 * Groups, channels and attachments — the parts that are easy to get subtly
 * wrong and impossible to notice until someone posts in a channel they should
 * not be able to post in.
 *
 *   node services/api/scripts/social-smoke.mjs
 *
 * Needs api :4000 with STORAGE_PROVIDER=local. Postgres and Redis up.
 *
 * The questions that matter:
 *   - can a subscriber post in a channel? (they must not, at every entry point)
 *   - does removing someone actually stop them reading?
 *   - can a member of chat A fetch chat B's photo with a stolen key?
 *   - does the mime allowlist hold, and does the size limit hold?
 *   - does a full upload round trip return the same bytes?
 */
import { randomUUID } from "node:crypto";

const API = process.env.API_URL ?? "http://127.0.0.1:4000";

let failures = 0;
function check(label, condition, detail = "") {
  if (!condition) failures += 1;
  console.log(`  ${condition ? "✓" : "✗"} ${label}${detail ? ` — ${detail}` : ""}`);
}

async function raw(path, options = {}) {
  const res = await fetch(`${API}${path}`, {
    ...options,
    headers: {
      ...(options.body && !options.rawBody ? { "content-type": "application/json" } : {}),
      ...(options.headers ?? {}),
    },
  });
  const text = res.headers.get("content-type")?.includes("json") ? await res.text() : null;
  return { status: res.status, body: text ? JSON.parse(text) : null, res };
}

async function api(path, options = {}) {
  const { status, body } = await raw(path, options);
  if (status >= 400) {
    throw new Error(`${path} -> ${status} ${JSON.stringify(body)}`);
  }
  return body;
}

const auth = (session) => ({ authorization: `Bearer ${session.tokens.access_token}` });

async function register(email) {
  const deviceId = randomUUID();
  const identity = { kind: "email", value: email };
  const { dev_code } = await api("/v1/auth/otp/request", {
    method: "POST",
    body: JSON.stringify({ identity, locale: "ru" }),
  });
  const session = await api("/v1/auth/otp/verify", {
    method: "POST",
    body: JSON.stringify({
      identity,
      code: dev_code,
      device: { device_id: deviceId, platform: "android", name: "Test handset" },
    }),
  });
  return { ...session, deviceId };
}

const stamp = Date.now().toString().slice(-8);

console.log("\nSakina groups, channels and media\n");

// ---------------------------------------------------------------------------
console.log("setup");
const owner = await register(`owner${stamp}@example.com`);
const member = await register(`member${stamp}@example.com`);
const outsider = await register(`outsider${stamp}@example.com`);
check("three users registered", !!owner.user.id && !!member.user.id && !!outsider.user.id);

// ---------------------------------------------------------------------------
console.log("\ngroups");

const group = await api("/v1/chats", {
  method: "POST",
  headers: auth(owner),
  body: JSON.stringify({
    kind: "group",
    title: "Оилаи мо",
    member_ids: [member.user.id],
    description: "Гурӯҳи оилавӣ",
  }),
});
check("group created", group.kind === "group", `"${group.title}"`);
check("creator is the owner", group.role === "owner");
check("both people are members", group.member_count === 2, `count=${group.member_count}`);
check("everyone in a group may post", group.can_post === true);
check("Tajik title survived the round trip", group.title === "Оилаи мо");

const memberChats = await api("/v1/chats", { headers: auth(member) });
const asMember = memberChats.chats.find((c) => c.id === group.id);
check("the other person sees the group", !!asMember);
check("they are a plain member", asMember?.role === "member");
check("but they can still post", asMember?.can_post === true);

// A member may add someone; that is what makes it a group and not a channel.
await api(`/v1/chats/${group.id}/members`, {
  method: "POST",
  headers: auth(member),
  body: JSON.stringify({ user_ids: [outsider.user.id] }),
});
const afterAdd = await api("/v1/chats", { headers: auth(outsider) });
check("a member can add someone", afterAdd.chats.some((c) => c.id === group.id));

const members = await api(`/v1/chats/${group.id}/members`, { headers: auth(owner) });
check("member list is complete and ordered", members.total === 3, `total=${members.total}`);
check("the owner is first", members.members[0]?.role === "owner");

// Renaming is an admin action.
const renameByMember = await raw(`/v1/chats/${group.id}`, {
  method: "PATCH",
  headers: auth(outsider),
  body: JSON.stringify({ title: "Nope" }),
});
check("a plain member cannot rename the group", renameByMember.status === 403,
  `status ${renameByMember.status}`);

await api(`/v1/chats/${group.id}`, {
  method: "PATCH",
  headers: auth(owner),
  body: JSON.stringify({ title: "Оилаи калон" }),
});
const renamed = (await api("/v1/chats", { headers: auth(owner) })).chats.find(
  (c) => c.id === group.id,
);
check("the owner can rename it", renamed?.title === "Оилаи калон");

// Removing, and leaving.
await api(`/v1/chats/${group.id}/members/${outsider.user.id}`, {
  method: "DELETE",
  headers: auth(owner),
});
const removedView = await api("/v1/chats", { headers: auth(outsider) });
check("a removed member loses the chat", !removedView.chats.some((c) => c.id === group.id));

const readAfterRemoval = await raw(`/v1/chats/${group.id}/messages`, {
  method: "GET",
  headers: auth(outsider),
});
check("and cannot read its history", readAfterRemoval.status === 403,
  `status ${readAfterRemoval.status}`);

const removeOwner = await raw(`/v1/chats/${group.id}/members/${owner.user.id}`, {
  method: "DELETE",
  headers: auth(member),
});
check("a member cannot remove the owner", removeOwner.status === 403,
  `status ${removeOwner.status}`);

// ---------------------------------------------------------------------------
console.log("\nchannels");

const handle = `news_${stamp}`;
const channel = await api("/v1/chats", {
  method: "POST",
  headers: auth(owner),
  body: JSON.stringify({
    kind: "channel",
    title: "Хабарҳои Душанбе",
    username: handle,
    description: "Расмӣ",
  }),
});
check("channel created", channel.kind === "channel", `@${channel.username}`);
check("the owner may post", channel.can_post === true);
check("it starts with one member", channel.member_count === 1);

const joined = await api("/v1/chats/join", {
  method: "POST",
  headers: auth(member),
  body: JSON.stringify({ username: handle }),
});
check("anyone can join by handle", joined.id === channel.id);
check("a subscriber may NOT post", joined.can_post === false);
check("they are a plain member", joined.role === "member");

// The check that matters. A subscriber must be refused at every entry point,
// not just have the composer hidden.
const subscriberUpload = await raw("/v1/media/upload", {
  method: "POST",
  headers: auth(member),
  body: JSON.stringify({
    chat_id: channel.id,
    name: "x.jpg",
    mime: "image/jpeg",
    size: 1000,
  }),
});
check("a subscriber cannot even get an upload ticket", subscriberUpload.status === 403,
  `status ${subscriberUpload.status}`);

const takenHandle = await raw("/v1/chats", {
  method: "POST",
  headers: auth(member),
  body: JSON.stringify({ kind: "channel", title: "Copycat", username: handle }),
});
check("a handle cannot be taken twice", takenHandle.status === 409,
  `status ${takenHandle.status}`);

const badHandle = await raw("/v1/chats", {
  method: "POST",
  headers: auth(member),
  body: JSON.stringify({ kind: "channel", title: "X", username: "Хабар" }),
});
check("a Cyrillic handle is refused", badHandle.status === 400, `status ${badHandle.status}`);

// Promotion, and who may grant it.
const selfPromote = await raw(`/v1/chats/${channel.id}/role`, {
  method: "POST",
  headers: auth(member),
  body: JSON.stringify({ user_id: member.user.id, role: "admin" }),
});
check("a subscriber cannot promote themselves", selfPromote.status === 403,
  `status ${selfPromote.status}`);

await api(`/v1/chats/${channel.id}/role`, {
  method: "POST",
  headers: auth(owner),
  body: JSON.stringify({ user_id: member.user.id, role: "admin" }),
});
const promoted = (await api("/v1/chats", { headers: auth(member) })).chats.find(
  (c) => c.id === channel.id,
);
check("the owner can promote a subscriber to admin", promoted?.role === "admin");
check("and then they can post", promoted?.can_post === true);

const demoteOwner = await raw(`/v1/chats/${channel.id}/role`, {
  method: "POST",
  headers: auth(owner),
  body: JSON.stringify({ user_id: owner.user.id, role: "member" }),
});
check("the owner cannot demote themselves by accident", demoteOwner.status === 400,
  `status ${demoteOwner.status}`);

// ---------------------------------------------------------------------------
console.log("\nmedia");

const photo = Buffer.from(
  // A real 1x1 PNG, so the bytes that come back can be compared exactly.
  "89504e470d0a1a0a0000000d4948445200000001000000010802000000907753" +
    "de0000000c4944415408d763f8cfc000000301010018dd8db00000000049454e44ae426082",
  "hex",
);

const ticket = await api("/v1/media/upload", {
  method: "POST",
  headers: auth(owner),
  body: JSON.stringify({
    chat_id: group.id,
    name: "суратҳо.png",
    mime: "image/png",
    size: photo.length,
  }),
});
check("upload ticket issued", !!ticket.url && ticket.method === "PUT");
check("the server decided the kind", ticket.kind === "image", ticket.kind);
check("the key is namespaced by chat", ticket.key.startsWith(`chat/${group.id}/image/`));
check("the filename is NOT in the key", !ticket.key.includes("сурат"));

const put = await fetch(ticket.url, {
  method: "PUT",
  headers: ticket.headers,
  body: photo,
});
check("the bytes uploaded", put.status === 204, `status ${put.status}`);

const urlResponse = await api(
  `/v1/media/url?key=${encodeURIComponent(ticket.key)}&chat_id=${group.id}`,
  { headers: auth(owner) },
);
check("a download URL was issued", !!urlResponse.url);

const fetched = await fetch(urlResponse.url);
const got = Buffer.from(await fetched.arrayBuffer());
check("the same bytes came back", got.equals(photo), `${got.length} bytes`);
check("it is served as an attachment, never inline",
  (fetched.headers.get("content-disposition") ?? "").startsWith("attachment"));
check("with nosniff", fetched.headers.get("x-content-type-options") === "nosniff");

// A member of another chat must not be able to read this key.
const stolen = await raw(
  `/v1/media/url?key=${encodeURIComponent(ticket.key)}&chat_id=${channel.id}`,
  { headers: auth(owner) },
);
check("a key cannot be claimed for a different chat", stolen.status === 403,
  `status ${stolen.status}`);

const byOutsider = await raw(
  `/v1/media/url?key=${encodeURIComponent(ticket.key)}&chat_id=${group.id}`,
  { headers: auth(outsider) },
);
check("a removed member cannot fetch the chat's media", byOutsider.status === 403,
  `status ${byOutsider.status}`);

const html = await raw("/v1/media/upload", {
  method: "POST",
  headers: auth(owner),
  body: JSON.stringify({ chat_id: group.id, name: "p.html", mime: "text/html", size: 100 }),
});
check("text/html is refused outright", html.status === 400, `status ${html.status}`);

const svg = await raw("/v1/media/upload", {
  method: "POST",
  headers: auth(owner),
  body: JSON.stringify({ chat_id: group.id, name: "p.svg", mime: "image/svg+xml", size: 100 }),
});
check("so is SVG — it is a script container", svg.status === 400, `status ${svg.status}`);

const huge = await raw("/v1/media/upload", {
  method: "POST",
  headers: auth(owner),
  body: JSON.stringify({
    chat_id: group.id,
    name: "big.mp4",
    mime: "video/mp4",
    size: 512 * 1024 * 1024,
  }),
});
check("an oversized video is refused before upload", huge.status === 400,
  `status ${huge.status}`);

const exe = await api("/v1/media/upload", {
  method: "POST",
  headers: auth(owner),
  body: JSON.stringify({
    chat_id: group.id,
    name: "app.apk",
    mime: "application/vnd.android.package-archive",
    size: 5000,
  }),
});
check("an unknown type is a file, not an image", exe.kind === "file", exe.kind);

const forged = await raw("/v1/media/upload", {
  method: "POST",
  headers: auth(outsider),
  body: JSON.stringify({ chat_id: group.id, name: "x.png", mime: "image/png", size: 10 }),
});
check("a non-member cannot get an upload ticket", forged.status === 403,
  `status ${forged.status}`);

const traversal = await raw(
  `/v1/media/url?key=${encodeURIComponent("chat/../../etc/passwd")}&chat_id=${group.id}`,
  { headers: auth(owner) },
);
check("a traversal key is rejected", traversal.status === 400 || traversal.status === 403,
  `status ${traversal.status}`);

const tampered = urlResponse.url.replace(/sig=([0-9a-f]{8})/, "sig=deadbeef");
const tamperedFetch = await fetch(tampered);
check("a tampered signature is rejected", tamperedFetch.status === 403,
  `status ${tamperedFetch.status}`);

console.log(
  failures === 0 ? "\nAll checks passed.\n" : `\n${failures} check(s) failed.\n`,
);
process.exit(failures === 0 ? 0 : 1);
