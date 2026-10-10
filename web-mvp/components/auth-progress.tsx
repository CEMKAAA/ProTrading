"use client";
import { LoaderCircle, ShieldCheck } from 'lucide-react';
import { UiText } from './language-provider';

export default function AuthProgress({ restoring, retrying, onRetry }: {
  restoring: boolean;
  retrying: boolean;
  onRetry: () => void;
}) {
  return <div className="uc-auth-progress" role="status" aria-live="polite" aria-busy={!retrying}>
    <span className="uc-auth-emblem"><ShieldCheck size={26} aria-hidden="true"/>
      {!retrying && <LoaderCircle className="uc-auth-spinner" size={18} aria-hidden="true"/>}
    </span>
    <div><strong><UiText>{retrying ? 'Your session is saved' : restoring ? 'Restoring your session...' : 'Opening your workspace...'}</UiText></strong>
      <p><UiText>{retrying ? 'The service is temporarily unavailable. We will retry without signing you out.' : 'Securely checking your account. No need to click again.'}</UiText></p>
    </div>
    {retrying && <button className="secondary-btn" type="button" onClick={onRetry}><UiText>{'Retry now'}</UiText></button>}
  </div>;
}
