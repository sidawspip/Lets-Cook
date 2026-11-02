import { Injectable, signal } from '@angular/core';
import Keycloak from 'keycloak-js';

@Injectable({ providedIn: 'root' })
export class AuthService {
  private readonly keycloak = new Keycloak({
    url: window.location.protocol === 'https:'
      ? window.location.origin
      : `http://${window.location.hostname}:8180`,
    realm: 'lets-cook',
    clientId: 'lets-cook-web'
  });

  readonly authenticated = signal(false);
  readonly displayName = signal('Guest');
  readonly available = signal(true);
  readonly failureMessage = signal('');

  async initialize(): Promise<void> {
    try {
      const authenticated = await this.keycloak.init({
        onLoad: 'check-sso',
        // Web Crypto (required by PKCE-S256) is unavailable on a plain HTTP
        // LAN origin. Keep PKCE enabled everywhere Chrome considers secure,
        // while allowing the explicitly configured local UAT origin to log in.
        pkceMethod: 'S256',
        checkLoginIframe: false
      });
      this.authenticated.set(authenticated);
      this.displayName.set(this.keycloak.tokenParsed?.['name'] as string
        ?? this.keycloak.tokenParsed?.['preferred_username'] as string
        ?? 'Member');
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
    return this.keycloak.logout({ redirectUri: window.location.origin });
  }

  async token(): Promise<string> {
    if (!this.keycloak.authenticated) {
      throw new Error('Not authenticated');
    }
    await this.keycloak.updateToken(30);
    return this.keycloak.token ?? '';
  }
}

