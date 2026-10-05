import { realpathSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

// Node canonicalizes import.meta.url; argv retains the release symlink used to launch it.
export function isMainModule(moduleUrl, entrypoint = process.argv[1]) {
  const evaluating = process.execArgv.some(
    arg =>
      ['-e', '--eval', '-p', '--print', '-pe'].includes(arg) ||
      arg.startsWith('--eval=') ||
      arg.startsWith('--print=')
  );
  if (!entrypoint || entrypoint === '-' || evaluating) return false;
  // A real filesystem error for a launched file must remain visible.
  return moduleUrl === pathToFileURL(realpathSync(entrypoint)).href;
}
