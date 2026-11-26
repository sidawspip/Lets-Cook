type RoomEvent = {type?: string; roomId?: string; senderId?: string; senderName?: string; body?: string};

class NotificationStream {
  private socket: WebSocket | null = null;
  private retry: ReturnType<typeof setTimeout> | null = null;
  private enabled = false;
  private pending = '';
  onEvent: (event: RoomEvent) => void = () => {};

  connect() {
    this.enabled = true;
    if (this.socket && this.socket.readyState <= WebSocket.OPEN) return;
    const token = localStorage.getItem('access_token');
    if (!token) return;
    const base = new URL(import.meta.env.VITE_API_BASE || 'https://xynk.in/api', window.location.origin);
    const socket = new WebSocket(`${base.protocol === 'https:' ? 'wss:' : 'ws:'}//${base.host}/ws`);
    this.socket = socket;
    socket.onopen = () => socket.send(`CONNECT\naccept-version:1.2\nheart-beat:0,0\nAuthorization:Bearer ${token}\n\n\0`);
    socket.onmessage = message => {
      this.pending += String(message.data);
      let end: number;
      while ((end = this.pending.indexOf('\0')) >= 0) {
        const frame = this.pending.slice(0, end).trim();
        this.pending = this.pending.slice(end + 1);
        if (frame.startsWith('CONNECTED')) socket.send('SUBSCRIBE\nid:xynk-notifications\ndestination:/user/queue/notifications\nack:auto\n\n\0');
        if (frame.startsWith('MESSAGE')) {
          const body = frame.split('\n\n').slice(1).join('\n\n');
          try { this.onEvent(JSON.parse(body) as RoomEvent); } catch { /* Ignore malformed events. */ }
        }
      }
    };
    socket.onclose = () => { if (this.socket === socket) this.socket = null; if (this.enabled) this.retry = setTimeout(() => this.connect(), 2000); };
    socket.onerror = () => socket.close();
  }
  disconnect() {
    this.enabled = false;
    if (this.retry) clearTimeout(this.retry);
    this.retry = null;
    this.socket?.close();
    this.socket = null;
    this.pending = '';
  }
}

export const notifications = new NotificationStream();
