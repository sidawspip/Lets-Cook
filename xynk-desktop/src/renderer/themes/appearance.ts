import catalog from './catalog.json';
export const themes = catalog;
export const DEFAULT_THEME = 'neo-purple';
export const THEME_KEY = 'xynk.appearance.theme';
export function getTheme(id: string) { return themes.find(theme => theme.id === id) || themes.find(theme => theme.id === DEFAULT_THEME)!; }
export function readTheme() { try { return getTheme(localStorage.getItem(THEME_KEY) || DEFAULT_THEME).id; } catch { return DEFAULT_THEME; } }
export function applyTheme(id: string) {
 const theme = getTheme(id);
 const shiny = ['neo-purple','aurora-cyan','sunset-amber'].includes(theme.id);
 const accent = theme.primary.match(/#[0-9a-fA-F]{6}/g)?.[1] || '#79d4bc';
 const reflectedAccents: Record<string, [string,string,string]> = {
   'neo-purple': ['#a855ff','#ed94e8','#ffc7ad'],
   'aurora-cyan': ['#00d4ff','#3ff0e0','#8effdd'],
   'sunset-amber': ['#ff9a44','#ff5e95','#ffd166'],
 };
 const vars: Record<string,string> = {'blur':shiny ? (theme.id === 'aurora-cyan' ? '18px' : '20px') : '16px','fill':theme.field,'line-strong':theme.line,'champagne':accent,'iris':accent,'violet':accent,'coral':accent,'jade':accent,'pink':accent,'cyan':accent,'text':theme.text,'muted':theme.muted,'ink':theme.ink,'frame-fill':theme.fill,'line':theme.line,'field-fill':theme.field,'primary':theme.primary,'control':theme.control,'rim':theme.rim,'background':theme.background};
 for (const [key,value] of Object.entries(vars)) document.documentElement.style.setProperty('--ui-'+key,value);
 if (shiny) {
   const [primary, secondary, highlight] = reflectedAccents[theme.id];
   for (const [key,value] of Object.entries({jade:primary,pink:primary,cyan:secondary,iris:secondary,violet:secondary,champagne:highlight,coral:highlight})) {
     document.documentElement.style.setProperty('--ui-'+key,value);
   }
 }
 document.documentElement.dataset.theme = theme.id;
 document.documentElement.classList.toggle('showcase-theme', shiny);
 document.documentElement.style.colorScheme = theme.id === 'pearl-glass' ? 'light' : 'dark';
 let style = document.getElementById('xynk-theme-material');
 if (!style) { style=document.createElement('style');style.id='xynk-theme-material';document.head.appendChild(style); }
 style.textContent = `
 .home-shell{background-color:transparent}
 .room-card{background:${theme.card};border-color:var(--ui-line)}
 .home-create{background:${theme.create};color:var(--ui-ink)}
 :is(.home-shell,.glass-dialog,.glass-drawer,.login-card,.watch-panel,.watch-header,.card,.sidebar-card) .text-white{color:var(--ui-text)}
 :is(.home-shell,.glass-dialog,.glass-drawer,.login-card,.watch-panel,.watch-header,.card,.sidebar-card) [class*="text-white/"]{color:var(--ui-muted)}
 .text-xynk-lime{color:var(--ui-jade)}.text-xynk-mint{color:var(--ui-jade)}
 .text-xynk-text{color:var(--ui-text)}.text-xynk-muted{color:var(--ui-muted)}
 .search-action.icon-button,.watch-tabs button[aria-pressed="true"],.settings-row[aria-checked="true"] .settings-switch{background:var(--ui-primary);color:var(--ui-ink)}
 input::placeholder,textarea::placeholder{color:var(--ui-muted)}

 .room-card,.glass-list-row,.queue-row,.ui4-room{background:${theme.card};border-color:var(--ui-line);backdrop-filter:blur(var(--ui-blur)) saturate(175%)}
 .input-field,.home-search,.friend-search,.chat-input,.ui4-field,.glass-dialog select,.player-main-controls select{backdrop-filter:blur(var(--ui-blur)) saturate(175%)}
 .watch-tabs,.ui4-tabs{background:var(--ui-field-fill)}
 .watch-tabs button,.ui4-tab{color:var(--ui-text)}
 .ui4-tab[aria-pressed='true'],.player-main-controls button:is([aria-label='Play'],[aria-label='Pause']){background:var(--ui-primary);color:var(--ui-ink)}
 .chat-bubble[data-own='true']{background:var(--ui-control),var(--ui-field-fill);border-color:var(--ui-line)}
 .input-field::placeholder,.home-search::placeholder,.friend-search::placeholder,.chat-input::placeholder,.ui4-field::placeholder{color:var(--ui-muted)}
 ${theme.extra || ''}
 @media(prefers-reduced-transparency:reduce){.room-card,.glass-surface,.glass-dialog,.glass-drawer,.watch-panel,.card,.sidebar-card,.input-field,.home-search,.friend-search,.chat-input{backdrop-filter:none;background:color-mix(in srgb,var(--ui-ink) 94%,var(--ui-text))}}
 @media(prefers-reduced-motion:reduce){.theme-option{transition:none}}`;
}
