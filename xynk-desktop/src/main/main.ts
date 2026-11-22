import { app, BrowserWindow, ipcMain, session, shell, components, desktopCapturer } from 'electron';
import * as path from 'path';
import * as http from 'node:http';
import { createHash, randomBytes } from 'node:crypto';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import * as fs from 'node:fs';
import { crunchyrollRequestHeaders, prepareCrunchyroll, requestCrunchyrollLicense } from './providers/crunchyroll';
const isDev = !app.isPackaged && process.env.XYNK_DESKTOP_PACKAGED !== '1';
app.commandLine.appendSwitch('autoplay-policy', 'no-user-gesture-required');
app.disableHardwareAcceleration();

let mainWindow: BrowserWindow | null = null;
let widevineReady: Promise<unknown> | null = null;
let selectedCaptureSourceId: string | null = null;
const execFileAsync = promisify(execFile);

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 800,
    minWidth: 960,
    minHeight: 640,
    title: 'XYNK',
    autoHideMenuBar: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: true,
      webSecurity: true,
      webviewTag: true,
    },
    icon: app.isPackaged
      ? path.join(process.resourcesPath, 'app.asar', 'resources', 'icon.ico')
      : path.join(__dirname, '../../resources/icon.ico'),
  });
  mainWindow.setMenuBarVisibility(false);
  const diagnostic = (message: string) => {
    try { fs.appendFileSync(path.join(app.getPath('userData'), 'desktop-errors.log'), `${new Date().toISOString()} ${message}\n`); } catch { /* Diagnostics must not affect startup. */ }
  };
  mainWindow.webContents.on('render-process-gone', (_event, details) => diagnostic(`Renderer exited: ${details.reason} (${details.exitCode})`));
  mainWindow.webContents.on('console-message', (_event, level, message) => {
    if (level >= 2) diagnostic(`Renderer console: ${message}`);
  });
  mainWindow.webContents.on('did-fail-load', (_event, code, description, url) => diagnostic(`Page load failed: ${code} ${description} ${url}`));
  mainWindow.webContents.on('will-attach-webview', (event, webPreferences, params) => {
    let url: URL;
    try { url = new URL(params.src); }
    catch { event.preventDefault(); return; }
    if (url.protocol !== 'https:') { event.preventDefault(); return; }
    delete webPreferences.preload;
    webPreferences.nodeIntegration = false;
    webPreferences.contextIsolation = true;
    webPreferences.sandbox = true;
  });

  if (isDev) {
    mainWindow.loadURL('http://localhost:5173');
    mainWindow.webContents.openDevTools();
  } else {
    mainWindow.loadFile(path.join(__dirname, '../renderer/index.html'));
  }

  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

