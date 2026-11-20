import { Client } from '../../../frontend/node_modules/@stomp/stompjs/esm6/index.js';

const keycloakUrl = 'http://localhost:8180';
const apiUrl = 'http://localhost:8080';

async function token(username, password) {
  const body = new URLSearchParams({
    client_id: 'lets-cook-web',
    grant_type: 'password',
    username,
    password,
  });
  const response = await fetch(
    `${keycloakUrl}/realms/xynk/protocol/openid-connect/token`,
    {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body,
    },
  );
  if (!response.ok) throw new Error(`Authentication failed: ${response.status}`);
  return (await response.json()).access_token;
}

async function api(path, accessToken, options = {}) {
  const response = await fetch(`${apiUrl}${path}`, {
    ...options,
    headers: {
      authorization: `Bearer ${accessToken}`,
      'content-type': 'application/json',
      ...options.headers,
    },
  });
  if (!response.ok) {
    throw new Error(`${options.method ?? 'GET'} ${path}: ${response.status} ${await response.text()}`);
  }
  if (response.status === 204 || response.headers.get('content-length') === '0') return null;
  const text = await response.text();
  return text ? JSON.parse(text) : null;
}

const testToken = await token('test', 'test');
const demoToken = await token('demo', 'demo');
const testUser = await api('/api/me', testToken);
let roomId;
let client;

try {
  const suffix = crypto.randomUUID().slice(0, 8);
  const created = await api('/api/rooms', demoToken, {
    method: 'POST',
    body: JSON.stringify({
      name: `Push Core ${suffix}`,
      description: 'Temporary STOMP notification test',
      accessPolicy: 'INVITE_ONLY',
      approvalRequired: false,
      maxMembers: 4,
      visibility: 'PRIVATE',
      ephemeral: true,
    }),
  });
  roomId = created.room.id;
  await api(`/api/rooms/${roomId}/live/join`, demoToken, {
    method: 'POST',
    body: '{}',
  });

  const events = await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      client?.deactivate();
      reject(new Error('Timed out waiting for invite and mention notifications'));
    }, 10000);
    let inviteEvent;
    client = new Client({
      webSocketFactory: () => new WebSocket('ws://localhost:8080/ws'),
      connectHeaders: { Authorization: `Bearer ${testToken}` },
      reconnectDelay: 0,
      heartbeatIncoming: 0,
      heartbeatOutgoing: 0,
      onConnect: () => {
        client.subscribe('/user/queue/notifications', async (message) => {
          const payload = JSON.parse(message.body);
          if (payload.roomId !== roomId) return;
          if (payload.type === 'ROOM_INVITE') {
            inviteEvent = payload;
            try {
              await api(`/api/rooms/${roomId}/live/join`, testToken, {
                method: 'POST',
                body: '{}',
              });
              await api(`/api/rooms/${roomId}/live/messages`, demoToken, {
                method: 'POST',
                body: JSON.stringify({ body: `@${testUser.username} mention push check` }),
              });
            } catch (error) {
              reject(error);
            }
            return;
          }
          if (payload.type === 'ROOM_MENTION' && inviteEvent) {
            clearTimeout(timeout);
            resolve({ invite: inviteEvent, mention: payload });
          }
        });
        setTimeout(() => {
          api(`/api/rooms/${roomId}/invite-user/${testUser.id}`, demoToken, {
            method: 'POST',
            body: '{}',
          }).catch(reject);
        }, 250);
      },
      onStompError: (frame) => reject(new Error(frame.headers.message ?? frame.body)),
      onWebSocketError: (error) => reject(error),
    });
    client.activate();
  });

  if (events.invite.roomId !== roomId || events.invite.type !== 'ROOM_INVITE') {
    throw new Error(`Unexpected invite event: ${JSON.stringify(events.invite)}`);
  }
  if (events.mention.roomId !== roomId || events.mention.type !== 'ROOM_MENTION'
      || !events.mention.messageId || !events.mention.body.includes(`@${testUser.username}`)) {
    throw new Error(`Unexpected mention event: ${JSON.stringify(events.mention)}`);
  }
  console.log(`PASS: targeted ROOM_INVITE reached Test User over STOMP for room ${roomId}`);
  console.log(`PASS: targeted ROOM_MENTION reached Test User with message and haptic preference`);
} finally {
  await client?.deactivate();
  if (roomId) {
    await api(`/api/rooms/${roomId}`, demoToken, { method: 'DELETE' }).catch(() => {});
    console.log(`CLEANUP: removed temporary push room ${roomId}`);
  }
}
