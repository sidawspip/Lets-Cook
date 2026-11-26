import { ArrowLeft, Check } from 'lucide-react';
import { themes } from '../../themes/appearance';
import { useUIStore } from '../../stores/uiStore';

export function AppearanceSettings({ onBack }: { onBack: () => void }) {
 const themeId = useUIStore(state => state.themeId);
 const setThemeId = useUIStore(state => state.setThemeId);
 return <div className="appearance-page">
  <header className="dialog-header flex items-center gap-3">
   <button type="button" className="icon-button" aria-label="Back to settings" onClick={onBack}><ArrowLeft size={20}/></button>
   <div><h2 className="text-xl font-black">Appearance</h2><p className="text-sm" style={{color:'var(--ui-muted)'}}>Choose a glass finish. Your selection is saved on this device.</p></div>
  </header>
  <div className="appearance-content">
   <h3 className="text-sm font-bold">Shiny Glass collection</h3>
   <p className="appearance-caption">From your attached CSS reference</p>
   <div className="theme-grid">{themes.slice(0,3).map(renderTheme)}</div>
   <h3 className="text-sm font-bold">Titanium &amp; smoked glass</h3>
   <p className="appearance-caption">All the finishes from our theme previews</p>
   <div className="theme-grid">{themes.slice(3).map(renderTheme)}</div>
   <p className="appearance-caption" role="status">Selected: {themes.find(theme => theme.id === themeId)?.label}</p>
  </div>
 </div>;
 function renderTheme(theme: typeof themes[number]) {
  const selected=theme.id===themeId;
  return <button type="button" key={theme.id} className="theme-option" aria-pressed={selected} onClick={()=>setThemeId(theme.id)}>
   <span className="theme-miniature" aria-hidden="true" style={{background:theme.background,color:theme.text}}>
    <span className="theme-mini-header">XYNK <span style={{background:theme.primary}}/></span>
    <span className="theme-mini-field" style={{background:theme.field,borderColor:theme.line}}/>
    <span className="theme-mini-room" style={{background:theme.card,borderColor:theme.line}}><span style={{background:theme.primary}}/><i/><i/></span>
    <span className="theme-mini-room" style={{background:theme.card,borderColor:theme.line}}><span style={{background:theme.create}}/><i/><i/></span>
   </span>
   <span className="theme-option-label"><span>{theme.label}</span>{selected && <Check size={18} aria-label="Selected"/>}</span>
  </button>;
 }
}
