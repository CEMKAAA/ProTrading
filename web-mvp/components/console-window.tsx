"use client";
import { UiText, useLanguage } from './language-provider';

import { type ReactNode, type RefObject } from "react";
import { Dialog } from "radix-ui";
import { X, Command } from "lucide-react";

export default function ConsoleWindow({ open, onOpenChange, title, description, tone = "gold", children, footer, returnFocus }: {
  open: boolean; onOpenChange: (open: boolean) => void; title: string; description: string;
  tone?: string; children: ReactNode; footer?: ReactNode; returnFocus?: RefObject<HTMLElement | null>;
}) {
 const {t}=useLanguage();
  return <Dialog.Root open={open} onOpenChange={onOpenChange}>
    <Dialog.Portal><Dialog.Overlay className="console-window-overlay" />
      <Dialog.Content className="console-window universal-dashboard" data-tone={tone} onCloseAutoFocus={event=>{if(returnFocus?.current?.isConnected){event.preventDefault();returnFocus.current.focus();}}}>
        <header className="console-window-header"><div className="console-window-emblem"><Command size={24}/></div>
          <div><span className="console-window-kicker"><UiText>{"STRATUM / CONTROL ROOM"}</UiText></span><Dialog.Title><UiText>{title}</UiText></Dialog.Title>
            <Dialog.Description><UiText>{description}</UiText></Dialog.Description></div>
          <Dialog.Close className="console-window-close" aria-label={t("Close settings window")}><X size={22}/></Dialog.Close>
        </header>
        <div className="console-window-body"><UiText>{children}</UiText></div>
        {footer && <footer className="console-window-footer"><UiText>{footer}</UiText></footer>}
      </Dialog.Content>
    </Dialog.Portal>
  </Dialog.Root>;
}
