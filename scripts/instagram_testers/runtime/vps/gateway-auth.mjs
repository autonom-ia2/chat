import { randomBytes } from 'node:crypto';
import { constants } from 'node:fs';
import filesystem from 'node:fs/promises';
import path from 'node:path';
import { jwtVerify } from 'jose';

export const MAX_SESSIONS = 64;
export const MAX_NONCES = 4096;
const CLAIMS = [
  'iss',
  'aud',
  'sub',
  'jti',
  'iat',
  'exp',
  'request_id',
  'deadline',
  'stack',
];
const HEX = '0123456789abcdef';
const COOKIE_CHARS =
  'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

export function reject(status = 403) {
  return Object.assign(new Error('instagram_gateway_denied'), { status });
}

export function exactKeys(value, keys) {
  return (
    value &&
    typeof value === 'object' &&
    !Array.isArray(value) &&
    Object.keys(value).length === keys.length &&
    keys.every(key => Object.hasOwn(value, key))
  );
}

export function isUuid(value) {
  if (typeof value !== 'string' || value.length !== 36) return false;
  return (
    [...value].every((char, index) =>
      [8, 13, 18, 23].includes(index) ? char === '-' : HEX.includes(char)
    ) &&
    ['1', '2', '3', '4', '5', '6', '7', '8'].includes(value[14]) &&
    '89ab'.includes(value[19])
  );
}

export function sameIdentity(a, b) {
  return a.dev === b.dev && a.ino === b.ino;
}

// The state directory is provisioned by the installer, never created/chmodded here.
export async function privateDirectory(directory, uid, gid, fs = filesystem) {
  const info = await fs.lstat(directory);
  if (
    !info.isDirectory() ||
    info.uid !== uid ||
    info.gid !== gid ||
    info.mode % 4096 !== 0o700
  )
    throw reject();
  return info;
}

export async function runtimeDirectory(config, fs = filesystem) {
  const info = await fs.lstat(config.runtimeDir);
  if (
    !info.isDirectory() ||
    info.uid !== config.browserUid ||
    info.gid !== config.viewerGid ||
    info.mode % 4096 !== 0o710
  )
    throw reject();
  return info;
}

