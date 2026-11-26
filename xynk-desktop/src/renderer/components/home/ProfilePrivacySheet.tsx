import { useState } from 'react';
import { Palette } from 'lucide-react';
import { AppearanceSettings } from './AppearanceSettings';
import { useUIStore } from '../../stores/uiStore';
import { getTheme } from '../../themes/appearance';
import { GlassDialog } from '../ui/GlassDialog';
import { EyeOff as SensitivityIcon, PictureInPicture2 as FloatingIcon, VolumeX as MuteIcon, Vibrate as HapticIcon, Languages as TranslateIcon, MapPin as LocationIcon, Users as InviteIcon, Crown as PremiumIcon, HelpCircle as HelpIcon, Code2 as CodeIcon, Globe as LangIcon, Heart as ReactionIcon, ChevronRight, X } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { useWatchPartyStore } from '../../stores/watchPartyStore';
import { _time, _timeDetailed, _providerLabel, _publicDisplayName, _publicHandle } from '../../lib/formatters';

export function ProfilePrivacySheet({ onClose }: { onClose: () => void }) {
  const navigate = useNavigate();
  const [appearanceOpen, setAppearanceOpen] = useState(false);
  const themeId = useUIStore(state => state.themeId);
  const {
    profile,
    displayName,
    hideSensitiveContent,
    floatingVideo,
    muteOtherAudio,
    hapticFeedback,
    autoTranslate,
    hideLocation,
    restrictInvites,
    preferredLanguage,
    quickReaction,
    setHideSensitiveContent,
    setProfilePreference,
    saveProfilePreferences,
    setProfileVisibility,
    profileVisibility,
    savingProfilePreferences,
    logout,
  } = useWatchPartyStore();

  return (
    <GlassDialog label="Settings" onClose={onClose} className="settings-dialog">
      {appearanceOpen ? <AppearanceSettings onBack={() => setAppearanceOpen(false)} /> : <div className="min-h-0 flex flex-col">
        {/* Header */}
        <div className="dialog-header flex items-center justify-between p-4 border-b border-xynk-line">
          <div>
            <h2 className="text-xl font-black text-white">Settings</h2>
            <p className="text-sm text-white/60">Privacy, playback and social preferences</p>
          </div>
          <button onClick={onClose} aria-label="Close settings" className="icon-button hover:bg-white/10 transition-colors">
            <X className="w-5 h-5 text-white" />
          </button>
        </div>

        {/* Content */}
        <div className="dialog-body flex-1 min-h-0 overflow-y-auto p-4 space-y-6">
          {/* Saving banner */}
          {savingProfilePreferences.size > 0 && (
            <div className="p-3 bg-xynk-lime/10 border border-xynk-lime/30 rounded-xl text-xynk-lime text-sm font-medium flex items-center gap-2">
              <svg className="w-5 h-5 animate-spin" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="12" cy="12" r="10" strokeLinecap="round" strokeDasharray="31.4 31.4"/></svg>
              Saving settings…
            </div>
          )}

          {/* Account */}
          <SettingsSection label="ACCOUNT">
            <button type="button" onClick={() => { if (profile?.id) { onClose(); navigate(`/profile/${profile.id}`); } }} className="w-full flex items-center gap-3 text-left rounded-xl hover:bg-white/5">
              <div className="relative w-14 h-14 rounded-full bg-gradient-to-br from-xynk-lime to-xynk-mint flex items-center justify-center">
                <span className="text-2xl font-bold text-xynk-ink">{displayName.charAt(0).toUpperCase()}</span>
              </div>
              <div className="flex-1">
                <p className="font-bold text-white">{displayName}</p>
                <p className="text-sm text-white/60">@{profile?.username || 'member'} · Signed in</p>
              </div>
              <ChevronRight />
            </button>
          </SettingsSection>

          <SettingsToggle
            label="Hide sensitive content"
            icon={SensitivityIcon}
            value={hideSensitiveContent}
            saving={savingProfilePreferences.has('hideSensitiveContent')}
            onChange={setHideSensitiveContent}
          />

          <SettingsSection label="APPEARANCE">
            <button type="button" onClick={() => setAppearanceOpen(true)} className="settings-row w-full flex items-center gap-3 p-3 text-left">
              <Palette size={20} aria-hidden="true" />
              <span className="flex-1"><span className="block font-semibold">Theme &amp; glass finish</span><span className="block text-sm" style={{color:'var(--ui-muted)'}}>{getTheme(themeId).label}</span></span>
              <ChevronRight size={20} aria-hidden="true" />
            </button>
          </SettingsSection>

          {/* Experience */}
          <SettingsSection label="EXPERIENCE">
            <SettingsToggle
              label="Floating video"
              icon={FloatingIcon}
              value={floatingVideo}
              saving={savingProfilePreferences.has('floatingVideo')}
              onChange={v => setProfilePreference('floatingVideo', v)}
            />
            <SettingsToggle
              label="Mute other audio"
              icon={MuteIcon}
              value={muteOtherAudio}
              saving={savingProfilePreferences.has('muteOtherAudio')}
              onChange={v => setProfilePreference('muteOtherAudio', v)}
            />
            <SettingsToggle
              label="Haptic feedback"
              icon={HapticIcon}
              value={hapticFeedback}
              saving={savingProfilePreferences.has('hapticFeedback')}
              onChange={v => setProfilePreference('hapticFeedback', v)}
            />
            <SettingsToggle
              label="Automatic translation"
              icon={TranslateIcon}
              value={autoTranslate}
              saving={savingProfilePreferences.has('autoTranslate')}
              onChange={v => setProfilePreference('autoTranslate', v)}
            />
            <SettingsToggle
              label="Hide location"
              icon={LocationIcon}
              value={hideLocation}
              saving={savingProfilePreferences.has('hideLocation')}
              onChange={v => setProfilePreference('hideLocation', v)}
            />
            <SettingsToggle
              label="Friends-only invitations"
              icon={InviteIcon}
              value={restrictInvites}
              saving={savingProfilePreferences.has('restrictInvites')}
              onChange={v => setProfilePreference('restrictInvites', v)}
            />

            {/* Language */}
            <div className="settings-row flex items-center justify-between p-3 rounded-xl bg-xynk-panelSoft border border-xynk-line">
              <div className="flex items-center gap-3">
                <LangIcon />
                <span className="font-semibold text-white">Language</span>
              </div>
              <select
                aria-label="Language" value={preferredLanguage}
                onChange={e => { void setProfilePreference('preferredLanguage', e.target.value); }}
                className="px-3 py-2 bg-xynk-panel rounded-xl text-sm text-white border border-xynk-line appearance-none cursor-pointer"
              >
                <option value="en">English</option>
                <option value="hi">Hindi</option>
                <option value="es">Spanish</option>
              </select>
            </div>

            {/* Quick reaction */}
            <div className="settings-row flex items-center justify-between p-3 rounded-xl bg-xynk-panelSoft border border-xynk-line">
              <div className="flex items-center gap-3">
                <ReactionIcon />
                <span className="font-semibold text-white">Quick reaction</span>
              </div>
              <select
                aria-label="Quick reaction" value={quickReaction}
                onChange={e => { void setProfilePreference('quickReaction', e.target.value); }}
                className="text-2xl bg-transparent border-none text-white cursor-pointer"
              >
                <option value="❤️">❤️</option>
                <option value="🔥">🔥</option>
                <option value="😂">😂</option>
                <option value="👏">👏</option>
                <option value="😮">😮</option>
              </select>
            </div>
          </SettingsSection>

          {/* Support */}
          <SettingsSection label="SUPPORT & APP">
            <SettingsItem
              icon={PremiumIcon}
              label="Premium"
              description="Plan controls will appear here when enabled"
            />
            <SettingsItem
              icon={HelpIcon}
              label="Help and feedback"
              description="Help centre and diagnostics"
            />
            <SettingsItem
              icon={CodeIcon}
              label="Developer information"
              description="Build and service information"
            />
          </SettingsSection>

          {/* Logout */}
          <button
            onClick={() => { onClose(); void logout(); }}
            className="w-full btn-secondary mt-4"
          >
            <svg className="w-5 h-5 mr-2" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9"/></svg>
            Log out
          </button>
        </div>
      </div>}
    </GlassDialog>
  );
}

