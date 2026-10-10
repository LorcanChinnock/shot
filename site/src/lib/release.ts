import { readFile } from 'node:fs/promises';

const repo = 'LorcanChinnock/shot';

export interface Release {
  version: string;
  zip: string;
  date?: string;
}

let cached: Promise<Release> | undefined;

/**
 * The latest published release. Read from GitHub at build time so the download button never points at a draft
 * (release-please tags first and attaches the zip later); falls back to the release-please manifest offline.
 */
export function latestRelease(): Promise<Release> {
  cached ??= fetchLatest().catch(async (error) => {
    console.warn(`[release] GitHub API unavailable (${error.message}); using .release-please-manifest.json`);
    const manifest = JSON.parse(await readFile(new URL('../../../.release-please-manifest.json', import.meta.url), 'utf8'));
    const version = manifest['.'];
    return { version, zip: zipURL(`v${version}`) };
  });
  return cached;
}

async function fetchLatest(): Promise<Release> {
  const headers: Record<string, string> = { Accept: 'application/vnd.github+json', 'User-Agent': 'shot-site' };
  if (process.env.GITHUB_TOKEN) headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
  const response = await fetch(`https://api.github.com/repos/${repo}/releases/latest`, { headers });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  const release = await response.json();
  const asset = release.assets?.find((a: { name: string }) => /^Shot-v.+\.zip$/.test(a.name));
  return {
    version: release.tag_name.replace(/^v/, ''),
    zip: asset?.browser_download_url ?? zipURL(release.tag_name),
    date: release.published_at,
  };
}

function zipURL(tag: string) {
  return `https://github.com/${repo}/releases/download/${tag}/Shot-${tag}.zip`;
}
