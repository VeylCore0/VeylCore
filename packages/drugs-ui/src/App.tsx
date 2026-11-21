import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Icon, KeyBadge, SearchBox, StateView, VMark, announceReady, nui, useNuiMessage } from '@veyl/ui';
import { CONTAINERS, STAGES, eta, needs, type EquipmentView, type JournalData, type PlacementState, type PlantView } from './types';
import { Equipment } from './Equipment';

const REDUCED_KEY = 'veyl_drugs.reducedMotion';

function useReducedMotion(): [boolean, (v: boolean) => void] {
  const [on, setOn] = useState(() => { try { return localStorage.getItem(REDUCED_KEY) === '1'; } catch { return false; } });
  useEffect(() => { document.documentElement.classList.toggle('dr-reduced', on); }, [on]);
  return [on, (v: boolean) => { setOn(v); try { localStorage.setItem(REDUCED_KEY, v ? '1' : '0'); } catch { /* storage unavailable */ } }];
}

export function App() {
  const [placement, setPlacement] = useState<PlacementState | null>(null);
  const [card, setCard] = useState<PlantView | null>(null);
  const [journal, setJournal] = useState<JournalData | null>(null);
  const [equipment, setEquipment] = useState<EquipmentView | null>(null);
  const reduced = useReducedMotion();

  useEffect(() => announceReady(), []);
  useNuiMessage<PlacementState>('drugs:placement', (d) => setPlacement(d && d.visible ? d : null));
  useNuiMessage<PlantView | null>('drugs:card', (d) => setCard(d ?? null));
  useNuiMessage<JournalData>('drugs:journal', (d) => { setEquipment(null); setJournal(d); });
  useNuiMessage<EquipmentView>('drugs:equipment', (d) => { setJournal(null); setEquipment(d); });
  useNuiMessage('drugs:close', () => { setJournal(null); setEquipment(null); });

  return (
    <>
      {placement && <PlacementHint s={placement} />}
      {card && !journal && !equipment && <PlantCard p={card} />}
      {equipment && <Equipment data={equipment} onData={setEquipment} />}
      {journal && <Journal data={journal} onData={setJournal} reduced={reduced} />}
    </>
  );
}

