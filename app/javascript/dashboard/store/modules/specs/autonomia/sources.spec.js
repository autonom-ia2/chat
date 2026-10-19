import { actions, TETO_DA_RELEITURA_MS } from '../../autonomiaSources';

// #1426 — a releitura da lista de materiais. Ela segue enquanto algo está sendo lido OU já foi lido e espera a revisão
// (needs_review sem reviewed_at): é o que faz a reprovação chegar sem recarregar. Para quando tudo assenta, nunca se
// prende num material sem parecer (de antes da revisão, ou mídia de envio) e tem teto.
const REVISADO = '2026-10-19T12:00:00Z';
const fonte = (status, review = null, extra = {}) => ({
  id: 1,
  kind: 'knowledge',
  status,
  review,
  ...extra,
});
const revisando = fonte('ready', { status: 'needs_review', reviewed_at: null });

const agendar = records => {
  const dispatch = vi.fn().mockResolvedValue(undefined);
  actions.schedulePoll({ dispatch }, { agentId: 7, records });
  return dispatch;
};

describe('#autonomiaSources schedulePoll', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    actions.stopPolling();
  });

  afterEach(() => {
    actions.stopPolling();
    vi.useRealTimers();
  });

  it('keeps reading while a source was read but the review has not landed', () => {
    const dispatch = agendar([revisando]);

    vi.advanceTimersByTime(4000);

    expect(dispatch).toHaveBeenCalledWith('fetch', { agentId: 7 });
  });

  it('keeps reading while a source is being read', () => {
    const dispatch = agendar([fonte('processing')]);

    vi.advanceTimersByTime(4000);

    expect(dispatch).toHaveBeenCalledWith('fetch', { agentId: 7 });
  });

  it.each([
    ['approved', fonte('ready', { status: 'accepted', reviewed_at: REVISADO })],
    [
      'sent back',
      fonte('ready', { status: 'needs_resend', reviewed_at: REVISADO }),
    ],
    ['older than the review (no verdict)', fonte('ready', { status: null })],
    ['a media to send', fonte('ready', null, { kind: 'media' })],
    ['failed', fonte('failed', { status: 'needs_review', reviewed_at: null })],
  ])('stops once the source is %s', (_, record) => {
    const dispatch = agendar([record]);

    vi.advanceTimersByTime(60000);

    expect(dispatch).not.toHaveBeenCalled();
  });

  it('gives up after a ceiling of rounds, even if the review never lands', async () => {
    const dispatch = vi.fn();
    const ler = () =>
      actions.schedulePoll({ dispatch }, { agentId: 7, records: [revisando] });
    dispatch.mockImplementation(async nome => {
      if (nome === 'fetch') ler();
    });
    ler();

    await vi.runAllTimersAsync();

    const leituras = dispatch.mock.calls.filter(([nome]) => nome === 'fetch');
    expect(leituras.length).toBeGreaterThan(10);
    expect(leituras.length).toBe(TETO_DA_RELEITURA_MS / 4000);
  });

  it('starts counting again when the person sends something new', async () => {
    const dispatch = vi.fn();
    const ler = () =>
      actions.schedulePoll({ dispatch }, { agentId: 7, records: [revisando] });
    dispatch.mockImplementation(async nome => {
      if (nome === 'fetch') ler();
    });
    ler();
    await vi.runAllTimersAsync();
    dispatch.mockClear();

    actions.schedulePoll(
      { dispatch },
      { agentId: 7, records: [revisando], novo: true }
    );
    vi.advanceTimersByTime(4000);

    expect(dispatch).toHaveBeenCalledWith('fetch', { agentId: 7 });
  });
});
