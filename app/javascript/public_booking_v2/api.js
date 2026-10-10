// API pública da página de agendamento v2 (#1189). Mesma origem, sem login. `fetch` nativo: a página fica leve
// (RA-16). Erro vira ApiError com o status HTTP e o código de `{ error }` do servidor.
const BASE = '/public/api/v2';

export class ApiError extends Error {
  constructor(status, code) {
    super(code || `http_${status}`);
    this.name = 'ApiError';
    this.status = status;
    this.code = code || null;
  }
}

const request = async (path, { method = 'GET', body } = {}) => {
  const headers = { Accept: 'application/json' };
  if (body) headers['Content-Type'] = 'application/json';

  let response;
  try {
    response = await fetch(`${BASE}${path}`, {
      method,
      headers,
      credentials: 'same-origin',
      body: body ? JSON.stringify(body) : undefined,
    });
  } catch (error) {
    throw new ApiError(0, 'network');
  }

  if (response.status === 204) return null;
  const data = await response.json().catch(() => null);
  if (!response.ok) throw new ApiError(response.status, data?.error);
  return data;
};

const segment = value => encodeURIComponent(String(value));

const query = params => {
  const search = new URLSearchParams();
  Object.entries(params).forEach(([key, value]) => {
    if (value !== undefined && value !== null && value !== '') {
      search.set(key, String(value));
    }
  });
  const text = search.toString();
  return text ? `?${text}` : '';
};

export const getPage = (slug, preview) =>
  request(`/booking/${segment(slug)}${query({ preview })}`);

export const getSlots = (slug, date, duration) =>
  request(`/booking/${segment(slug)}/slots${query({ date, duration })}`);

export const getNextSlot = (slug, duration) =>
  request(`/booking/${segment(slug)}/next_slot${query({ duration })}`);

export const createBooking = (slug, payload) =>
  request(`/booking/${segment(slug)}`, { method: 'POST', body: payload });

export const requestContact = (slug, payload) =>
  request(`/booking/${segment(slug)}/contact_request`, {
    method: 'POST',
    body: payload,
  });

export const getInvite = code => request(`/invites/${segment(code)}`);

export const markInviteViewed = code =>
  request(`/invites/${segment(code)}/viewed`, { method: 'POST' });
