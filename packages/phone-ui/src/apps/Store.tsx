import { useMemo, useState } from 'react';
import { Icon } from '@veyl/ui';
import { api } from '../api';
import { AppHeader, usePhone } from '../App';
import { APP_STYLE, type AppDef } from '../types';

/** App Store: install and remove optional apps. Core apps are listed as built in. */
export function StoreApp() {
  const { session, toast, setAppInstalled, go } = usePhone();
  const [busy, setBusy] = useState<string | null>(null);
  const [detail, setDetail] = useState<AppDef | null>(null);
  const [search, setSearch] = useState('');
  const apps = useMemo(() => session.apps.filter((a) => a.id !== 'store' && (!a.dock || a.description)), [session.apps]);
  const q = search.trim().toLowerCase();
  const shown = apps.filter((a) => !q || a.label.toLowerCase().includes(q) || (a.category ?? '').toLowerCase().includes(q));
  const optional = shown.filter((a) => !a.core);
  const categories = [...new Set(optional.map((a) => a.category ?? 'Other'))];

  const toggle = async (a: AppDef) => {
    if (busy) return;
    setBusy(a.id);
    const on = !a.installed;
    const r = await api<{ installed: string[] }>('appInstall', a.id, on);
    setBusy(null);
    if (!r.ok) { toast(r.message ?? 'Could not change the app', 'error'); return; }
    setAppInstalled(a.id, on);
    setDetail((d) => (d && d.id === a.id ? { ...d, installed: on } : d));
    toast(r.message ?? (on ? 'Installed' : 'Removed'));
  };

  const Btn = ({ a }: { a: AppDef }) => (
    <button className={`ph-btn store-btn${a.installed ? '' : ' primary'}`} disabled={busy !== null} onClick={(e) => { e.stopPropagation(); void toggle(a); }}>
      {busy === a.id ? '…' : a.installed ? 'Remove' : 'Get'}
    </button>
  );

  if (detail) {
    const a = session.apps.find((x) => x.id === detail.id) ?? detail;
    const st = APP_STYLE[a.id] ?? { icon: 'box', color: '#3a3346' };
    return (
      <div className="ph-appview">
        <AppHeader title="" onBack={() => setDetail(null)} />
        <div className="ph-body store-detail">
          <div className="store-hero">
            <span className="store-icon lg" style={{ background: st.color }}><Icon name={st.icon} size="2rem" /></span>
            <div>
              <div className="store-name">{a.label}</div>
              <div className="muted">{a.category ?? 'App'}</div>
              <div className="store-actions">
                <Btn a={a} />
                {a.installed && <button className="ph-btn" onClick={() => go(a.id)}>Open</button>}
              </div>
            </div>
          </div>
          <p className="store-desc">{a.description ?? 'No description.'}</p>
          <div className="store-facts">
            <div><span className="muted">Made by</span>VeylCore</div>
            <div><span className="muted">Price</span>Free</div>
            <div><span className="muted">Data</span>Saved to your character</div>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="ph-appview">
      <AppHeader title="App Store" />
      <div className="ph-body">
        <label className="ph-search store-search"><Icon name="search" size="0.9rem" /><input placeholder="Search apps" value={search} onChange={(e) => setSearch(e.target.value)} /></label>
        {optional.length === 0 && <div className="ph-empty">No apps match “{search}”.</div>}
        {categories.map((cat) => (
          <div key={cat}>
            <div className="ph-section">{cat}</div>
            <ul className="ph-list">
              {optional.filter((a) => (a.category ?? 'Other') === cat).map((a) => {
                const st = APP_STYLE[a.id] ?? { icon: 'box', color: '#3a3346' };
                return (
                  <li key={a.id}>
                    <div className="ph-row store-row" role="button" tabIndex={0} onClick={() => setDetail(a)} onKeyDown={(e) => { if (e.key === 'Enter') setDetail(a); }}>
                      <span className="store-icon" style={{ background: st.color }}><Icon name={st.icon} size="1.2rem" /></span>
                      <span className="ph-row-main"><strong>{a.label}</strong><span className="muted store-sub">{a.description}</span></span>
                      <Btn a={a} />
                    </div>
                  </li>
                );
              })}
            </ul>
          </div>
        ))}
        {!q && (
          <>
            <div className="ph-section">Built in</div>
            <div className="store-builtin">
              {session.apps.filter((a) => a.core).map((a) => {
                const st = APP_STYLE[a.id] ?? { icon: 'box', color: '#3a3346' };
                return <span key={a.id} className="store-chip"><span className="store-icon xs" style={{ background: st.color }}><Icon name={st.icon} size="0.75rem" /></span>{a.label}</span>;
              })}
            </div>
          </>
        )}
      </div>
    </div>
  );
}
