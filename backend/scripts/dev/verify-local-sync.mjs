import fs from 'node:fs';
import { Client } from '../../../frontend/node_modules/@stomp/stompjs/esm6/index.js';

const privateDir = 'C:/Users/siddh/.letscook/secrets';
const users = JSON.parse(fs.readFileSync(`${privateDir}/voice-test-credentials.json`, 'utf8'));
const { roomId } = JSON.parse(fs.readFileSync(`${privateDir}/voice-test-room.json`, 'utf8'));
const origin = 'https://xynk.in';

async function token(role) {
  const user = users.find(item => item.role === role);
  const body = new URLSearchParams({
    client_id: 'lets-cook-web', grant_type: 'password',
    username: user.username, password: user.password,
  });
  const response = await fetch(`${origin}/realms/xynk/protocol/openid-connect/token`, {
    method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body,
  });
  if (!response.ok) throw new Error(`${role} login failed: ${response.status}`);
  return (await response.json()).access_token;
}

const [host, guest] = await Promise.all([token('host'), token('guest')]);
const marker = `sync-${crypto.randomUUID().slice(0, 8)}`;
let client;
try {
  await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error('No sync event received')), 12000);
    client = new Client({
      webSocketFactory: () => new WebSocket('wss://xynk.in/ws'),
      connectHeaders: { Authorization: `Bearer ${guest}` },
      reconnectDelay: 0,
      heartbeatIncoming: 0,
      heartbeatOutgoing: 0,
      onConnect: async () => {
        client.subscribe(`/topic/rooms/${roomId}/watch`, message => {
          const event = JSON.parse(message.body);
          if (event.state?.mediaId !== marker) return;
          clearTimeout(timeout);
          resolve();
        });
        try {
          const response = await fetch(`${origin}/api/rooms/${roomId}/watch`, {
            method: 'PUT',
            headers: { authorization: `Bearer ${host}`, 'content-type': 'application/json' },
            body: JSON.stringify({
              provider: 'DIRECT_MP4', sourceType: 'DIRECT', mediaId: marker,
              sourceUrl: `https://example.com/${marker}.mp4`, title: 'Temporary sync transport test',
              playing: false, positionSeconds: 0, playbackRate: 1,
            }),
          });
          if (!response.ok) throw new Error(`Host watch update failed: ${response.status}`);
        } catch (error) { clearTimeout(timeout); reject(error); }
      },
      onStompError: frame => { clearTimeout(timeout); reject(new Error(frame.headers.message)); },
      onWebSocketError: error => { clearTimeout(timeout); reject(error); },
    });
    client.activate();
  });
  console.log('PASS: guest received host playback update over backend WebSocket with local LiveKit stopped');
} finally {
  await client?.deactivate();
}
