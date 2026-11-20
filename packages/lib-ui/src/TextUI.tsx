import type { TextUIMessage } from '@veyl/ui';

export function TextUI({ data }: { data: TextUIMessage }) {
  return (
    <div className="textui v-panel">
      {data.key && <span className="v-key">{data.key}</span>}
      <span>{data.text}</span>
    </div>
  );
}