export async function configFromEnv(
  env = process.env,
  {
    fs = filesystem,
    uid = process.getuid(),
    gid = process.getgid(),
    groups = process.getgroups(),
  } = {}
) {
  const stack = env.INSTAGRAM_TESTER_RUNTIME_STACK;
  if (!['hub2you', 'autonomia'].includes(stack)) throw reject();
  const base = new URL(env.INSTAGRAM_TESTER_OPERATOR_BROWSER_URL);
  const issuer = new URL(env.INSTAGRAM_TESTER_OPERATOR_ISSUER);
  const cleanHttps = url =>
    url.protocol === 'https:' &&
    !url.username &&
    !url.password &&
    !url.search &&
    !url.hash;
  const hex = env.INSTAGRAM_TESTER_OPERATOR_BROWSER_SIGNING_KEY;
  const port = stack === 'hub2you' ? 18441 : 18442;
  if (
    !cleanHttps(base) ||
    base.pathname !== `/${stack}/` ||
    base.href !== env.INSTAGRAM_TESTER_OPERATOR_BROWSER_URL ||
    !cleanHttps(issuer) ||
    issuer.origin !== env.INSTAGRAM_TESTER_OPERATOR_ISSUER ||
    typeof hex !== 'string' ||
    hex.length < 64 ||
    hex.length % 2 !== 0 ||
    ![...hex.toLowerCase()].every(char => HEX.includes(char)) ||
    env.INSTAGRAM_TESTER_GATEWAY_PORT !== String(port) ||
    env.INSTAGRAM_TESTER_OPERATOR_REQUEST_FILE !==
      `/run/instagram-${stack}/browser-request.json` ||
    env.INSTAGRAM_TESTER_VNC_SOCKET !== `/run/instagram-${stack}/vnc.sock` ||
    env.INSTAGRAM_TESTER_GATEWAY_STATE_DIR !==
      `/var/lib/instagram-gateway-${stack}/gateway`
  )
    throw reject();
  const browserHome = `/var/lib/instagram-${stack}`;
  const gatewayHome = `/var/lib/instagram-gateway-${stack}`;
  const runtimeDir = `/run/instagram-${stack}`;
  // Check every ancestor with lstat: no symlink, nor writable root-owned parent.
  // eslint-disable-next-line no-restricted-syntax -- Validate trusted ancestors in order.
  for (const directory of ['/', '/var', '/var/lib', '/run']) {
    // eslint-disable-next-line no-await-in-loop -- Each ancestor must be verified before deriving identities.
    const info = await fs.lstat(directory);
    // eslint-disable-next-line no-bitwise -- Detect writable POSIX ancestors.
    if (!info.isDirectory() || info.uid !== 0 || (info.mode & 0o022) !== 0)
      throw reject();
  }
  const browser = await fs.lstat(browserHome);
  const runtime = await fs.lstat(runtimeDir);
  const config = {
    stack,
    base,
    issuer: issuer.origin,
    key: Buffer.from(hex, 'hex'),
    port,
    requestFile: env.INSTAGRAM_TESTER_OPERATOR_REQUEST_FILE,
    vncSocket: env.INSTAGRAM_TESTER_VNC_SOCKET,
    stateDir: env.INSTAGRAM_TESTER_GATEWAY_STATE_DIR,
    gatewayUid: uid,
    gatewayGid: gid,
    browserUid: browser.uid,
    viewerGid: runtime.gid,
    browserHome,
    gatewayHome,
    runtimeDir,
  };
  if (
    !browser.isDirectory() ||
    browser.mode % 4096 !== 0o700 ||
    !Number.isSafeInteger(uid) ||
    uid <= 0 ||
    !Number.isSafeInteger(gid) ||
    gid <= 0 ||
    !Number.isSafeInteger(browser.uid) ||
    browser.uid <= 0 ||
    !Number.isSafeInteger(browser.gid) ||
    browser.gid <= 0 ||
    uid === browser.uid ||
    gid === browser.gid ||
    !Number.isSafeInteger(runtime.gid) ||
    runtime.gid <= 0 ||
    runtime.gid === gid ||
    runtime.gid === browser.gid ||
    !groups.includes(runtime.gid) ||
    groups.some(group => ![gid, runtime.gid].includes(group))
  )
    throw reject();
  await privateDirectory(gatewayHome, uid, gid, fs);
  await privateDirectory(config.stateDir, uid, gid, fs);
  await runtimeDirectory(config, fs);
  return config;
}

export async function readPrivateJson(
  filename,
  owner,
  maxBytes = 1024,
  fs = filesystem
) {
  const valid = info =>
    info.isFile() &&
    info.uid === owner.uid &&
    info.gid === owner.gid &&
    info.mode % 4096 === owner.mode &&
    (owner.marker ? [1, 2].includes(info.nlink) : info.nlink === 1) &&
    info.size <= maxBytes;
  const info = await fs.lstat(filename);
  if (!valid(info)) throw reject();
  const handle = await fs.open(
    filename,
    // eslint-disable-next-line no-bitwise -- Compose POSIX no-follow open flags.
    constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK
  );
  try {
    const current = await handle.stat();
    if (!sameIdentity(info, current) || !valid(current)) throw reject();
    const buffer = Buffer.alloc(maxBytes + 1);
    const { bytesRead } = await handle.read(buffer, 0, buffer.length, 0);
    if (bytesRead > maxBytes) throw reject();
    const after = await handle.stat();
    if (!sameIdentity(current, after) || !valid(after)) throw reject();
    return {
      value: JSON.parse(buffer.subarray(0, bytesRead).toString('utf8')),
      info: after,
    };
  } finally {
    await handle.close();
  }
}