app.whenReady().then(() => {
  widevineReady = components.whenReady();
  void widevineReady.catch(error => console.error('Widevine component unavailable:', error));
  session.defaultSession.webRequest.onBeforeSendHeaders(
    {urls: ['https://www.crunchyroll.com/license/v1/license/widevine*', 'https://www.crunchyroll.com/playback/*', 'https://www.youtube.com/embed/*', 'https://www.youtube-nocookie.com/embed/*']},
    (details, callback) => {
      if (details.url.startsWith('https://www.youtube.com/embed/') || details.url.startsWith('https://www.youtube-nocookie.com/embed/')) {
        callback({requestHeaders: {...details.requestHeaders, Referer: 'https://xynk.in/'}});
        return;
      }
      callback({requestHeaders: crunchyrollRequestHeaders(details.url, details.requestHeaders)});
    },
  );
  session.defaultSession.setDisplayMediaRequestHandler((_request, callback) => {
    if (!selectedCaptureSourceId) { callback(null); return; }
    void desktopCapturer.getSources({types: ['screen', 'window']}).then(sources => {
      const source = sources.find(item => item.id === selectedCaptureSourceId);
      selectedCaptureSourceId = null;
      callback(source ? {video: source} : null);
    }).catch(() => callback(null));
  });
  createWindow();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

ipcMain.handle('screen:sources', async () => {
  const sources = await desktopCapturer.getSources({types: ['screen', 'window'], thumbnailSize: {width: 320, height: 180}});
  return sources.map(source => ({id: source.id, name: source.name, thumbnail: source.thumbnail.toDataURL()}));
});

ipcMain.handle('screen:select', async (_event, sourceId: string) => {
  const sources = await desktopCapturer.getSources({types: ['screen', 'window']});
  if (!sources.some(source => source.id === sourceId)) throw new Error('Capture source is no longer available');
  selectedCaptureSourceId = sourceId;
});

ipcMain.handle('cr:prepare', async (_event, episodeId: string) => {
  if (!widevineReady) throw new Error('Widevine is not initialized');
  await widevineReady;
  return prepareCrunchyroll(episodeId);
});

ipcMain.handle('cr:license', async (_event, challenge: Uint8Array) => {
  if (!(challenge instanceof Uint8Array) || challenge.byteLength > 1024 * 1024) throw new Error('Invalid DRM challenge');
  return requestCrunchyrollLicense(challenge);
});

ipcMain.handle('youtube:resolve', async (_event, videoId: string, quality = 'auto') => {
  if (!/^[A-Za-z0-9_-]{11}$/.test(videoId)) throw new Error('Invalid YouTube video ID');
  const resolver = app.isPackaged
    ? path.join(process.resourcesPath, 'xynk-youtube-resolver.exe')
    : path.join(__dirname, '../../resources/xynk-youtube-resolver.exe');
  const {stdout} = await execFileAsync(resolver, [videoId, quality], {timeout: 40000, maxBuffer: 64 * 1024});
  const result = JSON.parse(stdout.trim()) as {url: string; quality: string; qualities: string[]};
  const stream = new URL(result.url);
  if (stream.protocol !== 'https:') throw new Error('YouTube returned an invalid stream');
  return result;
});

ipcMain.handle('auth:identity-provider', async (_event, provider: string) => {
  if (provider !== 'google' && provider !== 'x') throw new Error('Unsupported identity provider');
  const redirectUri = 'http://127.0.0.1:42817/oauth/callback';
  const verifier = randomBytes(48).toString('base64url');
  const challenge = createHash('sha256').update(verifier).digest('base64url');
  const state = randomBytes(24).toString('base64url');
  const authorization = new URL('https://xynk.in/realms/xynk/protocol/openid-connect/auth');
  for (const [key, value] of Object.entries({
    client_id: 'lets-cook-mobile', redirect_uri: redirectUri, response_type: 'code',
    scope: 'openid profile email offline_access', code_challenge: challenge,
    code_challenge_method: 'S256', state, kc_idp_hint: provider,
  })) authorization.searchParams.set(key, value);

  const code = await new Promise<string>((resolve, reject) => {
    let settled = false;
    const finish = (error?: Error, value?: string) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      server.close();
      if (error) reject(error); else resolve(value!);
    };
    const server = http.createServer((request, response) => {
      const callback = new URL(request.url ?? '/', redirectUri);
      if (callback.pathname !== '/oauth/callback') {
        response.writeHead(404).end();
        return;
      }
      response.writeHead(200, {'Content-Type': 'text/html; charset=utf-8'});
      response.end('<!doctype html><title>XYNK</title><body style="background:#15182c;color:white;font:18px system-ui;text-align:center;padding:20vh 2rem"><h1>Sign-in complete</h1><p>Return to XYNK.</p></body>');
      if (callback.searchParams.get('state') !== state) return finish(new Error('Sign-in response could not be verified'));
      const error = callback.searchParams.get('error');
      if (error) return finish(new Error(callback.searchParams.get('error_description') || error));
      const result = callback.searchParams.get('code');
      if (!result) return finish(new Error('Identity provider returned no code'));
      finish(undefined, result);
    });
    const timer = setTimeout(() => finish(new Error('Sign-in timed out')), 180000);
    server.once('error', error => finish(error));
    server.listen(42817, '127.0.0.1', () => {
      void shell.openExternal(authorization.toString()).catch(error => finish(error));
    });
  });
  const form = new URLSearchParams({
    client_id: 'lets-cook-mobile', grant_type: 'authorization_code', code,
    redirect_uri: redirectUri, code_verifier: verifier,
  });
  const tokenResponse = await fetch('https://xynk.in/realms/xynk/protocol/openid-connect/token', {
    method: 'POST', headers: {'Content-Type': 'application/x-www-form-urlencoded'}, body: form,
  });
  if (!tokenResponse.ok) throw new Error(`Could not complete browser sign-in (${tokenResponse.status})`);
  const token = await tokenResponse.json() as {access_token: string; refresh_token: string; expires_in: number};
  return {accessToken: token.access_token, refreshToken: token.refresh_token,
    expiresAt: new Date(Date.now() + token.expires_in * 1000).toISOString()};
});

ipcMain.handle('auth:register', () => shell.openExternal(
  'https://xynk.in/realms/xynk/protocol/openid-connect/registrations?client_id=lets-cook-web&response_type=code&scope=openid%20profile%20email&redirect_uri=https%3A%2F%2Fxynk.in',
));

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

// IPC handlers
ipcMain.handle('window:minimize', () => mainWindow?.minimize());
ipcMain.handle('window:maximize', () => mainWindow?.isMaximized() ? mainWindow?.unmaximize() : mainWindow?.maximize());
ipcMain.handle('window:close', () => mainWindow?.close());
ipcMain.handle('window:isMaximized', () => mainWindow?.isMaximized());

// Session persistence
ipcMain.handle('session:get', (event, key: string) => {
  return session.defaultSession.cookies.get({ url: 'https://xynk.in', name: key });
});

ipcMain.handle('session:set', (event, key: string, value: string) => {
  return session.defaultSession.cookies.set({ url: 'https://xynk.in', name: key, value, expirationDate: Math.floor(Date.now() / 1000) + 3600 * 24 * 30 });
});

ipcMain.handle('session:clear', () => {
  return session.defaultSession.clearStorageData();
});
