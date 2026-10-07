"use client";
import { UiText, useLanguage } from './language-provider';

type LeverSwitchProps = {
  label: string;
  checked: boolean;
  onChange: (checked: boolean) => void;
  description?: string;
  accessibleLabel?: string;
  compact?: boolean;
};

export default function LeverSwitch({ label, checked, onChange, description, accessibleLabel, compact = false }: LeverSwitchProps) {
 const {t}=useLanguage();
  return <button type="button" role="switch" aria-checked={checked}
    aria-label={accessibleLabel ?? label} title={description}
    className={`lever-switch${compact ? " lever-switch-compact" : ""}`} data-enabled={checked}
    onClick={() => onChange(!checked)}>
    <span className="lever-copy"><span className="lever-label"><UiText>{label}</UiText></span>
      <span className="lever-state"><i aria-hidden="true" /><UiText>{checked ? "Enabled" : "Disabled"}</UiText></span>
    </span>
    <span className="lever-plate" aria-hidden="true">
      <span className="lever-screw lever-screw-top" /><span className="lever-screw lever-screw-bottom" />
      <span className="lever-track" /><span className="lever-pivot" />
      <span className="lever-handle"><span className="lever-grip" /></span>
    </span>
  </button>;
}
