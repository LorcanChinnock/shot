import { execFileSync } from 'node:child_process';

/** When a file last changed, from git, as a date for the sitemap. Left out where git can't say, such as in a shallow clone, which would date every file to the same commit. */
export function lastModified(...paths: string[]): string | undefined {
  try {
    if (execFileSync('git', ['rev-parse', '--is-shallow-repository'], { encoding: 'utf8' }).trim() !== 'false') return undefined;
    return execFileSync('git', ['log', '-1', '--format=%cs', '--', ...paths], { encoding: 'utf8' }).trim() || undefined;
  } catch {
    return undefined;
  }
}
