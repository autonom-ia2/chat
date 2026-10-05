import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import filesystem, {
  chmod,
  mkdir,
  mkdtemp,
  realpath,
  rm,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { createAuth } from '../../scripts/instagram_testers/runtime/vps/gateway-auth.mjs';

test('RubyJWT tickets are consumed by the actual jose gateway with the same decoded key', async t => {
  const root = await mkdtemp(
    path.join(await realpath(tmpdir()), 'ig995-rubyjwt-')
  );
  await chmod(root, 0o700);
  t.after(() => rm(root, { recursive: true, force: true }));
  const runtimeDir = path.join(root, 'runtime');
  await mkdir(runtimeDir, { mode: 0o710 });
  await chmod(runtimeDir, 0o710);
  const projectStat = (filename, info) =>
    Object.assign(info, {
      uid: filename === runtimeDir ? 2102 : 2101,
      gid: filename === runtimeDir ? 2202 : 2201,
    });
  const fs = {
    ...filesystem,
    lstat: async filename =>
      projectStat(filename, await filesystem.lstat(filename)),
    open: async (...args) => {
      const handle = await filesystem.open(...args);
      return new Proxy(handle, {
        get(target, key) {
          if (key === 'stat')
            return async () => projectStat(args[0], await target.stat());
          const value = target[key];
          return typeof value === 'function' ? value.bind(target) : value;
        },
      });
    },
  };
  const time = 1800000000;
  const key = 'ab'.repeat(32);
  const claims = {
    iss: 'https://hub.example',
    aud: 'instagram-operator-browser:hub2you',
    sub: '42',
    jti: '11111111-1111-4111-8111-111111111111',
    iat: time,
    exp: time + 60,
    request_id: '22222222-2222-4222-8222-222222222222',
    deadline: time + 3600,
    stack: 'hub2you',
  };
  const ruby = spawnSync(
    'ruby',
    [
      '-e',
      `
    gem 'jwt', '2.10.3'
    require 'jwt'
    require 'json'
    input = JSON.parse(STDIN.read)
    STDOUT.write JWT.encode(input.fetch('claims'), [input.fetch('hex')].pack('H*'), 'HS256', typ: 'JWT')
  `,
    ],
    {
      input: JSON.stringify({ claims, hex: key }),
      encoding: 'utf8',
      timeout: 10000,
    }
  );
  assert.equal(ruby.error, undefined);
  assert.equal(
    ruby.status,
    0,
    'RubyJWT 2.10.3 must be installed in the isolated test Ruby environment'
  );
  const auth = await createAuth(
    {
      stack: 'hub2you',
      issuer: claims.iss,
      key: Buffer.from(key, 'hex'),
      stateDir: root,
      requestFile: path.join(runtimeDir, 'request.json'),
      gatewayUid: 2101,
      gatewayGid: 2201,
      browserUid: 2102,
      viewerGid: 2202,
      runtimeDir,
    },
    () => time,
    fs
  );
  const result = await auth.grant(ruby.stdout);
  assert.ok(
    result.cookie.includes('Secure; HttpOnly; SameSite=Strict; Path=/hub2you/')
  );
  await assert.rejects(auth.grant(ruby.stdout));
  const other = await createAuth(
    {
      stack: 'autonomia',
      issuer: claims.iss,
      key: Buffer.from(key, 'hex'),
      stateDir: root,
      requestFile: path.join(runtimeDir, 'request.json'),
      gatewayUid: 2101,
      gatewayGid: 2201,
      browserUid: 2102,
      viewerGid: 2202,
      runtimeDir,
    },
    () => time,
    fs
  );
  await assert.rejects(other.grant(ruby.stdout));
});