export async function createAuth(
  config,
  now = () => Math.floor(Date.now() / 1000),
  fs = filesystem
) {
  if (
    ![
      config.gatewayUid,
      config.gatewayGid,
      config.browserUid,
      config.viewerGid,
    ].every(value => Number.isSafeInteger(value) && value > 0) ||
    config.gatewayUid === config.browserUid ||
    config.gatewayGid === config.viewerGid
  )
    throw reject();
  if (path.dirname(config.requestFile) !== config.runtimeDir) throw reject();
  const nonceOwner = {
    uid: config.gatewayUid,
    gid: config.gatewayGid,
    mode: 0o600,
  };
  const markerOwner = {
    uid: config.browserUid,
    gid: config.viewerGid,
    mode: 0o640,
    marker: true,
  };
  const identity = await privateDirectory(
    config.stateDir,
    config.gatewayUid,
    config.gatewayGid,
    fs
  );
  const runtimeIdentity = await runtimeDirectory(config, fs);
  const sessions = new Map();
  const cookieName = `__Secure-ig-${config.stack}`;
  let grants = Promise.resolve();

  async function checkDirectory() {
    if (
      !sameIdentity(
        identity,
        await privateDirectory(
          config.stateDir,
          config.gatewayUid,
          config.gatewayGid,
          fs
        )
      )
    )
      throw reject();
  }

  function revoke(id) {
    const session = sessions.get(id);
    sessions.delete(id);
    session?.connection?.terminate();
  }

  async function pruneNonces(cutoff = now()) {
    await checkDirectory();
    let count = 0;
    /* eslint-disable no-restricted-syntax, no-continue, no-await-in-loop -- Inspect and prune each nonce sequentially; skip unsafe entries without removing them. */
    for (const name of await fs.readdir(config.stateDir)) {
      if (
        !name.startsWith('nonce-') ||
        !name.endsWith('.json') ||
        !isUuid(name.slice(6, -5))
      )
        continue;
      const filename = path.join(config.stateDir, name);
      count += 1;
      try {
        const { value, info } = await readPrivateJson(
          filename,
          nonceOwner,
          1024,
          fs
        );
        if (
          !exactKeys(value, ['stack', 'jti', 'exp']) ||
          value.stack !== config.stack ||
          value.jti !== name.slice(6, -5) ||
          !Number.isSafeInteger(value.exp) ||
          value.exp > cutoff
        )
          continue;
        await checkDirectory();
        const current = await fs.lstat(filename);
        if (
          sameIdentity(info, current) &&
          current.isFile() &&
          current.uid === config.gatewayUid &&
          current.gid === config.gatewayGid &&
          current.nlink === 1 &&
          // eslint-disable-next-line no-bitwise -- POSIX permission bits require masking.
          (current.mode & 0o7777) === 0o600
        ) {
          await fs.unlink(filename);
          count -= 1;
        }
      } catch (error) {
        if (error.code === 'ENOENT') count -= 1;
        // Unrecognized/unsafe entries are never removed and still count toward the bound.
        else if (error.code && !['ELOOP', 'EINVAL'].includes(error.code))
          throw error;
      }
    }
    /* eslint-enable no-restricted-syntax, no-continue, no-await-in-loop */
    return count;
  }

  async function checkRuntime() {
    try {
      if (!sameIdentity(runtimeIdentity, await runtimeDirectory(config, fs)))
        throw reject();
    } catch {
      throw reject(401);
    }
  }

  async function marker(session) {
    await checkRuntime();
    let value;
    let missing = false;
    try {
      ({ value } = await readPrivateJson(
        config.requestFile,
        markerOwner,
        1024,
        fs
      ));
    } catch (error) {
      if (error.code === 'ENOENT' && !session.seenMarker) missing = true;
      else throw reject(401);
    }
    await checkRuntime();
    if (missing) return false;
    if (
      !exactKeys(value, ['request_id', 'deadline']) ||
      value.request_id !== session.requestId ||
      value.deadline !== session.deadline ||
      !Number.isSafeInteger(value.deadline) ||
      value.deadline <= now()
    )
      throw reject(401);
    session.seenMarker = true;
    return true;
  }

  async function validate(id, requireMarker = false) {
    const session = sessions.get(id);
    try {
      if (!session || session.expires <= now()) throw reject(401);
      const ready = await marker(session);
      if (sessions.get(id) !== session || session.expires <= now())
        throw reject(401);
      if (requireMarker && !ready) throw reject(409);
      return { session, ready };
    } catch (error) {
      if (error.status !== 409) revoke(id);
      throw error;
    }
  }

  function sessionId(headers) {
    const cookies = (headers.cookie || '').split(';').map(part => part.trim());
    const matches = cookies.filter(part => part.startsWith(`${cookieName}=`));
    if (matches.length !== 1) throw reject(401);
    const id = matches[0].slice(cookieName.length + 1);
    if (id.length !== 43 || ![...id].every(char => COOKIE_CHARS.includes(char)))
      throw reject(401);
    return id;
  }

  async function grant(ticket) {
    // Serialize admission so concurrent requests cannot bypass either capacity bound.
    const operation = grants.then(async () => {
      const time = now();
      const { payload, protectedHeader } = await jwtVerify(ticket, config.key, {
        algorithms: ['HS256'],
        typ: 'JWT',
        issuer: config.issuer,
        audience: `instagram-operator-browser:${config.stack}`,
        requiredClaims: CLAIMS,
        currentDate: new Date(time * 1000),
        clockTolerance: 0,
      });
      if (
        !exactKeys(protectedHeader, ['alg', 'typ']) ||
        protectedHeader.typ !== 'JWT' ||
        !exactKeys(payload, CLAIMS) ||
        payload.iss !== config.issuer ||
        payload.aud !== `instagram-operator-browser:${config.stack}` ||
        payload.stack !== config.stack ||
        typeof payload.sub !== 'string' ||
        !payload.sub.length ||
        payload.sub[0] === '0' ||
        ![...payload.sub].every(char => '0123456789'.includes(char)) ||
        !isUuid(payload.jti) ||
        !isUuid(payload.request_id) ||
        !Number.isSafeInteger(payload.iat) ||
        payload.iat > time ||
        !Number.isSafeInteger(payload.exp) ||
        payload.exp !== payload.iat + 60 ||
        payload.exp <= time ||
        !Number.isSafeInteger(payload.deadline) ||
        payload.deadline <= time ||
        payload.deadline > payload.iat + 3600
      )
        throw reject();
      // eslint-disable-next-line no-restricted-syntax -- Node supports native iteration; preserve ordered side effects.
      for (const [id, session] of sessions)
        if (session.expires <= time) revoke(id);
      if (
        sessions.size >= MAX_SESSIONS ||
        (await pruneNonces(time)) >= MAX_NONCES
      )
        throw reject(503);
      const session = {
        requestId: payload.request_id,
        deadline: payload.deadline,
        expires: Math.min(time + 900, payload.deadline),
        seenMarker: false,
        connection: null,
      };
      await marker(session);
      await checkDirectory();
      // Admission and nonce cleanup share one cutoff; slow I/O cannot revive a ticket.
      if (payload.exp <= now()) throw reject();
      const nonce = await fs.open(
        path.join(config.stateDir, `nonce-${payload.jti}.json`),
        'wx',
        0o600
      );
      try {
        await nonce.chmod(0o600);
        await nonce.writeFile(
          JSON.stringify({
            stack: config.stack,
            jti: payload.jti,
            exp: payload.exp,
          })
        );
        await nonce.sync();
      } finally {
        await nonce.close();
      }
      // Persist the new directory entry before returning any browser access.
      const directory = await fs.open(
        config.stateDir,
        // eslint-disable-next-line no-bitwise -- POSIX open flags require bitwise composition.
        constants.O_RDONLY | constants.O_DIRECTORY | constants.O_NOFOLLOW
      );
      try {
        await directory.sync();
      } finally {
        await directory.close();
      }
      if (payload.exp <= now()) throw reject();
      const id = randomBytes(32).toString('base64url');
      sessions.set(id, session);
      return {
        id,
        cookie: `${cookieName}=${id}; Secure; HttpOnly; SameSite=Strict; Path=/${config.stack}/; Max-Age=${session.expires - time}`,
      };
    });
    grants = operation.catch(() => {});
    return operation;
  }

  await pruneNonces();
  return { grant, validate, sessionId, revoke, sessions, pruneNonces };
}
