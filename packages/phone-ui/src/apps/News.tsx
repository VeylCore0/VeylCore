// Weazel News: the city's news feed. On-duty reporters can publish stories and breaking news.
import { useState } from 'react';
import { api } from '../api';
import { Ico } from '../icons';
import { Button, Empty, Header, Sheet, TextInput, Toggle, cx, say } from '../ui';
import { Chip, Fab, Loaded, ago, useLoad } from './kit';

type Article = { id: number; author: string; title: string; body: string; breaking: number; at: number };
type Data = { articles: Article[]; reporter: boolean };

export function NewsApp() {
  const load = useLoad(() => api<Data>('newsList'));
  const [read, setRead] = useState<Article | null>(null);
  const [write, setWrite] = useState(false);

  return (
    <div className="ph-app">
      <Header title="Weazel News" />
      <div className="ph-scroll ph-pad">
        <Loaded {...load}>
          {(d) => d.articles.length === 0
            ? <Empty icon="note" title="No stories yet" text="Reporters publish city news here." />
            : (
              <>
                {d.articles.map((a, i) => (
                  <button key={a.id} className={cx('ph-article', a.breaking === 1 && 'breaking', i === 0 && 'lead')} onClick={() => setRead(a)}>
                    <span className="ph-article-tags">{a.breaking ? <Chip tone="bad" icon="alert">BREAKING</Chip> : <Chip>City</Chip>}<time>{ago(a.at)} ago</time></span>
                    <strong>{a.title}</strong>
                    <p>{a.body}</p>
                    <em>By {a.author}</em>
                  </button>
                ))}
              </>
            )}
        </Loaded>
      </div>
      {load.data?.reporter && <Fab icon="edit" label="Write a story" onClick={() => setWrite(true)} />}
      {read && (
        <Sheet title={read.breaking ? 'Breaking news' : 'Weazel News'} onClose={() => setRead(null)}>
          <article className="ph-reader"><h3>{read.title}</h3><small>By {read.author} · {ago(read.at)} ago</small>{read.body.split('\n').filter(Boolean).map((p, i) => <p key={i}>{p}</p>)}</article>
        </Sheet>
      )}
      {write && <WriteSheet onClose={() => setWrite(false)} onDone={() => { setWrite(false); void load.reload(); }} />}
    </div>
  );
}

function WriteSheet({ onClose, onDone }: { onClose: () => void; onDone: () => void }) {
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [breaking, setBreaking] = useState(false);
  const [busy, setBusy] = useState(false);
  const send = async () => { setBusy(true); const r = await api('newsPost', title, body, breaking); setBusy(false); if (say(r)) onDone(); };
  return (
    <Sheet title="New story" onClose={onClose}>
      <div className="ph-form">
        <label>Headline<TextInput value={title} onChange={setTitle} placeholder="What happened?" maxLength={120} autoFocus /></label>
        <label>Story<TextInput multiline value={body} onChange={setBody} placeholder="Write the story (at least a couple of sentences)" maxLength={4000} /></label>
        <div className="ph-form-row"><span>Breaking news<br /><small className="ph-sub">Alerts everyone in the city</small></span><Toggle on={breaking} onChange={setBreaking} label="Breaking news" /></div>
        <Button kind="primary" block disabled={title.trim().length < 5 || body.trim().length < 20 || busy} onClick={send}>Publish</Button>
      </div>
    </Sheet>
  );
}
