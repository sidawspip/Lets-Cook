import { Injectable, signal } from '@angular/core';
import Keycloak from 'keycloak-js';

@Injectable({ providedIn: 'root' })
export class AuthService {
  private readonly keycloak = new Keycloak({
    url: window.location.protocol === 'https:'
      ? window.location.origin
      : `http://${window.location.hostname}:8180`,
    realm: 'xynk',
    clientId: 'lets-cook-web'
  });

  readonly authenticated = signal(false);
  readonly displayName = signal('Guest');
  readonly available = signal(true);
  readonly failureMessage = signal('');
  private refreshTimer?: ReturnType<typeof setInterval>;

  private applySession(authenticated: boolean): void {
    this.available.set(true);
    this.failureMessage.set('');
    this.authenticated.set(authenticated);
    this.displayName.set(authenticated
      ? (this.keycloak.tokenParsed?.['name'] as string
        ?? this.keycloak.tokenParsed?.['preferred_username'] as string
        ?? 'Member')
      : 'Guest');
    if (authenticated && !this.refreshTimer) {
      this.refreshTimer = setInterval(() => {
        if (this.keycloak.authenticated) {
          void this.keycloak.updateToken(60).catch(() => {
            // Retry on the next interval or authenticated API request.
          });
        }
      }, 60_000);
    }
  }

  async initialize(): Promise<void> {
    try {
      const initialization = this.keycloak.init({
        onLoad: 'check-sso',
        // Web Crypto (required by PKCE-S256) is unavailable on a plain HTTP
        // LAN origin. Keep PKCE enabled everywhere Chrome considers secure,
        // while allowing the explicitly configured local UAT origin to log in.
        pkceMethod: 'S256',
        checkLoginIframe: false
      });
      // If Keycloak finishes after the startup guard, restore the session as
      // soon as it responds instead of leaving the page in an error state.
      let timedOut = false;
      void initialization.then(authenticated => {
        if (timedOut) this.applySession(authenticated);
      }).catch(() => {});
      // A stalled silent SSO request must not leave the entire app blank.
      let timeout: ReturnType<typeof setTimeout> | undefined;
      const authenticated = await Promise.race([
        initialization,
        new Promise<never>((_, reject) => {
          timeout = setTimeout(() => {
            timedOut = true;
            reject(new Error('Authentication startup timed out'));
          }, 8000);
        })
      ]).finally(() => { if (timeout) clearTimeout(timeout); });
      this.applySession(authenticated);
    } catch {
      this.available.set(false);
      this.failureMessage.set(
        !window.crypto?.subtle
          ? 'Chrome blocks secure authentication on a plain HTTP network address. Use http://localhost:4200 on this computer, or enable HTTPS for access from other devices.'
          : 'Authentication could not start. Make sure Docker services are healthy, then refresh.'
      );
    }
  }

  login(identityProvider?: 'google' | 'x'): Promise<void> {
    return this.keycloak.login({
      redirectUri: window.location.origin,
      idpHint: identityProvider
    });
  }

  logout(): Promise<void> {
    // Capture the URL while the ID token is still available so Keycloak can
    // invalidate the exact SSO session, then switch the SPA to signed-out state
    // immediately instead of showing authenticated Home during the redirect.
    const logoutUrl = this.keycloak.createLogoutUrl({ redirectUri: window.location.origin });
    if (this.refreshTimer) clearInterval(this.refreshTimer);
    this.refreshTimer = undefined;
    this.keycloak.clearToken();
    this.authenticated.set(false);
    this.displayName.set('Guest');
    window.location.replace(logoutUrl);
    return new Promise<void>(() => {});
  }

  async token(): Promise<string> {
    if (!this.keycloak.authenticated) {
      throw new Error('Not authenticated');
    }
    await this.keycloak.updateToken(30);
    return this.keycloak.token ?? '';
  }
}

