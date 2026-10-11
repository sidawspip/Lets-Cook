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

bootstrap().catch((error: unknown) => console.error('Application bootstrap failed', error));

