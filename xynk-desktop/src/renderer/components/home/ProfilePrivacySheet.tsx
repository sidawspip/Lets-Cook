import { Search, Users } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { useWatchPartyStore } from '../../stores/watchPartyStore';
import { _time, _timeDetailed, _providerLabel, _publicDisplayName, _publicHandle } from '../../lib/formatters';

export function ProfilePrivacySheet({ onClose }: { onClose: () => void }) {
  const navigate = useNavigate();
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
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center p-4">
      <div className="fixed inset-0 bg-black/60" onClick={onClose} />
      <div className="relative w-full max-w-2xl max-h-[90vh] bg-xynk-panel rounded-3xl overflow-hidden flex flex-col animate-slide-up">
        {/* Header */}
        <div className="flex items-center justify-between p-4 border-b border-xynk-line">
          <div>
            <h2 className="text-xl font-black text-white">Settings</h2>
            <p className="text-sm text-white/60">Privacy, playback and social preferences</p>
          </div>
          <button onClick={onClose} className="p-2 rounded-xl hover:bg-white/10 transition-colors">
            <svg className="w-6 h-6 text-white" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M18 6L6 18M6 6l12 12"/></svg>
          </button>
        </div>

        {/* Content */}
        <div className="flex-1 overflow-y-auto p-4 space-y-6">
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
            <div className="flex items-center justify-between p-3 rounded-xl bg-xynk-panelSoft border border-xynk-line">
              <div className="flex items-center gap-3">
                <LangIcon />
                <span className="font-semibold text-white">Language</span>
              </div>
              <select
                value={preferredLanguage}
                onChange={e => { void setProfilePreference('preferredLanguage', e.target.value); }}
                className="px-3 py-2 bg-xynk-panel rounded-xl text-sm text-white border border-xynk-line appearance-none cursor-pointer"
              >
                <option value="en">English</option>
                <option value="hi">Hindi</option>
                <option value="es">Spanish</option>
              </select>
            </div>

            {/* Quick reaction */}
            <div className="flex items-center justify-between p-3 rounded-xl bg-xynk-panelSoft border border-xynk-line">
              <div className="flex items-center gap-3">
                <ReactionIcon />
                <span className="font-semibold text-white">Quick reaction</span>
              </div>
              <select
                value={quickReaction}
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
      </div>
    </div>
  );
}

function SettingsSection({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <h3 className="text-xs font-black text-xynk-lime tracking-wider mb-3">{label}</h3>
      <div className="space-y-2">{children}</div>
    </div>
  );
}

function SettingsItem({ icon: Icon, label, description }: { icon: any; label: string; description: string }) {
  return (
    <div className="flex items-center gap-3 p-3 rounded-xl bg-xynk-panelSoft border border-xynk-line">
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
      className="w-full flex items-center justify-between p-3 rounded-xl bg-xynk-panelSoft border border-xynk-line transition-all hover:border-xynk-lime/50 disabled:opacity-50"
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
        <input
          type="checkbox"
          checked={value}
          onChange={e => !saving && onChange(e.target.checked)}
          className="w-10 h-6 appearance-none bg-white/10 rounded-full relative"
          style={{
            backgroundImage: `linear-gradient(to right, ${value ? '#FF5D83' : '#73D8FF'}, ${value ? '#FF5D83' : '#73D8FF'})`,
            borderRadius: '9999px',
          }}
        />
      )}
    </button>
  );
}

// Icons
function SensitivityIcon() { return <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-4.47 0-8.26-3.62-9-8.23M1 1l22 22"/></svg> }
function FloatingIcon() { return <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><rect x="2" y="2" width="20" height="20" rx="2" /><path d="M9 18h12a2 2 0 0 0 0-4h-12"/></svg> }
function MuteIcon() { return <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/></svg> }
function HapticIcon() { return <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M12 2a10 10 0 0 0-10 10c0 4.42 3.58 8 8 8s8-3.58 8-8a10 10 0 0 0-8-10z"/><path d="M12 6v6l4 2"/></svg> }
function TranslateIcon() { return <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M18 13v6a2 2 0 0 1-2 2h-8a2 2 0 0 1-2-2v-6"/><path d="M18 13v-6a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v6"/></svg> }
function LocationIcon() { return <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"/><circle cx="12" cy="10" r="3"/></svg> }
function InviteIcon() { return <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg> }
function PremiumIcon() { return <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M12 17v4M9 12h6M12 22s5-3 5-9-5-9-5-9"/><path d="M5 17h14"/></svg> }
function HelpIcon() { return <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="12" cy="12" r="10"/><path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3"/><path d="M12 17h.01"/></svg> }
function CodeIcon() { return <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><polyline points="16 18 22 12 16 6"/><polyline points="8 6 2 12 8 18"/></svg> }
function LangIcon() { return <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M5 8l6 6"/><path d="M4 14l6-6"/><path d="M2 5h12"/><path d="M7 19h10"/></svg> }
function ReactionIcon() { return <svg className="w-5 h-5" viewBox="0 0 24 24" fill="currentColor"><path d="M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 10.54L12 21.35z"/></svg> }


function ChevronRight() {
  return <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M9 18l6-6-6-6"/></svg>;
}

function SettingsIcon() {
  return <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1 0 2.83 2 2 0 0 1-2.83 0l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 1-1.82.33l-.06.06a2 2 0 0 1-2.83 0 2 2 0 0 1-2.83 0l-.06-.06a1.65 1.65 0 0 1-1.82-.33 1.65 1.65 0 0 1-1.82-.33l-.06-.06a2 2 0 0 1 0-2.83 2 2 0 0 1 2.83 0l.06-.06a1.65 1.65 0 0 1 1.82-.33H21 12a2 2 0 0 0 2-2V6.83a2 2 0 0 1 .59-1.42l.06-.06a2 2 0 0 1 1.42-.58h.06"/></svg>;
}

function LogoutIcon() {
  return <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9"/></svg>;
}
