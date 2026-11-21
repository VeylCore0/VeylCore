import { useCallback, useEffect, useRef, useState } from 'react';
import {
  BrandHeader, CloseHint, Icon, StateView, announceReady, money, newOpId, nui, t, useNuiMessage,
  type BankActivity, type BankHistoryPage, type BankOverview, type RecipientPreview,
} from '@veyl/ui';
import { AmountDialog, ConfirmDialog } from './Dialogs';

type View = 'overview' | 'accounts' | 'transfers' | 'history';
type Toast = { kind: 'error' | 'success'; text: string } | null;

const NAV: { id: View; icon: string }[] = [
  { id: 'overview', icon: 'home' }, { id: 'accounts', icon: 'card' }, { id: 'transfers', icon: 'transfer' }, { id: 'history', icon: 'clock' },
];

/** Whole-dollar amounts only (VeylCore money is integer). Returns the amount or an error message. */
export function parseAmount(raw: string): { ok: true; value: number } | { ok: false; error: string } {
  const s = raw.replace(/[$,\s]/g, '');
  if (s === '') return { ok: false, error: 'Enter an amount' };
  if (!/^\d+(\.0{1,2})?$/.test(s)) return { ok: false, error: /^\d*\.\d+$/.test(s) ? 'Whole dollars only' : 'Enter a valid amount' };
  const n = Number(s);
  if (!Number.isFinite(n) || n <= 0) return { ok: false, error: 'Amount must be more than $0' };
  if (n > 1_000_000) return { ok: false, error: 'Maximum $1,000,000 per transaction' };
  return { ok: true, value: Math.floor(n) };
}

export function activityIcon(a: BankActivity) {
  if (a.icon) return a.icon;
  const r = a.reason.toLowerCase();
  if (r.includes('pay')) return 'briefcase';
  if (r.includes('shop') || r.includes('store') || r.includes('24/7') || r.includes('purchase')) return 'cart';
  if (r.includes('vehicle') || r.includes('fuel')) return 'car';
  if (r.includes('transfer')) return 'transfer';
  return a.delta >= 0 ? 'money' : 'card';
}

export function App() {
  const [open, setOpen] = useState(false);
  const [view, setView] = useState<View>('overview');
  const [data, setData] = useState<BankOverview | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [toast, setToast] = useState<Toast>(null);
  const [amountDialog, setAmountDialog] = useState<'deposit' | 'withdraw' | null>(null);
  const toastTimer = useRef<number>();

  useEffect(() => announceReady(), []);
  const say = useCallback((kind: 'error' | 'success', text: string) => {
    setToast({ kind, text });
    window.clearTimeout(toastTimer.current);
    toastTimer.current = window.setTimeout(() => setToast(null), 3500);
  }, []);

  useNuiMessage<BankOverview | null>('bank:open', (d) => { setOpen(true); setView('overview'); setData(d); setError(null); setAmountDialog(null); });
  useNuiMessage<BankOverview>('bank:overview', (d) => setData(d));
  useNuiMessage<{ message: string }>('bank:error', (d) => setError(d.message));
  useNuiMessage('bank:close', () => setOpen(false));

  const close = useCallback(() => { void nui('close'); }, []);
  const refresh = useCallback(async () => {
    const res = await nui<BankOverview>('overview');
    if (res.ok && res.data) { setData(res.data); setError(null); } else setError(res.message ?? res.code ?? 'Unavailable');
  }, []);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== 'Escape' || amountDialog) return;
      if ((e.target as HTMLElement).tagName === 'INPUT') (e.target as HTMLElement).blur(); else close();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, amountDialog, close]);

  const moveOwn = useCallback(async (kind: 'deposit' | 'withdraw', amount: number, opId: string) => {
    const res = await nui<BankOverview>(kind, { amount, opId });
    if (res.ok) { if (res.data) setData(res.data); say('success', res.message ?? 'Done'); return true; }
    say('error', res.message ?? res.code ?? 'Failed');
    return res.code === 'TIMEOUT' ? 'retry' : false;
  }, [say]);

  if (!open) return null;

  return (
    <div className="bank-root">
      <div className="bank-window v-panel">
        <header className="bank-top">
          <BrandHeader section={t('bank.section')} />
          <CloseHint onClose={close} />
        </header>
        <div className="bank-body">
          <nav className="bank-nav">
            {NAV.map((n) => (
              <button key={n.id} className={`bank-nav-item${view === n.id ? ' active' : ''}`} onClick={() => setView(n.id)} aria-current={view === n.id}>
                <Icon name={n.icon} size="1.15rem" /><span>{t(`bank.${n.id}`)}</span>
              </button>
            ))}
          </nav>
          <section className="bank-content v-scroll">
            {error ? <StateView kind="error" message={error} onRetry={() => void refresh()} />
              : !data ? <StateView kind="loading" />
              : view === 'overview' ? <Overview data={data} onAmount={setAmountDialog} onTransfer={() => setView('transfers')} onViewAll={() => setView('history')} onDone={refresh} say={say} />
              : view === 'accounts' ? <Accounts data={data} />
              : view === 'transfers' ? <div className="bank-narrow"><TransferForm big onDone={refresh} say={say} cash={data.cash} bank={data.bank} /></div>
              : <History />}
          </section>
        </div>
      </div>
      {amountDialog && data && (
        <AmountDialog
          title={t(`bank.${amountDialog}`)} max={amountDialog === 'deposit' ? data.cash : data.bank}
          onCancel={() => setAmountDialog(null)}
          onSubmit={async (amount, opId) => { const r = await moveOwn(amountDialog, amount, opId); if (r === true) setAmountDialog(null); return r; }}
        />
      )}
      {toast && <div className={`v-toast-inline ${toast.kind}`} role="alert"><Icon name={toast.kind === 'error' ? 'alert' : 'check'} size="1rem" />{toast.text}</div>}
    </div>
  );
}

