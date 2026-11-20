import { bootstrapApplication } from '@angular/platform-browser';
import { provideHttpClient } from '@angular/common/http';
import { AppComponent } from './app/app.component';
import { AuthService } from './app/core/auth.service';

async function bootstrap(): Promise<void> {
  const auth = new AuthService();
  await auth.initialize();
  await bootstrapApplication(AppComponent, {
    providers: [provideHttpClient(), { provide: AuthService, useValue: auth }]
  });
}

bootstrap().catch((error: unknown) => {
  console.error('Application bootstrap failed', error);
  const root = document.querySelector('app-root');
  if (root) {
    root.innerHTML = '<main style="font:16px system-ui;padding:2rem;color:#fff;background:#0b0d12;min-height:100vh"><h1>Xynk could not start</h1><p>Please refresh this page. If it stays here, open <a style="color:#90caff" href="/connection-check.html">connection check</a>.</p></main>';
  }
});

