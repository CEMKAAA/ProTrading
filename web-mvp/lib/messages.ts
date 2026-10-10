import { marketingMessages } from './marketing-messages';
import { studioMessages } from './studio-messages';
import { connectionMessages } from './connection-messages';
import { demoMessages } from './demo-messages';
import { lessonMessages } from './lesson-messages';
import { chartMessages } from './chart-messages';
import { agentMessages } from './agent-messages';
import { adminMessages } from './admin-messages';
import { campaignMessages } from './campaign-messages';
import { authMessages } from './auth-messages';
import { auditProgressMessages } from './audit-progress-messages';
export type Locale = 'en' | 'tr' | 'de';

// Owned, bundled language packs. Engine identifiers and user content stay unchanged.
export const messages: Record<string, readonly [string, string]> = { ...marketingMessages, ...studioMessages, ...connectionMessages, ...demoMessages, ...lessonMessages, ...chartMessages, ...agentMessages, ...adminMessages, ...campaignMessages, ...authMessages, ...auditProgressMessages };
export function translate(text: string, locale: Locale): string {
  if (locale === 'en') return text;
  const trimmed = text.trim(), message=messages[trimmed];
  if(message) return text.replace(trimmed, message[locale === 'tr' ? 0 : 1]);
  return text;
}
