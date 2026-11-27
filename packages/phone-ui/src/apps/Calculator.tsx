// Calculator (client only): immediate-execution, like a handheld.
import { useCallback, useEffect, useState } from 'react';
import { Ico } from '../icons';
import { cx } from '../ui';

type Op = '+' | '-' | '×' | '÷';
const apply = (a: number, b: number, op: Op) => (op === '+' ? a + b : op === '-' ? a - b : op === '×' ? a * b : b === 0 ? NaN : a / b);
const fmt = (n: number) => {
  if (!Number.isFinite(n)) return 'Error';
  const s = Number(n.toPrecision(10)).toString();
  return s.length > 12 ? n.toExponential(5) : s;
};

export function CalculatorApp() {
  const [disp, setDisp] = useState('0');
  const [acc, setAcc] = useState<number | null>(null);
  const [op, setOp] = useState<Op | null>(null);
  const [fresh, setFresh] = useState(true);

  const digit = useCallback((d: string) => {
    setDisp((x) => (fresh || x === '0' || x === 'Error' ? (d === '.' ? '0.' : d) : d === '.' && x.includes('.') ? x : x.length >= 12 ? x : x + d));
    setFresh(false);
  }, [fresh]);
  const operate = useCallback((next: Op | null) => {
    const cur = Number(disp);
    if (disp === 'Error') return;
    const value = acc !== null && op && !fresh ? apply(acc, cur, op) : cur;
    setDisp(fmt(value));
    setAcc(Number.isFinite(value) ? value : null);
    setOp(next);
    setFresh(true);
  }, [acc, op, disp, fresh]);
  const clear = () => { setDisp('0'); setAcc(null); setOp(null); setFresh(true); };

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (document.activeElement && document.activeElement !== document.body) return;
      if (/^[0-9.]$/.test(e.key)) digit(e.key);
      else if (e.key === '+' || e.key === '-') operate(e.key);
      else if (e.key === '*') operate('×');
      else if (e.key === '/') { e.preventDefault(); operate('÷'); }
      else if (e.key === 'Enter' || e.key === '=') operate(null);
      else if (e.key === 'Backspace') setDisp((x) => (x.length > 1 && !fresh ? x.slice(0, -1) : '0'));
      else if (e.key.toLowerCase() === 'c') clear();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [digit, operate, fresh]);

  const key = (label: string, onClick: () => void, kind = '', active = false) => (
    <button key={label} className={cx("ph-ckey", kind, active && "active")} onClick={onClick}>{label}</button>
  );
  return (
    <div className="ph-app ph-calc">
      <div className="ph-calc-disp" aria-live="polite"><span style={{ fontSize: disp.length > 9 ? '2.6rem' : disp.length > 7 ? '3.2rem' : '4rem' }}>{disp}</span></div>
      <div className="ph-ckeys">
        {key(acc !== null || disp !== '0' ? 'C' : 'AC', clear, 'fn')}
        {key('±', () => setDisp((x) => (x === '0' || x === 'Error' ? x : x.startsWith('-') ? x.slice(1) : `-${x}`)), 'fn')}
        {key('%', () => { setDisp((x) => fmt(Number(x) / 100)); setFresh(true); }, 'fn')}
        {key('÷', () => operate('÷'), 'op', op === '÷' && fresh)}
        {['7', '8', '9'].map((d) => key(d, () => digit(d)))}{key('×', () => operate('×'), 'op', op === '×' && fresh)}
        {['4', '5', '6'].map((d) => key(d, () => digit(d)))}{key('−', () => operate('-'), 'op', op === '-' && fresh)}
        {['1', '2', '3'].map((d) => key(d, () => digit(d)))}{key('+', () => operate('+'), 'op', op === '+' && fresh)}
        {key('0', () => digit('0'), 'zero')}{key('.', () => digit('.'))}{key('=', () => operate(null), 'op')}
      </div>
      <span className="ph-calc-hint"><Ico name="calc" size={12} /> Keyboard works too</span>
    </div>
  );
}
