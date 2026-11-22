import { session } from 'electron';
import { randomUUID } from 'node:crypto';

const BASE = 'https://www.crunchyroll.com';
const providerSession = () => session.fromPartition('persist:xynk-provider');
const USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/156.0.0.0 Safari/537.36';

interface Access { token: string; accountId?: string; expiresAt: number; sessionCookie?: string }
interface Playback { episodeId: string; playbackToken: string; access: Access; cookies: string }
let cachedAccess: Access | null = null;
let cachedBasic: string | null = null;
let activePlayback: Playback | null = null;

async function cookies(): Promise<string> {
  const list = await providerSession().cookies.get({url: BASE});
  return list.map(cookie => `${cookie.name}=${cookie.value}`).join('; ');
}

async function providerFetch(path: string, options: RequestInit = {}): Promise<Response> {
  const response = await providerSession().fetch(`${BASE}${path}`, {
    ...options,
    headers: {'User-Agent': USER_AGENT, Cookie: await cookies(), ...options.headers},
  });
  if (!response.ok) throw new Error(`Crunchyroll returned ${response.status} for ${path.split('?')[0]}`);
  return response;
}

async function basicAuth(): Promise<string> {
  if (cachedBasic) return cachedBasic;
  const page = await (await providerFetch('/')).text();
  const app = page.match(/window\.__APP_CONFIG__\s*=\s*(\{[^<]+\})/s)?.[1];
  const etp = app ? null : page.match(/window\.etp\s*=\s*(\{.+?\})(?:;|\s*<)/s)?.[1];
  const config = app ? JSON.parse(app) as any : etp ? JSON.parse(etp) as any : null;
  const params = app ? config?.cxApiParams : config?.config?.cxApiParams;
  const id = params?.accountAuthClientId || params?.anonClientId;
  if (!id) throw new Error('Crunchyroll client configuration unavailable');
  cachedBasic = `Basic ${Buffer.from(`${id}:`).toString('base64')}`;
  return cachedBasic;
}

async function accessToken(): Promise<Access> {
  const cookieHeader = await cookies();
  const etp = cookieHeader.split(';').map(part => part.trim()).find(part => part.startsWith('etp_rt='))?.slice(7);
  // Signing in or out changes the provider cookie without restarting Xynk.
  // An anonymous cached token must never survive that transition.
  if (cachedAccess && cachedAccess.sessionCookie === etp && Date.now() < cachedAccess.expiresAt - 60000) return cachedAccess;
  const device = cookieHeader.split(';').map(part => part.trim()).find(part => part.startsWith('device_id='))?.slice(10)?.toUpperCase() || randomUUID().toUpperCase();
  const form = new URLSearchParams({grant_type: etp ? 'etp_rt_cookie' : 'client_id', device_id: device, device_type: 'Chrome on Windows'});
  if (etp) form.set('etp_rt_cookie', etp); else form.set('scope', 'offline_access');
  const response = await providerFetch('/auth/v1/token', {
    method: 'POST',
    headers: {
      Authorization: await basicAuth(), 'Content-Type': 'application/x-www-form-urlencoded',
      ...(!etp ? {'ETP-Anonymous-ID': randomUUID()} : {}),
    },
    body: form,
  });
  const result = await response.json() as {access_token: string; account_id?: string; expires_in?: number};
  cachedAccess = {token: result.access_token, accountId: result.account_id || undefined, sessionCookie: etp,
    expiresAt: Date.now() + (result.expires_in || 300) * 1000};
  return cachedAccess;
}

export async function prepareCrunchyroll(episodeId: string): Promise<{manifestUrl: string}> {
  if (episodeId.startsWith('https://')) {
    const page = new URL(episodeId);
    if (!/(^|\.)crunchyroll\.com$/i.test(page.hostname)) throw new Error('Invalid Crunchyroll episode URL');
    episodeId = page.pathname.match(/\/watch\/([A-Za-z0-9]+)/)?.[1] || episodeId;
  }
  if (!/^[A-Za-z0-9]+$/.test(episodeId)) throw new Error('Invalid Crunchyroll episode ID');
  const access = await accessToken();
  const response = await providerFetch(`/playback/v2/${episodeId}/web/chrome/play`, {
    headers: {Authorization: `Bearer ${access.token}`},
  });
  const stream = await response.json() as {url: string; token: string};
  if (!stream.url?.startsWith('https://') || !stream.token) throw new Error('Crunchyroll returned no playable stream');
  activePlayback = {episodeId, playbackToken: stream.token, access, cookies: await cookies()};
  const manifest = new URL(stream.url);
  if (access.accountId) {
    manifest.searchParams.set('playbackGuid', stream.token);
    manifest.searchParams.set('account_id', access.accountId);
  }
  return {manifestUrl: manifest.toString()};
}

export function crunchyrollRequestHeaders(url: string, existing: Record<string, string>): Record<string, string> {
  const playback = activePlayback;
  if (!playback) return existing;
  const target = new URL(url);
  if (target.hostname !== 'www.crunchyroll.com') return existing;
  if (target.pathname.startsWith('/playback/')) {
    return {...existing, Authorization: `Bearer ${playback.access.token}`,
      Cookie: playback.cookies,
      Referer: `${BASE}/`};
  }
  if (target.pathname === '/license/v1/license/widevine') {
    return {...existing, Authorization: `Bearer ${playback.access.token}`,
      'X-Cr-Content-Id': playback.episodeId,
      'X-Cr-Video-Token': playback.playbackToken,
      'Content-Type': 'application/octet-stream'};
  }
  return existing;
}

export async function requestCrunchyrollLicense(challenge: Uint8Array): Promise<Uint8Array> {
  const playback = activePlayback;
  if (!playback) throw new Error('Crunchyroll playback session is missing');
  if (Date.now() >= playback.access.expiresAt - 60000) playback.access = await accessToken();
  const response = await providerSession().fetch(`${BASE}/license/v1/license/widevine`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${playback.access.token}`,
      'X-Cr-Content-Id': playback.episodeId,
      'X-Cr-Video-Token': playback.playbackToken,
      'Content-Type': 'application/octet-stream',
      Cookie: playback.cookies,
      'User-Agent': USER_AGENT,
    },
    body: Buffer.from(challenge),
  });
  if (!response.ok) throw new Error(`Crunchyroll license request failed (${response.status})`);
  const result = await response.json() as {license?: string};
  if (!result.license) throw new Error('Crunchyroll returned no license');
  return new Uint8Array(Buffer.from(result.license, 'base64'));
}
