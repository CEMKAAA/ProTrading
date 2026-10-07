import { readFileSync } from 'node:fs';
import { parseEnv } from 'node:util';

const keys = [
  'STRATUM_AI_OPENROUTER_KEY',
  'STRATUM_AI_OPENROUTER_MODEL',
  'STRATUM_AI_LOCAL_MODEL',
  'STRATUM_AI_LOCAL_URL',
];

// Read only inside the control process; never load these into the web launcher.
export function studioAgentEnvironment({ env = process.env, file = new URL('./.state/assistant.env', import.meta.url) } = {}) {
  let saved = {};
  try {
    saved = parseEnv(readFileSync(file, 'utf8'));
  } catch (error) {
    if (error.code !== 'ENOENT') throw new Error('Cannot read server-only assistant configuration.');
  }
  return Object.fromEntries(keys.flatMap(key => {
    const value = env[key] ?? saved[key];
    return typeof value === 'string' ? [[key, value]] : [];
  }));
}
