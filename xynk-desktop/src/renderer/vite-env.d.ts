/// <reference types="vite/client" />
/// <reference types="electron" />

interface ImportMetaEnv {
  readonly VITE_API_BASE: string;
  readonly VITE_AUTH_BASE: string;
  readonly VITE_CLIENT_ID: string;
  readonly VITE_REALM: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}

declare global {
  interface Window {
    ipc: {
      invoke: (channel: string, ...args: unknown[]) => Promise<unknown>;
      on: (channel: string, listener: (data: unknown) => void) => () => void;
      once: (channel: string, listener: (data: unknown) => void) => () => void;
    };
    dart: {
      invoke: (method: string, args: unknown[]) => Promise<unknown>;
      on: (event: string, listener: (data: unknown) => void) => () => void;
    };
    session: {
      get: (key: string) => Promise<unknown>;
      set: (key: string, value: string) => Promise<unknown>;
      clear: () => Promise<unknown>;
    };
    window: {
      minimize: () => Promise<void>;
      maximize: () => Promise<void>;
      close: () => Promise<void>;
      isMaximized: () => Promise<boolean>;
    };
  }
}