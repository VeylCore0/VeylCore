import { useEffect, useState } from 'react';
import { AppHeader } from '../App';

type Op = '+' | '-' | '×' | '÷';
const apply = (a: number, b: number, op: Op) => (op === '+' ? a + b : op === '-' ? a - b : op === '×' ? a * b : b === 0 ? NaN : a / b);
const show = (n: number) => {
  if (!Number.isFinite(n)) return 'Error';
  const r = Number.parseFloat(n.toPrecision(12));
  return Math.abs(r) >= 1e12 ? r.toExponential(6) : r.toLocaleString('en-US', { maximumFractionDigits: 10 });
};

/** A plain calculator: chained operations, percent, sign and keyboard input. Runs entirely on the phone. */
export function CalculatorApp() {
  const [display, setDisplay] = useState('0');
  const [acc, setAcc] = useState<number | null>(null);
  const [op, setOp] = useState<Op | null>(null);
  const [fresh, setFresh] = useState(true);
  const value = () => Number(display.replace(/,/g, ''));

  const digit = (d: string) => {
    if (display === 'Error') { setDisplay(d === '.' ? '0.' : d); setFresh(false); return; }
    if (fresh) { setDisplay(d === '.' ? '0.' : d); setFresh(false); return; }
    if (d === '.' && display.includes('.')) return;
    if (display.replace(/[^0-9]/g, '').length >= 12) return;
    setDisplay(display === '0' && d !== '.' ? d : display + d);
  };
  const operator = (o: Op) => {
    const v = value();
    if (acc !== null && op && !fresh) { const r = apply(acc, v, op); setAcc(r); setDisplay(show(r)); } else setAcc(v);
    setOp(o); setFresh(true);
  };
  const equals = () => {
    if (acc === null || !op) return;
    const r = apply(acc, value(), op);
    setDisplay(show(r)); setAcc(null); setOp(null); setFresh(true);
  };
  const clear = () => { setDisplay('0'); setAcc(null); setOp(null); setFresh(true); };
  const sign = () => setDisplay(show(-value()));
  const percent = () => setDisplay(show(acc !== null && op && (op === '+' || op === '-') ? (acc * value()) / 100 : value() / 100));

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (/^[0-9.]$/.test(e.key)) digit(e.key);
      else if (e.key === '+' || e.key === '-') operator(e.key);
      else if (e.key === '*') operator('×');
      else if (e.key === '/') { e.preventDefault(); operator('÷'); }
      else if (e.key === 'Enter' || e.key === '=') equals();
      else if (e.key === 'Backspace') { e.preventDefault(); setDisplay((d) => (d.length > 1 && !fresh ? d.slice(0, -1) : '0')); }
      else if (e.key.toLowerCase() === 'c') clear();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  });

  const K = ({ label, onClick, kind = '' }: { label: string; onClick: () => void; kind?: string }) => <button className={`ca-key ${kind}${op === label && fresh ? ' active' : ''}`} onClick={onClick}>{label}</button>;
  return (
    <div className="ph-appview ca">
      <AppHeader title="Calculator" />
      <div className="ca-screen"><div className="ca-expr">{acc !== null && op ? `${show(acc)} ${op}` : ''}</div><div className="ca-value" aria-live="polite">{display}</div></div>
      <div className="ca-keys">
        <K label={acc === null && display === '0' ? 'AC' : 'C'} onClick={clear} kind="fn" /><K label="±" onClick={sign} kind="fn" /><K label="%" onClick={percent} kind="fn" /><K label="÷" onClick={() => operator('÷')} kind="op" />
        <K label="7" onClick={() => digit('7')} /><K label="8" onClick={() => digit('8')} /><K label="9" onClick={() => digit('9')} /><K label="×" onClick={() => operator('×')} kind="op" />
        <K label="4" onClick={() => digit('4')} /><K label="5" onClick={() => digit('5')} /><K label="6" onClick={() => digit('6')} /><K label="-" onClick={() => operator('-')} kind="op" />
        <K label="1" onClick={() => digit('1')} /><K label="2" onClick={() => digit('2')} /><K label="3" onClick={() => digit('3')} /><K label="+" onClick={() => operator('+')} kind="op" />
        <K label="0" onClick={() => digit('0')} kind="zero" /><K label="." onClick={() => digit('.')} /><K label="=" onClick={equals} kind="op" />
      </div>
    </div>
  );
}
