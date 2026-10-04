export const acceptanceUrl =
  'https://www.instagram.com/accounts/manage_access/';
export const appName =
  'Aplicativo Sintético QA 910 — atendimento e relacionamento';
export const candidates = [
  {
    id: '17841400000000910',
    username: 'empresa_sintetica_qa910',
    name: 'Empresa Sintética QA 910',
    avatar_url: '/qa-avatar.svg',
    selection_token: 'synthetic-selection-910-a',
  },
  {
    id: '17841400000000911',
    username: 'outra_empresa_sintetica_qa',
    name: 'Outra Empresa Sintética',
    avatar_url: null,
    selection_token: 'synthetic-selection-910-b',
  },
];
export const longCandidate = {
  ...candidates[0],
  username: 'perfil_sintetico_de_trinta_letra'.slice(0, 30),
  name: 'Organização Sintética de Relacionamento e Atendimento Internacional',
};
export const configuration = {
  enabled: true,
  available: true,
  app_name: appName,
  acceptance_url: acceptanceUrl,
};
export const json = (body, status = 200) => ({
  status,
  contentType: 'application/json',
  body: JSON.stringify(body),
});
export const errorResponse = (error_code, status = 503) =>
  json({ error_code, message: 'QA_UPSTREAM_PRIVATE_MARKER_910' }, status);
export function deferred() {
  let resolve;
  const promise = new Promise(done => {
    resolve = done;
  });
  return { promise, resolve };
}

// Only frozen internal contracts; no developer.facebook.com response emulation.
export async function responseFor(url, method, body, state) {
  const base = '/api/v1/accounts/910/instagram';
  const endpoint = url.pathname.slice(base.length);
  const allowed = {
    '/testers/configuration': 'GET',
    '/testers/search': 'GET',
    '/testers/status': 'POST',
    '/testers/invite': 'POST',
    '/authorization': 'POST',
  };
  if (!url.pathname.startsWith(`${base}/`) || allowed[endpoint] !== method)
    throw new Error(
      `Unexpected internal HTTP contract: ${method} ${url.pathname}`
    );
  if (endpoint === '/testers/configuration')
    return state.configuration || json(configuration);
  // Configuration deliberately remains public under the backend restriction.
  if (state.restricted && endpoint.startsWith('/testers/'))
    return json({ error_code: 'forbidden' }, 403);
  if (endpoint === '/testers/search') {
    if ([...url.searchParams.keys()].join(',') !== 'username')
      throw new Error('Search must send only username');
    const response =
      state.search || json({ results: state.candidates || candidates });
    if (state.searchGate) await state.searchGate.promise;
    return response;
  }
  const expectedKey =
    endpoint === '/authorization'
      ? 'tester_selection_token'
      : 'selection_token';
  if (endpoint !== '/authorization' || !state.legacy) {
    if (
      Object.keys(body || {}).join(',') !== expectedKey ||
      !(state.candidates || candidates).some(
        candidate => candidate.selection_token === body[expectedKey]
      )
    ) {
      throw new Error(`Invalid selected-profile contract for ${endpoint}`);
    }
  } else if (body !== null)
    throw new Error('Legacy authorization must not send a selection');
  if (endpoint === '/testers/status') {
    if (state.statusGate) await state.statusGate.promise;
    return state.statusResponse || json({ status: state.status || 'absent' });
  }
  if (endpoint === '/testers/invite') {
    if (state.inviteGate) await state.inviteGate.promise;
    return state.invite || json({ status: 'pending', invited: true });
  }
  if (state.oauthGate) await state.oauthGate.promise;
  return (
    state.authorization ||
    json({ url: 'https://www.instagram.com/qa-synthetic-oauth-910' })
  );
}
