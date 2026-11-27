// The in-call screen: incoming (answer / decline), outgoing and connected. State comes only from the server's `call` push.
import { useEffect, useState } from 'react';
import { answerCall, declineCall, endCall, openApp } from './controller';
import { duration, nowSec } from './format';
import { Ico } from './icons';
import { useBack } from './nav';
import { setState, useStore } from './store';
import { Avatar, cx } from './ui';

const REASON: Record<string, string> = {
  hangup: 'Call ended', declined: 'Declined', timeout: 'No answer', cancelled: 'Cancelled', busy: 'Line busy',
  unavailable: 'Not available', dropped: 'Call dropped', voice_failed: 'Could not connect',
};

export function useSecondTick(active: boolean) {
  const [, force] = useState(0);
  useEffect(() => {
    if (!active) return;
    const t = window.setInterval(() => force((n) => n + 1), 1000);
    return () => window.clearInterval(t);
  }, [active]);
}

export function CallScreen() {
  const call = useStore((s) => s.call);
  const min = useStore((s) => s.callMin);
  const shown = !!call && !min;
  useSecondTick(!!call && call.state === 'connected');
  useBack(shown, () => { if (call && call.state !== 'incoming') { setState({ callMin: true }); return true; } return false; });
  if (!call) return <div className="ph-call" aria-hidden="true" />;

  const name = call.peer.display;
  const unknown = /^\d{3}-\d{4}$/.test(name);
  const status = call.state === 'incoming' ? 'incoming call' : call.state === 'outgoing' ? 'calling...'
    : call.state === 'connected' ? duration(nowSec() - (call.answeredAt ?? call.startedAt)) : REASON[call.reason ?? ''] ?? 'Call ended';
  const ringing = call.state === 'incoming' || call.state === 'outgoing';

  return (
    <div className={cx('ph-call', shown && 'show', call.state)} aria-hidden={!shown}>
      <div className="ph-call-bg" />
      <div className="ph-call-body">
        <div className={cx('ph-call-avatar', ringing && 'ph-ringing')}><i /><i /><Avatar name={unknown ? '' : name} id={call.peer.number} size={116} /></div>
        <h2>{name}</h2>
        {!unknown && <div className="ph-call-num">{call.peer.number.replace(/^(\d{3})(\d{4})$/, '$1-$2')}</div>}
        <div className="ph-call-status">{status}</div>
      </div>
      <div className="ph-call-actions">
        {call.state === 'incoming' ? (
          <div className="ph-call-big">
            <div><button className="ph-cbtn cb-red" onClick={declineCall} aria-label="Decline"><Ico name="phone" size={28} style={{ transform: 'rotate(135deg)' }} /></button><span>Decline</span></div>
            <div><button className="ph-cbtn cb-green" onClick={answerCall} aria-label="Answer"><Ico name="phone" size={28} /></button><span>Answer</span></div>
          </div>
        ) : (
          <>
            {call.state !== 'ended' && (
              <div className="ph-call-small">
                <div><button className="ph-cbtn cb-glass" onClick={() => { setState({ callMin: true }); openApp('messages', `to/${call.peer.number}`); }} aria-label="Message"><Ico name="chat" size={22} /></button><span>Message</span></div>
                {unknown && <div><button className="ph-cbtn cb-glass" onClick={() => { setState({ callMin: true }); openApp('contacts', `new/${call.peer.number}`); }} aria-label="Add contact"><Ico name="userplus" size={22} /></button><span>Add contact</span></div>}
                <div><button className="ph-cbtn cb-glass" onClick={() => setState({ callMin: true })} aria-label="Minimise"><Ico name="down" size={22} /></button><span>Minimise</span></div>
              </div>
            )}
            {call.state !== 'ended' && (
              <div className="ph-call-big single">
                <div><button className="ph-cbtn cb-red" onClick={endCall} aria-label={call.state === 'outgoing' ? 'Cancel' : 'End call'}><Ico name="phone" size={28} style={{ transform: 'rotate(135deg)' }} /></button><span>{call.state === 'outgoing' ? 'Cancel' : 'End'}</span></div>
              </div>
            )}
          </>
        )}
      </div>
    </div>
  );
}
