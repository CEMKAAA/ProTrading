'use client';

import {Check, Database, Activity, ShieldCheck} from 'lucide-react';
import {useLanguage, UiText} from './language-provider';
import {auditProgressModel, type AuditProgressSnapshot} from '@/lib/audit-progress';

const stages = [
  {label: 'Broker history', icon: Database},
  {label: 'Trade replay', icon: Activity},
  {label: 'Result received', icon: ShieldCheck},
];

export default function AuditProgress({job, now, terminalError = ''}: {
  job: AuditProgressSnapshot; now: number; terminalError?: string;
}) {
  const {t} = useLanguage();
  const model = auditProgressModel(job, now, terminalError);
  return <div className={`uc-audit-progress${model.paused ? ' is-paused' : ''}`} data-audit-state={job.state}>
    <div className="uc-audit-progress-heading">
      <strong role="status"><UiText>{model.label}</UiText></strong>
      <span className="mono"><UiText>{'Elapsed'}</UiText> {model.elapsed}</span>
    </div>
    <div className={`uc-audit-meter${model.percent === null && model.active ? ' is-indeterminate' : ''}`}
      role="progressbar" aria-label={t(model.label)} aria-valuemin={0} aria-valuemax={100}
      aria-valuenow={model.percent ?? undefined}
      aria-valuetext={model.percent === null ? t('Completion percentage unavailable') : `${model.percent}%`}>
      <span className="uc-audit-meter-fill" style={model.percent === null ? undefined : {width: `${model.percent}%`}}/>
    </div>
    <div className="uc-audit-progress-caption">
      <span><UiText>{model.percent === null ? 'Waiting for real broker data; total download size is not supplied by MT5.' : 'Measured audit progress'}</UiText></span>
      {model.percent !== null && <strong className="mono">{model.percent}%</strong>}
    </div>
    <ol className="uc-audit-stages" aria-label={t('Audit stages')}>
      {stages.map(({label, icon: Icon}, i) => <li key={label}
        className={i < model.step ? 'is-done' : i === model.step && model.active ? 'is-current' : ''}
        aria-current={i === model.step && model.active ? 'step' : undefined}>
        {i < model.step ? <Check size={15}/> : <Icon size={15}/>}<UiText>{label}</UiText>
      </li>)}
    </ol>
    {model.paused && <p className="uc-audit-pause"><UiText>{'Research is paused until a fresh signed command arrives. Keep the helper open and check browser authorization. No result is being assumed.'}</UiText></p>}
    {job.progress?.detail && <p className="uc-audit-detail mono">{job.progress.detail}</p>}
  </div>;
}
