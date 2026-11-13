import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';

/**
 * Reads release-please's CHANGELOG.md into releases for /changelog/ and its RSS feed.
 * The file stays as release-please writes it: its headings and `**scope:**` prefixes are mapped here.
 */

const repo = 'https://github.com/LorcanChinnock/shot';

/** New for features, Fixed for bug fixes, Faster for performance work, Changed for breaking changes. */
export type Kind = 'new' | 'fixed' | 'faster' | 'changed';

export interface Entry {
  kind: Kind;
  /** The commit scope in words ("video editor"), if it had one. */
  scope?: string;
  /** Which of the four scope tag colours it gets, if any. */
  area?: 'capture' | 'editor' | 'gallery' | 'release';
  /** The change as HTML, with its first letter capitalised and a full stop. */
  html: string;
  /** The change as plain text, for the feed. */
  text: string;
  pr?: number;
}

export interface Release {
  version: string;
  /** YYYY-MM-DD. */
  date: string;
  entries: Entry[];
  /** Text under a release with no entries, such as 0.1.0's "First public release." */
  summary?: string;
}

const kinds: Record<string, Kind> = {
  Features: 'new',
  'Bug Fixes': 'fixed',
  'Performance Improvements': 'faster',
  '⚠ BREAKING CHANGES': 'changed',
};

const areas: Record<string, Entry['area']> = {
  capture: 'capture', overlay: 'capture', recording: 'capture', hotkeys: 'capture', shortcuts: 'capture',
  editor: 'editor', 'video-editor': 'editor', video: 'editor', text: 'editor', export: 'editor', style: 'editor',
  gallery: 'gallery', 'quick-access': 'gallery',
  release: 'release', update: 'release', updates: 'release', build: 'release', site: 'release', icon: 'release',
};

const scopeNames: Record<string, string> = {
  a11y: 'accessibility', ai: 'AI', linux: 'Linux', app: 'app', cli: 'command line', i18n: 'languages', ui: 'interface',
  perf: 'speed', 'menu-bar': 'menu bar', 'bug-report': 'bug report', 'quick-access': 'Quick Access',
};

const escape = (text: string) => text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

/** Renders the little Markdown release-please writes: code, links and bold. */
function inline(markdown: string) {
  return escape(markdown)
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, (_, text, href) => `<a href="${/^https?:/.test(href) ? href : `${repo}/blob/main/${href.replace(/^\.\.\//, '')}`}">${text}</a>`)
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
}

const plain = (markdown: string) => markdown.replace(/`([^`]+)`/g, '$1').replace(/\[([^\]]+)\]\([^)]*\)/g, '$1').replace(/\*\*/g, '');

function sentence(markdown: string) {
  const text = markdown.charAt(0).toUpperCase() + markdown.slice(1);
  return /[.!?…)]$/.test(text) ? text : `${text}.`;
}

function entry(line: string, kind: Kind): Entry {
  let body = line.slice(2);
  const scope = /^\*\*([^*:]+):\*\*\s*/.exec(body);
  if (scope) body = body.slice(scope[0].length);
  // The commit link and a ", closes #N" the PR link already covers, then the PR link, which then ends the line.
  body = body.replace(/\s*\(\[[0-9a-f]{7,}\]\([^)]*\)\)/g, '');
  body = body.replace(/,?\s*closes(?:\s*\[#\d+\]\([^)]*\))+/g, '').trim();
  const pr = /\s*\(\[#(\d+)\]\([^)]*\)\)\s*$/.exec(body);
  if (pr) body = body.slice(0, pr.index).trim();
  const text = sentence(body);
  const key = scope?.[1].trim();
  return {
    kind,
    scope: key ? (scopeNames[key] ?? key.replace(/-/g, ' ')) : undefined,
    area: key ? areas[key] : undefined,
    html: inline(text),
    text: plain(text),
    pr: pr ? Number(pr[1]) : undefined,
  };
}

export function parseChangelog(markdown: string): Release[] {
  return markdown
    .split(/^## /m)
    .slice(1)
    .flatMap((section) => {
      const head = /^\[([^\]]+)\]\([^)]*\) \((\d{4}-\d{2}-\d{2})\)/.exec(section) ?? /^\[?([^\]\s]+)\]? \((\d{4}-\d{2}-\d{2})\)/.exec(section);
      if (!head) return [];
      const [, version, date] = head;
      const entries: Entry[] = [];
      const summary: string[] = [];
      let kind: Kind | undefined;
      for (const line of section.split('\n').slice(1)) {
        if (line.startsWith('### ')) kind = kinds[line.slice(4).trim()] ?? 'new';
        else if (line.startsWith('* ') && kind) entries.push(entry(line, kind));
        else if (line.trim() && !kind) summary.push(line.trim());
      }
      // release-please lists a breaking feature twice, and sometimes repeats an entry: keep the first.
      const seen = new Set<string>();
      const unique = entries.filter((e) => {
        const key = e.text.toLowerCase();
        if (seen.has(key)) return false;
        seen.add(key);
        return true;
      });
      return [{ version, date, entries: unique, summary: summary.join(' ') || undefined }];
    });
}

/** CHANGELOG.md from the repo root. Builds run in the site folder; once bundled, import.meta.url points inside dist/. */
export async function readChangelog() {
  return parseChangelog(await readFile(resolve(process.cwd(), '../CHANGELOG.md'), 'utf8'));
}

export const prURL = (pr: number) => `${repo}/pull/${pr}`;
export const releaseURL = (version: string) => `${repo}/releases/tag/v${version}`;
