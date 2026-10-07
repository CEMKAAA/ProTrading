"use client";

import { createContext, useContext, useEffect, useSyncExternalStore, type ReactNode } from 'react';
import { Globe2 } from 'lucide-react';
import { translate, type Locale } from '@/lib/messages';

const key = 'stratum.language';
const event = 'stratum-language';
const locales: Locale[] = ['en', 'tr', 'de'];
let memoryLocale: Locale | null = null;
const serverSnapshot = (): Locale => 'en';
function browserSnapshot(): Locale {
  try { const value = memoryLocale ?? localStorage.getItem(key); return locales.includes(value as Locale) ? value as Locale : 'en'; }
  catch { return memoryLocale ?? 'en'; }
}
function subscribe(notify: () => void) {
  window.addEventListener(event, notify);
  const storage = (e: StorageEvent) => { if (e.key === key) { memoryLocale = null; notify(); } };
  window.addEventListener('storage', storage);
  return () => { window.removeEventListener(event, notify); window.removeEventListener('storage', storage); };
}
const Language = createContext<Locale>('en');
export function LanguageProvider({ children, locale }: { children: ReactNode; locale?: Locale }) {
  const saved = useSyncExternalStore(subscribe, browserSnapshot, serverSnapshot);
  const current = locale ?? saved;
  useEffect(() => { document.documentElement.lang = current; }, [current]);
  return <Language.Provider value={current}>{children}</Language.Provider>;
}
export function useLanguage() {
  const locale = useContext(Language);
  return { locale, t: (text: string) => translate(text, locale), number: (value: number, digits = 0) => new Intl.NumberFormat(locale, { maximumFractionDigits: digits }).format(value) };
}
// Explicit render-time localization, never DOM rewriting or configuration translation.
export function UiText({ children }: { children: ReactNode }) {
  const { t } = useLanguage();
  return <>{typeof children === 'string' ? t(children) : children}</>;
}
export function LanguageSelect() {
  const { locale, t } = useLanguage();
  return <label className="language-select"><Globe2 size={17} aria-hidden="true"/><span className="sr-only">{t('Language')}</span><select aria-label={t('Language')} value={locale} onChange={e => {
    try { localStorage.setItem(key, e.target.value); } catch { /* The current-tab event still updates the UI when storage is unavailable. */ }
    memoryLocale = e.target.value as Locale;
    window.dispatchEvent(new Event(event));
  }}>{locales.map(l => <option key={l} value={l}>{{ en: 'English', tr: 'Türkçe', de: 'Deutsch' }[l]}</option>)}</select></label>;
}