function greeting(hour: number) {
  return hour < 12 ? t('bank.morning') : hour < 18 ? t('bank.afternoon') : t('bank.evening');
}

function Overview({ data, onAmount, onTransfer, onViewAll, onDone, say }: {
  data: BankOverview; onAmount: (k: 'deposit' | 'withdraw') => void; onTransfer: () => void; onViewAll: () => void;
  onDone: () => Promise<void>; say: (k: 'error' | 'success', s: string) => void;
}) {
  return (
    <div className="bank-overview">
      <div className="bank-hero">
        <div className="bank-greeting">{greeting(data.hour)}</div>
        <div className="v-muted">{t('bank.personal')}</div>
        <div className="v-label bank-avail">{t('bank.available')}</div>
        <div className="bank-balance">{money(data.bank, true)}</div>
        <div className="v-muted bank-acct">{data.accountMasked}</div>
        <div className="bank-cash"><span className="v-muted">{t('bank.cashOnHand')}</span> <strong>{money(data.cash, true)}</strong></div>
        <div className="bank-actions">
          <button className="v-btn primary" onClick={() => onAmount('deposit')} disabled={data.cash <= 0}>{t('bank.deposit')}</button>
          <button className="v-btn" onClick={() => onAmount('withdraw')} disabled={data.bank <= 0}>{t('bank.withdraw')}</button>
          <button className="v-btn" onClick={onTransfer}>{t('bank.transfer')}</button>
        </div>
      </div>
      <div className="bank-quick v-panel"><TransferForm onDone={onDone} say={say} cash={data.cash} bank={data.bank} /></div>
      <div className="bank-recent v-panel">
        <div className="bank-recent-head">
          <span className="bank-h2">{t('bank.recent')}</span>
          <button className="v-btn link" onClick={onViewAll}>{t('bank.viewAll')} <Icon name="chevron" size="0.9rem" /></button>
        </div>
        {data.recent.length === 0 ? <StateView kind="empty" message={t('bank.noActivity')} /> : data.recent.map((a) => <ActivityRow key={a.id} a={a} />)}
      </div>
    </div>
  );
}

export function ActivityRow({ a }: { a: BankActivity }) {
  return (
    <div className="bank-row">
      <span className="bank-row-icon"><Icon name={activityIcon(a)} size="1rem" /></span>
      <span className="bank-row-reason">{a.reason}</span>
      <span className="v-muted bank-row-at">{a.at}</span>
      <span className={`bank-row-amt${a.delta >= 0 ? ' in' : ''}`}>{a.delta >= 0 ? '+' : '-'}{money(Math.abs(a.delta), true).replace('-', '')}</span>
    </div>
  );
}

function Accounts({ data }: { data: BankOverview }) {
  return (
    <div className="bank-accounts">
      <div className="bank-h2">{t('bank.accounts')}</div>
      <div className="bank-acct-card v-panel">
        <Icon name="bank" size="1.4rem" />
        <div><div className="bank-acct-name">{t('bank.bankAccount')}</div><div className="v-muted">{data.account}</div></div>
        <div className="bank-acct-bal">{money(data.bank, true)}</div>
      </div>
      <div className="bank-acct-card v-panel">
        <Icon name="money" size="1.4rem" />
        <div><div className="bank-acct-name">{t('bank.cashAccount')}</div><div className="v-muted">{t('bank.cashOnHand')}</div></div>
        <div className="bank-acct-bal">{money(data.cash, true)}</div>
      </div>
      <p className="v-muted bank-note">Business accounts are not available yet.</p>
    </div>
  );
}

