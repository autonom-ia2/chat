/* eslint-disable no-restricted-syntax -- Node fixtures register independent boundary cases without browser transpilation. */
import test from 'node:test';
import assert from 'node:assert/strict';
import { chmod, mkdtemp, mkdir, symlink, rm, realpath } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  configuration,
  proxyConfiguration,
  observedSession,
  rolesQueryFields,
  validateRolesResponse,
  safeBrowserLocation,
} from '../../scripts/instagram_testers/session-observer.mjs';
import {
  browserEnvironment,
  isAllowedBrowserRequest,
  privateProfile,
  publisher,
} from '../../scripts/instagram_testers/session-manager.mjs';

const env = {
  INSTAGRAM_META_DEVELOPER_APP_ID: '10001',
  INSTAGRAM_META_BUSINESS_ID: '10002',
  INSTAGRAM_TESTER_ROLES_DOC_ID: '10003',
  INSTAGRAM_TESTER_ADMIN_USER_ID: '12345',
  INSTAGRAM_TESTER_PROXY_HOST: '127.0.0.1',
  INSTAGRAM_TESTER_PROXY_PORT: '9100',
  INSTAGRAM_TESTER_PROXY_AUTH_MODE: 'ip',
};
const config = configuration(env);

test('manual browser initialization validates the proxy without inventing Meta bindings', () => {
  const proxyEnv = {
    INSTAGRAM_TESTER_PROXY_HOST: '127.0.0.1',
    INSTAGRAM_TESTER_PROXY_PORT: '9100',
    INSTAGRAM_TESTER_PROXY_AUTH_MODE: 'ip',
  };
  assert.deepEqual(proxyConfiguration(proxyEnv), {
    host: '127.0.0.1',
    port: '9100',
    authMode: 'ip',
  });
  assert.throws(() => configuration(proxyEnv));
  assert.throws(() =>
    proxyConfiguration({
      ...proxyEnv,
      INSTAGRAM_TESTER_PROXY_PASSWORD: 'synthetic',
    })
  );
});

test('browser child environment excludes backend secrets and protocol tracing', () => {
  assert.deepEqual(
    browserEnvironment({
      PATH: '/synthetic/bin',
      LANG: 'en_US.UTF-8',
      DATABASE_URL: 'synthetic',
      AWS_SECRET_ACCESS_KEY: 'synthetic',
      INSTAGRAM_TESTER_PROXY_PASSWORD: 'synthetic',
      DEBUG: 'pw:protocol',
      PWDEBUG: '1',
    }),
    { PATH: '/synthetic/bin', LANG: 'en_US.UTF-8' }
  );
});
const fields = {
  __user: '12345',
  __bid: '10002',
  doc_id: '10003',
  fb_api_req_friendly_name: 'RolesTable_Query',
  variables: '{"app_id":"10001"}',
  fb_dtsg: 'synthetic-dtsg',
  lsd: 'synthetic-lsd',
  jazoest: '1234',
  __req: '1',
};
const request = overrides => ({
  url: 'https://developers.facebook.com/api/graphql/',
  method: 'POST',
  headers: {
    cookie: 'c_user=12345; xs=synthetic',
    'user-agent': 'Synthetic Browser',
    'x-fb-lsd': 'synthetic-lsd',
  },
  body: new URLSearchParams(fields).toString(),
  ...overrides,
});
const roles = {
  data: {
    get_app_roles: {
      app_roles: [
        {
          role: 'instagram testers',
          users: [{ id: '10004', status: 'CONFIRMED' }],
        },
      ],
    },
  },
};

test('captures only the legitimate matching roles request and binds admin/app/business/doc/proxy', () => {
  const session = observedSession(request(), config);
  assert.equal(session.user_id, '12345');
  assert.equal(session.cookie, 'c_user=12345; xs=synthetic');
  assert.deepEqual(session.extra_form, { __req: '1' });
  assert.equal(config.proxyFingerprint.length, 64);
  assert.equal(
    observedSession(
      request({ url: 'https://example.com/api/graphql/' }),
      config
    ),
    null
  );
  assert.equal(
    observedSession(
      request({
        body: new URLSearchParams({
          ...fields,
          fb_api_req_friendly_name: 'Other_Query',
        }).toString(),
      }),
      config
    ),
    null
  );
});

