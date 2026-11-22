export function _looksSensitive(value: string): boolean {
  const text = value.toLowerCase();
  return ['nsfw', 'adult', 'porn', 'xxx', 'xhamster', 'xvideos', 'pornhub', 'femdom', 'nude', 'sex'].some(w => text.includes(w));
}

export function _providerName(value: string): string {
  const provider = value.trim().toUpperCase();
  const map: Record<string, string> = {
    YOUTUBE: 'YouTube',
    VIMEO: 'Vimeo',
    TWITCH: 'Twitch',
    X: 'X',
    GOOGLE_DRIVE: 'Google Drive',
    DRIVE: 'Google Drive',
    DROPBOX: 'Dropbox',
    ONEDRIVE: 'OneDrive',
    BOX: 'Box',
    NEXTCLOUD: 'Nextcloud',
    INTERNET_ARCHIVE: 'Internet Archive',
    CRUNCHYROLL: 'Crunchyroll',
    NETFLIX: 'Netflix',
    PRIME_VIDEO: 'Prime Video',
    DIRECT_MP4: 'Web',
    DIRECT_HLS: 'Web',
    WEB: 'Web',
  };
  return map[provider] ?? provider.toLowerCase().split('_').map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(' ');
}

export function _time(seconds: number): string {
  if (!isFinite(seconds) || seconds < 0) return '0:00';
  const total = Math.floor(seconds);
  const minutes = Math.floor(total / 60) % 60;
  const secs = total % 60;
  const hours = Math.floor(total / 3600);
  return hours > 0 ? `${hours}:${minutes.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}` : `${minutes}:${secs.toString().padStart(2, '0')}`;
}

export function _timeDetailed(seconds: number): string {
  const duration = Math.floor(Math.max(0, seconds));
  if (duration === 0) return '<1m';
  if (duration < 60) return '<1m';
  if (duration < 3600) return `${Math.floor(duration / 60)}m`;
  const hours = Math.floor(duration / 3600);
  const minutes = Math.floor((duration % 3600) / 60);
  return minutes === 0 ? `${hours}h` : `${hours}h ${minutes}m`;
}

export function _dateLabel(value?: string): string {
  const date = value ? new Date(value) : null;
  if (!date || isNaN(date.getTime())) return '';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return `${months[date.getMonth()]} ${date.getFullYear()}`;
}

export function _relativeTime(value?: string): string {
  const date = value ? new Date(value) : null;
  if (!date || isNaN(date.getTime())) return 'recently';
  const diff = Date.now() - date.getTime();
  if (diff < 60000) return 'just now';
  if (diff < 3600000) return `${Math.floor(diff / 60000)}m ago`;
  if (diff < 86400000) return `${Math.floor(diff / 3600000)}h ago`;
  if (diff < 604800000) return `${Math.floor(diff / 86400000)}d ago`;
  return _dateLabel(value);
}

export function _shortDate(value?: string): string {
  const date = value ? new Date(value) : null;
  if (!date || isNaN(date.getTime())) return '';
  return `${date.getDate()}/${date.getMonth() + 1}/${date.getFullYear().toString().slice(2)}`;
}

export function _providerLabel(value: string): string {
  return _providerName(value);
}

export function _normalizedMediaTitle(title: string): string {
  return title
    .toLowerCase()
    .replace(/\[[^\]]*\]|\([^)]*\)/g, ' ')
    .replace(/\b(official|video|audio|lyrics?|lyrical|hd|4k|8k|full song)\b/gi, ' ')
    .replace(/[^a-z0-9]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

export function _isGenericMediaTitle(title: string): boolean {
  const normalized = _normalizedMediaTitle(title);
  return normalized === '' || normalized === 'youtube video' || normalized === 'selected web video' || normalized === 'video' || normalized === 'now playing';
}

export function _sameMediaTitle(left: string, right: string): boolean {
  const a = _normalizedMediaTitle(left);
  const b = _normalizedMediaTitle(right);
  if (!a || !b) return false;
  if (a === b) return true;
  const shorter = a.length < b.length ? a : b;
  const longer = a.length < b.length ? b : a;
  return shorter.length >= 10 && longer.includes(shorter) && shorter.length / longer.length >= 0.78;
}

export function _mediaTitle(state: { title: string } | null): string {
  if (!state) return 'Search YouTube to begin';
  const storedTitle = state.title.trim();
  const separator = storedTitle.lastIndexOf(' · ');
  if (separator > 0) return storedTitle.substring(0, separator).trim();
  return storedTitle || (state.title === 'Synced for everyone in the room' ? 'Video' : state.title);
}

export function _sourceLabel(state: { provider: string; title: string; sourceUrl?: string } | null): string {
  if (!state) return 'Search YouTube to begin';
  const provider = state.provider.trim().toUpperCase();
  if (provider !== 'WEB') return _providerName(provider);
  const storedTitle = state.title.trim();
  const separator = storedTitle.lastIndexOf(' · ');
  if (separator > 0 && separator + 3 < storedTitle.length) return storedTitle.substring(separator + 3).trim();
  try {
    const host = new URL(state.sourceUrl ?? '').hostname.toLowerCase();
    return host.startsWith('www.') ? host.slice(4) : (host || 'Web video');
  } catch { return 'Web video'; }
}

export function _publicDisplayName(profile: { displayName?: string; username?: string; name?: string } | null): string {
  return profile?.displayName?.trim() || profile?.name?.trim() || profile?.username?.trim() || 'XYNK member';
}

export function _publicHandle(profile: { username?: string; handle?: string } | null): string {
  return (profile?.username || profile?.handle || 'member').replace(/^@/, '');
}

export const _watchTime = _time;
export const _watchTimeDetailed = _timeDetailed;

export function _providerCaption(provider: string): string {
  return _providerName(provider);
}

export function _asInt(value: unknown): number {
  const number = Number(value);
  return Number.isFinite(number) ? Math.trunc(number) : 0;
}
