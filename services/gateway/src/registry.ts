import type { WebSocket } from "ws";
import { encodeFrame, type ServerFrame } from "@sakina/protocol";

export interface Connection {
  socket: WebSocket;
  userId: string;
  deviceId: string;
  /** Heartbeat flag — cleared on each ping sweep, set again by the pong handler. */
  alive: boolean;
  sendCount: number;
  windowStartedAt: number;
}

/**
 * Connections held by this process, keyed user -> device -> connection.
 *
 * Keyed by device rather than by user because one account is expected on
 * several installs at once, and delivery has to address them individually: the
 * device that sent a message gets an ack, its siblings get the message itself.
 */
export class ConnectionRegistry {
  private readonly byUser = new Map<string, Map<string, Connection>>();

  add(conn: Connection): Connection | undefined {
    const devices = this.byUser.get(conn.userId) ?? new Map<string, Connection>();
    // A reconnect from the same device replaces the old socket; the caller
    // closes the stale one so we do not leak half-dead connections.
    const previous = devices.get(conn.deviceId);
    devices.set(conn.deviceId, conn);
    this.byUser.set(conn.userId, devices);
    return previous;
  }

  remove(conn: Connection): void {
    const devices = this.byUser.get(conn.userId);
    if (!devices) return;
    // Only remove if it is still the current connection for that device —
    // a slow close from a replaced socket must not evict its replacement.
    if (devices.get(conn.deviceId) === conn) devices.delete(conn.deviceId);
    if (devices.size === 0) this.byUser.delete(conn.userId);
  }

  get(userId: string): Connection[] {
    const devices = this.byUser.get(userId);
    return devices ? [...devices.values()] : [];
  }

  all(): Connection[] {
    return [...this.byUser.values()].flatMap((devices) => [...devices.values()]);
  }

  get size(): number {
    return this.all().length;
  }

  deliver(userIds: string[], frame: ServerFrame, excludeDeviceId?: string): number {
    const encoded = encodeFrame(frame);
    let delivered = 0;

    for (const userId of userIds) {
      for (const conn of this.get(userId)) {
        if (excludeDeviceId && conn.deviceId === excludeDeviceId) continue;
        if (conn.socket.readyState !== conn.socket.OPEN) continue;
        conn.socket.send(encoded);
        delivered += 1;
      }
    }

    return delivered;
  }
}

export function sendFrame(socket: WebSocket, frame: ServerFrame): void {
  if (socket.readyState === socket.OPEN) socket.send(encodeFrame(frame));
}