function SettingsSection({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div data-settings-section={label}>
      <h3 className="text-xs font-black text-xynk-lime tracking-wider mb-3">{label}</h3>
      <div className="space-y-2">{children}</div>
    </div>
  );
}

function SettingsItem({ icon: Icon, label, description }: { icon: any; label: string; description: string }) {
  return (
    <div className="settings-row settings-info-row flex items-center gap-3 p-3 rounded-xl bg-xynk-panelSoft border border-xynk-line">
      <div className="w-10 h-10 rounded-xl bg-xynk-lime/20 flex items-center justify-center">
        <Icon className="w-5 h-5 text-xynk-lime" />
      </div>
      <div>
        <p className="font-semibold text-white">{label}</p>
        <p className="text-xs text-white/60">{description}</p>
      </div>
    </div>
  );
}

function SettingsToggle({ label, icon: Icon, value, saving, onChange }: { label: string; icon: any; value: boolean; saving: boolean; onChange: (v: boolean) => void }) {
  return (
    <button
      onClick={() => !saving && onChange(!value)}
      disabled={saving}
      role="switch" aria-checked={value} aria-label={label} aria-busy={saving}
      className="settings-row w-full flex items-center justify-between p-3 rounded-xl bg-xynk-panelSoft border border-xynk-line transition-all hover:border-xynk-lime/50 disabled:opacity-50"
    >
      <div className="flex items-center gap-3">
        <Icon className="w-5 h-5 text-xynk-lime" />
        <span className="font-semibold text-white">{label}</span>
      </div>
      {saving ? (
        <div className="flex items-center gap-2 text-xynk-lime text-xs font-bold">
          <svg className="w-4 h-4 animate-spin" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="12" cy="12" r="10" strokeLinecap="round" strokeDasharray="31.4 31.4"/></svg>
          SAVE
        </div>
      ) : (
        <span aria-hidden="true" className="settings-switch" />
      )}
    </button>
  );
}
