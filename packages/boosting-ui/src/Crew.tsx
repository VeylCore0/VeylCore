import { useCallback, useEffect, useState } from 'react';
import type { Ctx } from './ctx';
import { Button, Confirm, Empty, Ico, ago, api } from './ui';

interface Nearby { id: number; name: string }

export function Crew({ c }: { c: Ctx }) {
  const crew = c.s.crew;
  const [nearby, setNearby] = useState<Nearby[] | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [kick, setKick] = useState<{ id: string; name: string } | null>(null);
  const canInvite = !crew || (crew.leader && !crew.locked && crew.members.length < crew.max);

  const scan = useCallback(async () => {
    setNearby(null); setErr(null);
    const r = await api<Nearby[]>('crewNearby');
    if (r.ok) setNearby(r.data ?? []); else setErr(r.message ?? 'Could not look around');
  }, []);
  useEffect(() => { if (canInvite) void scan(); }, [canInvite, scan]);

  return (
    <div className="bst-page">
      <div className="bst-page-head"><div><h2>Crew Management</h2><p>Crews take group contracts together. Only the leader can take contracts and invite.</p></div></div>

      {c.s.invite && (
        <div className="bst-invite">
          <Ico name="crew" size={22} />
          <span><strong>{c.s.invite.from}</strong> invited you to their crew.</span>
          <Button kind="ghost" onClick={() => void c.run('crewAnswer', false)}>Decline</Button>
          <Button kind="primary" onClick={() => void c.run('crewAnswer', true)}>Join</Button>
        </div>
      )}

      <div className="bst-crew-grid">
        <section className="bst-panel">
          <h4 className="bst-h"><Ico name="crew" size={16} />YOUR CREW {crew && <span className="bst-count">{crew.members.length}/{crew.max}</span>}</h4>
          {!crew ? <Empty icon="crew" title="You are not in a crew" text="Invite a nearby player to form one." /> : (
            <ul className="bst-members big">
              {crew.members.map((m) => (
                <li key={m.id} className={m.online ? '' : 'off'}>
                  <span className="bst-av">{m.leader ? <Ico name="crown" size={16} /> : <Ico name="user" size={16} />}</span>
                  <span className="bst-m-name"><strong>{m.name}{m.me ? ' (you)' : ''}</strong><em>{m.leader ? 'Leader' : 'Member'}{m.online ? '' : ' · offline'}</em></span>
                  {crew.leader && !m.me && (
                    <span className="bst-m-actions">
                      <Button kind="ghost" onClick={() => void c.run('crewLead', m.id)}>Make leader</Button>
                      <Button kind="danger" onClick={() => setKick({ id: m.id, name: m.name })} disabled={crew.locked}>Remove</Button>
                    </span>
                  )}
                </li>
              ))}
            </ul>
          )}
          {crew && <Button kind="ghost" onClick={() => void c.run('crewLeave')} disabled={c.busy}>Leave crew</Button>}
          {crew?.locked && <p className="bst-mute">The contract has started, so the crew is locked.</p>}
        </section>

        <section className="bst-panel">
          <h4 className="bst-h"><Ico name="plus" size={16} />INVITE NEARBY <button className="bst-icon" onClick={() => void scan()} aria-label="Look again"><Ico name="refresh" size={14} /></button></h4>
          {!canInvite ? <p className="bst-mute">{crew && !crew.leader ? 'Only the leader can invite.' : crew?.locked ? 'The crew is locked.' : 'The crew is full.'}</p>
            : err ? <p className="bst-mute">{err}</p>
            : nearby === null ? <p className="bst-mute">Looking around...</p>
            : nearby.length === 0 ? <Empty icon="user" title="Nobody close by" text="Players within a few metres show up here." />
            : (
              <ul className="bst-members big">
                {nearby.map((n) => (
                  <li key={n.id}><span className="bst-av"><Ico name="user" size={16} /></span><span className="bst-m-name"><strong>{n.name}</strong><em>Nearby</em></span>
                    <Button kind="primary" onClick={async () => { await c.run('crewInvite', n.id); void scan(); }}>Invite</Button></li>
                ))}
              </ul>
            )}
        </section>
      </div>

      <section className="bst-panel">
        <h4 className="bst-h"><Ico name="clock" size={16} />CREW ACTIVITY</h4>
        {!crew || crew.log.length === 0 ? <p className="bst-mute">Nothing yet.</p> : (
          <ul className="bst-log">{crew.log.slice(0, 8).map((l, i) => <li key={i}><span>{l.text}</span><time>{ago(l.at, c.s.serverTime)}</time></li>)}</ul>
        )}
      </section>
      {kick && <Confirm danger title={`Remove ${kick.name}?`} text="They leave the crew and any contract it has." confirm="Remove" onCancel={() => setKick(null)} onConfirm={() => { const k = kick; setKick(null); void c.run('crewKick', k.id); }} />}
    </div>
  );
}
