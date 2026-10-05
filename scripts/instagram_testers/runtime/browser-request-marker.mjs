import filesystem, { link } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { dirname, isAbsolute, resolve } from 'node:path';

const refused = () => new Error('operator_browser_state_rejected');
export function requestMarker(env, now = Date.now) {
  const path = env.INSTAGRAM_TESTER_OPERATOR_REQUEST_FILE;
  if (!path) return null;
  const id = env.INSTAGRAM_TESTER_OPERATOR_REQUEST_ID;
  const parts = typeof id === 'string' ? id.split('-') : [];
  const sizes = [8, 4, 4, 4, 12];
  const rawDeadline = env.INSTAGRAM_TESTER_OPERATOR_REQUEST_DEADLINE;
  const deadline = Number(rawDeadline);
  const seconds = Math.floor(now() / 1000);
  if (
    !isAbsolute(path) ||
    resolve(path) !== path ||
    parts.length !== sizes.length ||
    !parts.every(
      (part, index) =>
        part.length === sizes[index] &&
        [...part].every(char => '0123456789abcdef'.includes(char))
    ) ||
    String(deadline) !== rawDeadline ||
    !Number.isSafeInteger(deadline) ||
    deadline <= seconds ||
    deadline > seconds + 3600
  )
    throw refused();
  return { path, value: { request_id: id, deadline } };
}

export async function publishBrowserMarker(
  env,
  now = Date.now,
  createLink = link,
  { fs = filesystem, uid = process.getuid(), groups = process.getgroups() } = {}
) {
  const marker = requestMarker(env, now);
  if (!marker) return async () => {};
  const ancestors = [dirname(marker.path)];
  while (ancestors.at(-1) !== dirname(ancestors.at(-1)))
    ancestors.push(dirname(ancestors.at(-1)));
  const directories = await Promise.all(ancestors.map(path => fs.lstat(path)));
  if (directories.some(info => !info.isDirectory() || info.isSymbolicLink()))
    throw refused();
  const directory = await fs.lstat(dirname(marker.path));
  if (
    directory.uid !== uid ||
    directory.mode % 4096 !== 0o710 ||
    !groups.includes(directory.gid)
  )
    throw refused();
  const temporary = `${marker.path}.pending-${randomUUID()}`;
  const handle = await fs.open(temporary, 'wx', 0o600);
  let identity;
  let released = false;
  const release = async () => {
    if (released) return;
    const current = await fs.lstat(marker.path).catch(error => {
      if (error.code === 'ENOENT') return null;
      throw error;
    });
    if (
      current &&
      (current.ino !== identity.ino ||
        current.dev !== identity.dev ||
        !current.isFile() ||
        current.uid !== uid ||
        current.gid !== directory.gid ||
        current.mode % 4096 !== 0o640 ||
        ![1, 2].includes(current.nlink))
    )
      throw refused();
    if (current) await fs.unlink(marker.path);
    released = true;
  };
  try {
    // The manager umask may be 0077: set the shared viewer group and exact mode explicitly.
    await handle.chown(-1, directory.gid);
    await handle.chmod(0o640);
    identity = await handle.stat();
    if (
      !identity.isFile() ||
      identity.uid !== uid ||
      identity.gid !== directory.gid ||
      identity.mode % 4096 !== 0o640 ||
      identity.nlink !== 1
    )
      throw refused();
    await handle.writeFile(JSON.stringify(marker.value));
    await handle.sync();
    await handle.close();
    // link(2) publishes the complete JSON atomically and refuses an existing name.
    // For this instant only, the complete public marker has two hard links.
    const currentDirectory = await fs.lstat(dirname(marker.path));
    if (
      !currentDirectory.isDirectory() ||
      currentDirectory.uid !== uid ||
      currentDirectory.gid !== directory.gid ||
      currentDirectory.mode % 4096 !== 0o710 ||
      currentDirectory.ino !== directory.ino ||
      currentDirectory.dev !== directory.dev
    )
      throw refused();
    await createLink(temporary, marker.path);
  } finally {
    await handle.close();
    await fs.unlink(temporary);
  }
  return release;
}
