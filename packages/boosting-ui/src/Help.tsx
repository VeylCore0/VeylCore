import type { Ctx } from './ctx';
import { Ico } from './ui';

export function Help({ c }: { c: Ctx }) {
  const ui = c.s.ui;
  const steps: [string, string, string][] = [
    ['contracts', 'Take a contract', 'Open Contracts, pick one that matches your rank and press Accept. Solo contracts start straight away; crew contracts wait for the leader.'],
    ['pin', 'Find the vehicle', 'A circle on the map shows the area. The exact spot is up to you. Use the GPS button to mark the area.'],
    ['lock', 'Access it', 'Walk up to the vehicle and use the interaction prompt. Watch the symbols, then repeat the sequence. Three wrong answers fail the attempt and you wait before trying again.'],
    ['car', 'Deliver it', 'Once the vehicle is yours the handoff point is revealed. Drive there, park on the marker, step out and use the prompt.'],
    ['money', 'Get paid', 'Pay depends on the vehicle, how well you handled it and the condition it arrives in. Crews split the pay.'],
  ];
  return (
    <div className="bst-page">
      <div className="bst-page-head"><div><h2>Settings and Help</h2><p>How {ui.Brand.toLowerCase()} works.</p></div></div>
      <ol className="bst-help">
        {steps.map(([icon, title, text], i) => <li key={title}><span><Ico name={icon} size={18} /></span><div><strong>{i + 1}. {title}</strong><em>{text}</em></div></li>)}
      </ol>
      <div className="bst-help-cols">
        <section className="bst-panel">
          <h4 className="bst-h"><Ico name="gear" size={16} />CONTROLS</h4>
          <ul className="bst-keys"><li><kbd>ESC</kbd>Close the tablet or the puzzle</li><li><kbd>1</kbd>–<kbd>6</kbd>Enter a symbol in the puzzle</li><li><kbd>Backspace</kbd>Undo a symbol</li><li><kbd>Enter</kbd>Send your answer</li></ul>
        </section>
        <section className="bst-panel">
          <h4 className="bst-h"><Ico name="help" size={16} />GOOD TO KNOW</h4>
          <ul className="bst-tips">
            <li>Everything here is a fictional game. Your rewards and reputation are decided by the server, not by the tablet.</li>
            <li>Leaving the area, losing the vehicle or running out of time fails the contract.</li>
            <li>Heat rises when you are loud or fail. High heat hides the easy contracts and raises pay.</li>
            {c.s.event && <li><b>An event is running:</b> a special contract is on offer.</li>}
          </ul>
        </section>
      </div>
    </div>
  );
}