for (const [field, value] of [
  ['__user', '999'],
  ['__bid', '999'],
  ['doc_id', '999'],
  ['variables', '{"app_id":"999"}'],
  ['fb_dtsg', 'bad\nvalue'],
]) {
  test(`rejects mismatched or unsafe ${field} without publishing`, () => {
    assert.throws(() =>
      observedSession(
        request({
          body: new URLSearchParams({ ...fields, [field]: value }).toString(),
        }),
        config
      )
    );
  });
}
test('rejects duplicate fields/cookies and mismatched cookie/header identity', () => {
  assert.throws(() =>
    observedSession(
      request({
        body: new URLSearchParams({ ...fields, av: '999' }).toString(),
      }),
      config
    )
  );
  assert.throws(() =>
    observedSession(
      request({
        body: new URLSearchParams({
          ...fields,
          variables: '{"app_id":"999","app_id":"10001"}',
        }).toString(),
      }),
      config
    )
  );
  assert.throws(() =>
    observedSession(request({ body: `${request().body}&__user=12345` }), config)
  );
  for (const headers of [
    { ...request().headers, cookie: 'c_user=999' },
    { ...request().headers, cookie: 'c_user=12345; c_user=999' },
    { ...request().headers, 'x-fb-lsd': 'different' },
  ])
    assert.throws(() => observedSession(request({ headers }), config));
});
test('proxy cannot be disabled, contain URL credentials, or change implicitly', () => {
  for (const overrides of [
    { INSTAGRAM_TESTER_PROXY_HOST: '' },
    { INSTAGRAM_TESTER_PROXY_HOST: 'p.webshare.io' },
    { INSTAGRAM_TESTER_PROXY_PORT: '65536' },
    { INSTAGRAM_TESTER_PROXY_AUTH_MODE: 'basic' },
    { INSTAGRAM_TESTER_PROXY_AUTH_MODE: undefined },
    { INSTAGRAM_TESTER_PROXY_USERNAME: 'synthetic-user' },
    { INSTAGRAM_TESTER_PROXY_PASSWORD: 'synthetic-password' },
  ]) {
    assert.throws(() => configuration({ ...env, ...overrides }));
  }
  assert.equal(config.authMode, 'ip');
  assert.equal(config.proxyFingerprint.length, 64);
  assert.notEqual(
    configuration({ ...env, INSTAGRAM_TESTER_PROXY_HOST: '127.0.0.2' })
      .proxyFingerprint,
    config.proxyFingerprint
  );
});
test('requires complete error-free roles; rejects login/challenge/html and partial pagination', () => {
  assert.equal(
    validateRolesResponse(`for (;;);${JSON.stringify(roles)}`),
    true
  );
  for (const body of [
    '<html>login</html>',
    JSON.stringify({ ...roles, errors: [{ message: 'challenge' }] }),
    JSON.stringify({
      data: {
        get_app_roles: { app_roles: [], page_info: { has_next_page: true } },
      },
    }),
    JSON.stringify({
      data: {
        get_app_roles: {
          app_roles: [
            {
              role: 'instagram testers',
              users: [{ id: '10004', status: 'UNKNOWN' }],
            },
          ],
        },
      },
    }),
  ])
    assert.throws(() => validateRolesResponse(body));
  assert.equal(safeBrowserLocation(config.rolesUrl, config), true);
  for (const url of [
    'https://www.facebook.com/login/',
    'https://developers.facebook.com/checkpoint/',
    'https://developers.facebook.com.evil.invalid/',
  ]) {
    assert.equal(safeBrowserLocation(url, config), false);
  }
});
test('allows only safe browser reads and the exact RolesTable query write', () => {
  const graphql = {
    url: 'https://developers.facebook.com/api/graphql/',
    method: 'POST',
    body: new URLSearchParams(fields).toString(),
    config,
  };
  assert.equal(isAllowedBrowserRequest(graphql), true);
  for (const method of ['PUT', 'PATCH', 'DELETE', 'OPTIONS']) {
    assert.equal(
      isAllowedBrowserRequest({ ...graphql, method }),
      false,
      method
    );
  }
  assert.equal(
    isAllowedBrowserRequest({
      ...graphql,
      url: 'https://developers.facebook.com/api/graphql/?write=1',
    }),
    false
  );
  assert.equal(
    isAllowedBrowserRequest({
      ...graphql,
      body: new URLSearchParams({
        ...fields,
        fb_api_req_friendly_name: 'Other_Query',
      }).toString(),
    }),
    false
  );
  assert.equal(
    isAllowedBrowserRequest({
      ...graphql,
      body: new URLSearchParams({ ...fields, doc_id: '999' }).toString(),
    }),
    false
  );
  assert.equal(
    isAllowedBrowserRequest({
      ...graphql,
      body: `${graphql.body}&__user=12345`,
    }),
    false
  );
  assert.equal(rolesQueryFields(graphql.body, config).doc_id, config.docId);
  for (const method of ['GET', 'HEAD']) {
    assert.equal(
      isAllowedBrowserRequest({
        url: 'https://developers.facebook.com/apps/10001/roles/roles/',
        method,
      }),
      true,
      method
    );
  }
  assert.equal(
    isAllowedBrowserRequest({
      url: 'https://developers.facebook.com/apps/10001/roles/add/',
      method: 'GET',
    }),
    false
  );
  assert.equal(
    isAllowedBrowserRequest({
      url: 'https://example.invalid/resource',
      method: 'GET',
    }),
    false
  );
});
test('profile must be private, outside Git and cannot follow symlinks', async () => {
  const root = await mkdtemp(
    join(await realpath(tmpdir()), 'instagram-synthetic-profile-')
  );
  try {
    assert.equal(
      await privateProfile(join(root, 'private')),
      join(root, 'private')
    );
    await mkdir(join(root, '.git'));
    await assert.rejects(privateProfile(join(root, 'in-git')));
    await rm(join(root, '.git'), { recursive: true });
    await symlink(join(root, 'private'), join(root, 'link'));
    await assert.rejects(privateProfile(join(root, 'link')));
    await mkdir(join(root, 'public'), { mode: 0o755 });
    // mkdir's mode is filtered by the caller's umask; make this fixture public.
    await chmod(join(root, 'public'), 0o755);
    await assert.rejects(privateProfile(join(root, 'public')));
    await assert.rejects(privateProfile('relative'));
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
test('publisher uses typed stdin without shell and suppresses errors', async () => {
  const version = '12345678-1234-1234-1234-123456789abc';
  const script = `let input='';process.stdin.on('data',v=>input+=v);process.stdin.on('end',()=>{const r=JSON.parse(input);process.stdout.write(JSON.stringify({type:'session',version:r.type==='session'&&r.operation==='version'?'${version}':null}));});`;
  assert.equal(
    await publisher([process.execPath, '-e', script], {
      type: 'session',
      operation: 'version',
    }),
    version
  );
  await assert.rejects(
    publisher(
      [
        process.execPath,
        '-e',
        "console.error('synthetic-secret');process.exit(2)",
      ],
      { type: 'session', operation: 'version' }
    ),
    { message: 'publication_failed' }
  );
  await assert.rejects(
    publisher(
      [
        process.execPath,
        '-e',
        'console.log(\'{"version":null,"secret":"synthetic"}\')',
      ],
      { type: 'session', operation: 'version' }
    ),
    { message: 'publication_failed' }
  );
  await assert.rejects(
    publisher(null, { type: 'session', operation: 'version' }),
    { message: 'publisher_required' }
  );
});