// ---------------------------------------------------------------------------
// Placement hint (passive)
// ---------------------------------------------------------------------------
function PlacementHint({ s }: { s: PlacementState }) {
  return (
    <div className="dr-place" role="status">
      <div className={`dr-place-status ${s.valid ? 'ok' : 'bad'}`}>
        <Icon name={s.valid ? 'check' : 'alert'} size="1rem" />
        <span>{s.valid ? `${s.label} · ${CONTAINERS[s.container ?? 'ground']}` : s.reason}</span>
      </div>
      <div className="dr-place-keys">
        <span><KeyBadge>E</KeyBadge> Place</span>
        <span><KeyBadge>R</KeyBadge> Rotate</span>
        {s.canToggle && <span><KeyBadge>G</KeyBadge> {s.container === 'pot' ? 'Use ground' : 'Use pot'}</span>}
        <span><KeyBadge>Esc</KeyBadge> Cancel</span>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Plant card (passive, compact)
// ---------------------------------------------------------------------------
function Meter({ label, value, icon }: { label: string; value: number; icon: string }) {
  const tone = value <= 15 ? 'bad' : value < 40 ? 'warn' : '';
  return (
    <div className={`dr-meter ${tone}`}>
      <span className="lbl"><Icon name={icon} size="0.85rem" /> {label}</span>
      <div className="track" role="progressbar" aria-label={label} aria-valuenow={value} aria-valuemin={0} aria-valuemax={100}><span style={{ width: `${value}%` }} /></div>
      <span className="val">{value}%</span>
    </div>
  );
}

function GradeBadge({ grade, id }: { grade?: string; id?: string }) {
  if (!grade) return null;
  return <span className={`dr-grade ${id ?? ''}`}><Icon name="sparkle" size="0.75rem" /> {grade}</span>;
}

function PlantCard({ p }: { p: PlantView }) {
  if (!p.own) {
    return (
      <div className="dr-card" role="status">
        <div className="dr-card-head"><Icon name="leaf" size="1.2rem" /><div><div className="dr-card-title">{p.typeLabel}</div><div className="v-muted">{STAGES[p.stage - 1]}</div></div></div>
        <div className="v-muted dr-card-note">You don't know who tends this plant.</div>
      </div>
    );
  }
  const n = needs(p);
  return (
    <div className="dr-card" role="status">
      <div className="dr-card-head">
        <Icon name="leaf" size="1.2rem" />
        <div>
          <div className="dr-card-title">{p.varietyLabel}</div>
          <div className="v-muted">{p.typeLabel} · {STAGES[p.stage - 1]}</div>
        </div>
        <GradeBadge grade={p.grade} id={p.gradeId} />
      </div>
      <Meter label="Growth" value={p.growth ?? 0} icon="clock" />
      <Meter label="Water" value={p.water ?? 0} icon="drop" />
      <Meter label="Care" value={p.care ?? 0} icon="heart" />
      <Meter label="Health" value={p.health ?? 0} icon="shield" />
      <div className={`dr-need ${n.tone}`}>{n.text}{!p.ready && <span className="v-muted"> · {eta(p.etaMinutes)} left</span>}</div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Grow journal (modal tablet)
// ---------------------------------------------------------------------------
type Filter = 'all' | 'ready' | 'attention';

function Journal({ data, onData, reduced }: { data: JournalData; onData: (d: JournalData) => void; reduced: [boolean, (v: boolean) => void] }) {
  const [filter, setFilter] = useState<Filter>('all');
  const [search, setSearch] = useState('');
  const [selected, setSelected] = useState<number | null>(data.plants[0]?.id ?? null);
  const [status, setStatus] = useState<{ kind: 'idle' | 'loading' | 'error'; message?: string }>({ kind: 'idle' });
  const [toast, setToast] = useState<string | null>(null);
  const [settings, setSettings] = useState(false);
  const listRef = useRef<HTMLDivElement>(null);
  const close = useCallback(() => { void nui('close'); }, []);

  const refresh = useCallback(async () => {
    setStatus({ kind: 'loading' });
    const res = await nui<JournalData>('refresh');
    if (res.ok && res.data) { onData(res.data); setStatus({ kind: 'idle' }); } else setStatus({ kind: 'error', message: res.message ?? 'Could not refresh' });
  }, [onData]);

  const plants = useMemo(() => {
    const q = search.trim().toLowerCase();
    return data.plants.filter((p) => (filter === 'all' || (filter === 'ready' ? p.ready : needs(p).tone === 'bad' || needs(p).tone === 'warn'))
      && (!q || `${p.varietyLabel} ${p.typeLabel} ${p.area ?? ''} ${p.street ?? ''}`.toLowerCase().includes(q)));
  }, [data.plants, filter, search]);
  const sel = data.plants.find((p) => p.id === selected) ?? null;
  const attention = data.plants.filter((p) => ['bad', 'warn'].includes(needs(p).tone)).length;

  useEffect(() => {
    // Only text fields swallow keys; checkboxes and buttons don't.
    const typing = (t: EventTarget | null) => t instanceof HTMLInputElement && !['checkbox', 'radio', 'range', 'button'].includes(t.type);
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') { if (typing(e.target)) (e.target as HTMLElement).blur(); else if (settings) setSettings(false); else close(); return; }
      if (typing(e.target)) return;
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        e.preventDefault();
        const i = plants.findIndex((p) => p.id === selected);
        const next = plants[Math.max(0, Math.min(plants.length - 1, i + (e.key === 'ArrowDown' ? 1 : -1)))];
        if (next) setSelected(next.id);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [plants, selected, close, settings]);

  const waypoint = async (id: number) => {
    const res = await nui('waypoint', { id });
    setToast(res.ok ? 'Waypoint set on your map' : res.message ?? 'Could not set waypoint');
    window.setTimeout(() => setToast(null), 2500);
  };

  return (
    <div className="dr-journal-wrap">
      <div className="dr-tablet" role="dialog" aria-label="Grow Journal">
        <nav className="dr-rail" aria-label="Sections">
          <VMark size="1.8rem" />
          <button className="dr-rail-btn on" aria-current="page" title="Plants"><Icon name="leaf" size="1.3rem" /></button>
          <button className={`dr-rail-btn${settings ? ' on' : ''}`} title="Settings" onClick={() => setSettings((s) => !s)}><Icon name="gear" size="1.3rem" /></button>
          <button className="dr-rail-btn dr-rail-close" title="Close (Esc)" onClick={close}><Icon name="close" size="1.2rem" /></button>
        </nav>
        <main className="dr-main">
          <header className="dr-head">
            <div>
              <div className="dr-title">Your operation</div>
              <div className="v-muted">{data.stats.plants} of {data.stats.limit} plants tended</div>
            </div>
            <button className="v-btn" onClick={() => void refresh()} disabled={status.kind === 'loading'}><Icon name="reset" size="1rem" /> {status.kind === 'loading' ? 'Refreshing…' : 'Refresh'}</button>
          </header>

          {settings ? (
            <section className="dr-settings">
              <div className="dr-section-title">Settings</div>
              <label className="dr-toggle">
                <input type="checkbox" checked={reduced[0]} onChange={(e) => reduced[1](e.target.checked)} />
                <span>Reduce motion (no animated bars or transitions)</span>
              </label>
            </section>
          ) : (
            <>
              <div className="dr-stats">
                <div className="dr-stat"><Icon name="leaf" size="1.4rem" /><div><strong>{data.stats.plants}</strong><span>Plants</span></div></div>
                <div className="dr-stat"><Icon name="check" size="1.4rem" /><div><strong>{data.stats.ready}</strong><span>Ready</span></div></div>
                <div className="dr-stat"><Icon name="alert" size="1.4rem" /><div><strong>{attention}</strong><span>Need attention</span></div></div>
                <div className="dr-stat"><Icon name="pin" size="1.4rem" /><div><strong>{data.stats.locations}</strong><span>Locations</span></div></div>
              </div>
              <div className="dr-toolbar">
                <div className="v-tabs" role="tablist">
                  {(['all', 'ready', 'attention'] as Filter[]).map((f) => (
                    <button key={f} role="tab" aria-selected={filter === f} className={`v-tab${filter === f ? ' active' : ''}`} onClick={() => setFilter(f)}>
                      {f === 'all' ? 'All' : f === 'ready' ? 'Ready' : 'Needs attention'}
                    </button>
                  ))}
                </div>
                <div className="dr-search"><SearchBox value={search} onChange={setSearch} placeholder="Search variety or area…" /></div>
              </div>
              {status.kind === 'error' && <div className="dr-error" role="alert"><Icon name="alert" size="1rem" /> {status.message}</div>}
              <div className="dr-body">
                <div className="dr-list v-scroll" ref={listRef}>
                  {data.plants.length === 0 && <StateView kind="empty" message="No plants yet. Use a seed from your inventory to plant one." />}
                  {data.plants.length > 0 && plants.length === 0 && <StateView kind="empty" message="Nothing matches this filter." />}
                  {plants.map((p) => {
                    const n = needs(p);
                    return (
                      <button key={p.id} className={`dr-row${p.id === selected ? ' on' : ''}`} onClick={() => setSelected(p.id)}>
                        <span className={`dr-row-icon ${p.type}`}><Icon name="leaf" size="1.3rem" /></span>
                        <span className="dr-row-main">
                          <span className="dr-row-name">{p.varietyLabel} <GradeBadge grade={p.grade} id={p.gradeId} /></span>
                          <span className="v-muted dr-row-sub">{p.typeLabel} · {p.area ?? 'Unknown area'}</span>
                        </span>
                        <span className="dr-row-growth">
                          <span className="v-muted">Growth</span>
                          <span className="track"><span style={{ width: `${p.growth}%` }} /></span>
                          <span>{p.growth}%</span>
                        </span>
                        <span className={`dr-chip ${n.tone}`}>{n.tone === 'ready' ? 'Ready' : n.tone === 'ok' ? 'Growing' : n.tone === 'warn' ? 'Check' : 'Urgent'}</span>
                      </button>
                    );
                  })}
                </div>
                <aside className="dr-detail">
                  {!sel ? <div className="v-muted dr-detail-empty">Select a plant to see its details.</div> : (
                    <>
                      <div className="dr-detail-head">
                        <div>
                          <div className="dr-detail-title">{sel.varietyLabel}</div>
                          <div className="v-muted">{sel.typeLabel} · {CONTAINERS[sel.container ?? 'ground']}</div>
                        </div>
                        <GradeBadge grade={sel.grade} id={sel.gradeId} />
                      </div>
                      <button className="v-btn dr-waypoint" onClick={() => void waypoint(sel.id)}><Icon name="pin" size="1rem" /> Set waypoint</button>
                      {sel.trait && <div className="dr-trait"><Icon name="dna" size="0.9rem" /> {sel.trait}</div>}
                      <Meter label="Growth" value={sel.growth ?? 0} icon="clock" />
                      <Meter label="Water" value={sel.water ?? 0} icon="drop" />
                      <Meter label="Care" value={sel.care ?? 0} icon="heart" />
                      <Meter label="Health" value={sel.health ?? 0} icon="shield" />
                      <dl className="dr-facts">
                        <div><dt>Stage</dt><dd>{STAGES[sel.stage - 1]}</dd></div>
                        <div><dt>Time left</dt><dd>{eta(sel.etaMinutes)}</dd></div>
                        <div><dt>Expected yield</dt><dd>{sel.expectedYield}</dd></div>
                        <div><dt>Quality now</dt><dd>{sel.quality} / 100</dd></div>
                        <div><dt>Location</dt><dd>{[sel.street, sel.area].filter(Boolean).join(', ') || 'Unknown'}</dd></div>
                      </dl>
                      <div className={`dr-need ${needs(sel).tone}`}>{needs(sel).text}</div>
                      <p className="v-muted dr-hint">Care for plants in person: water and nutrients keep quality up. The journal can't tend plants remotely.</p>
                    </>
                  )}
                </aside>
              </div>
            </>
          )}
        </main>
      </div>
      {toast && <div className="v-toast-inline success" role="status"><Icon name="check" size="1rem" />{toast}</div>}
    </div>
  );
}
