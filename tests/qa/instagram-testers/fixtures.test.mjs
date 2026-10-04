import test from 'node:test';
import assert from 'node:assert/strict';
import {
  candidates,
  longCandidate,
  configuration,
  deferred,
  json,
  responseFor,
} from './fixtures.mjs';

const url = endpoint =>
  new URL(`http://127.0.0.1:39211/api/v1/accounts/910/instagram${endpoint}`);

test('configuration and synthetic candidates follow frozen public contract', async () => {
  assert.deepEqual(
    JSON.parse(
      (await responseFor(url('/testers/configuration'), 'GET', null, {})).body
    ),
    configuration
  );
  const search = url('/testers/search');
  search.searchParams.set('username', 'empresa_sintetica_qa910');
  assert.deepEqual(
    JSON.parse((await responseFor(search, 'GET', null, {})).body),
    { results: candidates }
  );
  assert.equal(longCandidate.username.length, 30);
});

test('wrong method, account, endpoint and arbitrary IDs fail loudly', async () => {
  await assert.rejects(responseFor(url('/testers/status'), 'GET', null, {}));
  await assert.rejects(
    responseFor(
      new URL(
        'http://127.0.0.1:39211/api/v1/accounts/911/instagram/testers/configuration'
      ),
      'GET',
      null,
      {}
    )
  );
  await assert.rejects(responseFor(url('/roles'), 'POST', {}, {}));
  await assert.rejects(
    responseFor(url('/testers/invite'), 'POST', { id: candidates[0].id }, {})
  );
});

test('status/invite and assisted authorization require exact signed-selection field', async () => {
  const selected = { selection_token: candidates[1].selection_token };
  assert.deepEqual(
    JSON.parse(
      (
        await responseFor(url('/testers/status'), 'POST', selected, {
          status: 'pending',
        })
      ).body
    ),
    { status: 'pending' }
  );
  assert.deepEqual(
    JSON.parse(
      (await responseFor(url('/testers/invite'), 'POST', selected, {})).body
    ),
    { status: 'pending', invited: true }
  );
  await assert.rejects(
    responseFor(url('/authorization'), 'POST', selected, {})
  );
  assert.ok(
    JSON.parse(
      (
        await responseFor(
          url('/authorization'),
          'POST',
          { tester_selection_token: selected.selection_token },
          {}
        )
      ).body
    ).url.startsWith('https://www.instagram.com/')
  );
});

test('legacy authorization sends no selection', async () => {
  await responseFor(url('/authorization'), 'POST', null, { legacy: true });
  await assert.rejects(
    responseFor(
      url('/authorization'),
      'POST',
      { tester_selection_token: candidates[0].selection_token },
      { legacy: true }
    )
  );
});

test('search gate keeps original response for genuine stale-response QA', async () => {
  const gate = deferred();
  const state = { searchGate: gate };
  const search = url('/testers/search');
  search.searchParams.set('username', candidates[0].username);
  const pending = responseFor(search, 'GET', null, state);
  state.search = json({ results: [candidates[1]] });
  gate.resolve();
  assert.deepEqual(JSON.parse((await pending).body).results, candidates);
});
