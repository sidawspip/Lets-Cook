import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { UserRound, LockKeyhole, Eye, EyeOff, UserRoundPlus } from 'lucide-react';
import { useWatchPartyStore } from '../../stores/watchPartyStore';
import { LogoMark } from '../ui/LogoMark';

export function LoginScreen() {
  const navigate = useNavigate();
  const { login, loginWithProvider, busy, error, setError } = useWatchPartyStore();
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    try {
      await login(username.trim(), password);
      navigate('/');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Login failed');
    }
  };

  const handleProvider = async (provider: 'google' | 'x') => {
    setError(null);
    try { await loginWithProvider(provider); navigate('/'); }
    catch (error) { setError(error instanceof Error ? error.message : String(error)); }
  };

  return (
    <div className="login-screen min-h-screen bg-xynk-ink flex items-center justify-center p-6">
      <div className="absolute inset-0 -z-10 bg-gradient-to-br from-[#31204B] via-[#4B315D] to-[#101D2B]">
        <div className="absolute -top-90 -right-90 w-[300px] h-[300px] rounded-full bg-[#66E33F9E] blur-[70px]" />
        <div className="absolute bottom-70 left-[-100px] w-[340px] h-[340px] rounded-full bg-[#661AA8D6] blur-[70px]" />
        <div className="absolute inset-0 bg-gradient-to-b from-[#12000000] to-[#B3050910]" />
      </div>

      <div className="login-card glass-surface w-full max-w-[560px] relative px-2 md:px-6">
        <div className="login-intro">
        <div className="flex justify-start mb-10">
          <LogoMark size={62} />
        </div>

        <h1 className="text-left text-4xl md:text-[46px] leading-[0.98] font-black tracking-tight text-white mb-4">Watch together.<br />Stay connected.</h1>
        <p className="text-left text-xynk-muted mb-10">Watch, talk, and build the queue together—without leaving the room.</p>
        </div>

        <div className="login-form-column">
        {error && (
          <div className="mb-6 p-4 bg-red-500/20 border border-red-500/50 rounded-xl text-red-300 text-sm">
            {error}
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-3">
          <div>
            <label htmlFor="login-username" className="block text-xs font-medium mb-2 text-xynk-muted">Username</label>
            <div className="relative"><UserRound className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-xynk-muted" /><input
              type="text"
              id="login-username"
              value={username}
              onChange={e => setUsername(e.target.value)}
              className="input-field pl-11"
              placeholder="Username"
              autoComplete="username"
              required
            /></div>
          </div>

          <div>
            <label htmlFor="login-password" className="block text-xs font-medium mb-2 text-xynk-muted">Password</label>
            <div className="relative">
              <LockKeyhole className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-xynk-muted" />
              <input
                type={showPassword ? 'text' : 'password'}
                id="login-password"
                value={password}
                onChange={e => setPassword(e.target.value)}
                className="input-field pl-11 pr-12"
                placeholder="Password"
                autoComplete="current-password"
                required
              />
              <button
                type="button"
                aria-label={showPassword ? 'Hide password' : 'Show password'}
                onClick={() => setShowPassword(!showPassword)}
                className="absolute right-4 top-1/2 -translate-y-1/2 text-xynk-muted hover:text-white"
              >
                {showPassword ? <EyeOff className="w-5 h-5" /> : <Eye className="w-5 h-5" />}
              </button>
            </div>
          </div>

          <button
            type="submit"
            disabled={busy}
            className="btn-primary w-full"
          >
            {busy ? (
              <>
                <svg className="w-5 h-5 animate-spin" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="12" cy="12" r="10" strokeLinecap="round" strokeDasharray="31.4 31.4"/></svg>
                Signing in...
              </>
            ) : (
              'Enter Xynk'
            )}
          </button>
        </form>

        <div className="mt-3 space-y-2">
          <button type="button" disabled={busy} onClick={() => void handleProvider('google')} className="btn-secondary w-full py-2 text-xynk-lime"><span className="font-black text-lg">G</span>Continue with Google</button>
          <button type="button" disabled={busy} onClick={() => void handleProvider('x')} className="btn-secondary w-full py-2 text-xynk-lime"><span className="font-black text-lg">𝕏</span>Continue with X</button>
          <button type="button" onClick={() => void window.xynkDesktop.register()} className="btn-secondary w-full py-2 text-xynk-lime"><UserRoundPlus className="w-4 h-4" />Create an account</button>
        </div>
        </div>
      </div>
    </div>
  );
}