function TransferForm({ big, onDone, say, bank }: { big?: boolean; onDone: () => Promise<void>; say: (k: 'error' | 'success', s: string) => void; cash: number; bank: number }) {
  const [account, setAccount] = useState('');
  const [amount, setAmount] = useState('');
  const [reference, setReference] = useState('');
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);
  const [preview, setPreview] = useState<(RecipientPreview & { amount: number }) | null>(null);
  const [opId, setOpId] = useState<string | null>(null);

  const cont = async () => {
    const errs: Record<string, string> = {};
    const acct = account.trim().toUpperCase();
    if (!/^[A-Z0-9]{6,20}$/.test(acct)) errs.account = 'Enter a valid account number';
    const a = parseAmount(amount);
    if (!a.ok) errs.amount = a.error; else if (a.value > bank) errs.amount = 'Insufficient funds';
    if (reference.length > 40) errs.reference = 'At most 40 characters';
    setErrors(errs);
    if (Object.keys(errs).length || !a.ok) return;
    setBusy(true);
    const res = await nui<RecipientPreview>('resolveRecipient', { account: acct });
    setBusy(false);
    if (!res.ok || !res.data) { setErrors({ account: res.message ?? 'Unknown account' }); return; }
    setOpId(newOpId());
    setPreview({ ...res.data, amount: a.value });
  };

  const send = async () => {
    if (!preview || !opId) return;
    setBusy(true);
    const res = await nui('transfer', { token: preview.token, amount: preview.amount, reference: reference.trim(), opId });
    setBusy(false);
    if (res.ok) {
      say('success', res.message ?? 'Transfer sent');
      setPreview(null); setOpId(null); setAccount(''); setAmount(''); setReference('');
      await onDone();
    } else if (res.code === 'TIMEOUT') {
      say('error', 'Transfer is being verified. Confirm again to check its status.'); // same opId: cannot send twice
    } else {
      say('error', res.message ?? res.code ?? 'Transfer failed');
      setPreview(null); setOpId(null);
    }
  };

  return (
    <div className={`bank-form${big ? ' big' : ''}`}>
      <div className="bank-h2">{big ? t('bank.transfers') : t('bank.quickTransfer')}</div>
      <label className="bank-field"><span>{t('bank.accountNumber')}</span>
        <input className="v-input" value={account} maxLength={20} placeholder="Enter account number" onChange={(e) => setAccount(e.target.value)} />
        {errors.account && <em className="bank-err">{errors.account}</em>}
      </label>
      <label className="bank-field"><span>{t('bank.amount')}</span>
        <input className="v-input" value={amount} inputMode="numeric" placeholder="$0.00" onChange={(e) => setAmount(e.target.value)} />
        {errors.amount && <em className="bank-err">{errors.amount}</em>}
      </label>
      <label className="bank-field"><span>{t('bank.reference')} <span className="v-muted">{t('bank.optional')}</span></span>
        <input className="v-input" value={reference} maxLength={40} placeholder="e.g. Rent, Vehicle, etc." onChange={(e) => setReference(e.target.value)} />
        {errors.reference && <em className="bank-err">{errors.reference}</em>}
      </label>
      <button className="v-btn block" disabled={busy} onClick={() => void cont()}>{busy && !preview ? '…' : t('bank.continue')}</button>
      {preview && (
        <ConfirmDialog
          title={t('bank.confirmTransfer')}
          message={t('bank.sendTo', { amount: money(preview.amount), name: `${preview.name} (${preview.accountMasked})` })}
          detail={reference.trim() ? `Reference: ${reference.trim()}` : undefined}
          busy={busy} onCancel={() => { setPreview(null); setOpId(null); }} onConfirm={() => void send()}
        />
      )}
    </div>
  );
}

function History() {
  const [filter, setFilter] = useState<'all' | 'in' | 'out'>('all');
  const [rows, setRows] = useState<BankActivity[]>([]);
  const [next, setNext] = useState<number | null>(0);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async (offset: number, reset: boolean) => {
    setLoading(true);
    const res = await nui<BankHistoryPage>('history', { offset, filter });
    setLoading(false);
    if (!res.ok || !res.data) { setError(res.message ?? res.code ?? 'Unavailable'); return; }
    setError(null);
    setRows((r) => (reset ? res.data!.rows : [...r, ...res.data!.rows]));
    setNext(res.data.nextOffset);
  }, [filter]);

  useEffect(() => { void load(0, true); }, [load]);

  return (
    <div className="bank-history">
      <div className="bank-history-head">
        <span className="bank-h2">{t('bank.history')}</span>
        <div className="v-tabs">
          {(['all', 'in', 'out'] as const).map((f) => (
            <button key={f} className={`v-tab${filter === f ? ' active' : ''}`} onClick={() => setFilter(f)}>{t(`bank.${f}`)}</button>
          ))}
        </div>
      </div>
      {error ? <StateView kind="error" message={error} onRetry={() => void load(0, true)} />
        : rows.length === 0 && loading ? <StateView kind="loading" />
        : rows.length === 0 ? <StateView kind="empty" message={t('bank.noActivity')} />
        : (
          <div className="v-panel bank-history-list">
            {rows.map((a) => <ActivityRow key={a.id} a={a} />)}
            {next !== null && <button className="v-btn link block" disabled={loading} onClick={() => void load(next, false)}>{loading ? '…' : t('bank.loadMore')}</button>}
          </div>
        )}
    </div>
  );
}
