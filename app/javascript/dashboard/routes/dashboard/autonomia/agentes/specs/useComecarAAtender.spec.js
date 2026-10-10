import { useComecarAAtender } from '../composables/useComecarAAtender';

const store = vi.hoisted(() => ({ dispatch: vi.fn() }));
vi.mock('dashboard/composables/store', () => ({ useStore: () => store }));

const canais = vi.hoisted(() => ({ connect: vi.fn(), disconnect: vi.fn() }));
vi.mock('dashboard/api/autonomia/channels', () => ({ default: canais }));

const agente = {
  id: 5,
  name: 'Duda',
  status: 'draft',
  enabled: false,
  config: { response_window: 'always' },
};

const http = status =>
  Object.assign(new Error(`${status}`), { response: { status } });
const semRede = () => new Error('Network Error');
// A store (updateRecord → throwErrorMessage) troca o erro do axios por um Error só com a mensagem:
// nunca chega `response`, seja 500, 422 ou falta de rede.
const daStore = () => new Error('Request failed with status code 500');

// A ordem fechada no DECISOES.md item 4: PATCH no novo → DELETE no antigo (troca) → POST no novo.
const chamadas = () => {
  const ordem = [];
  store.dispatch.mockImplementation(async (acao, dados) => {
    ordem.push(`${acao}:${dados.status}`);
  });
  canais.disconnect.mockImplementation(async (id, inbox) => {
    ordem.push(`delete:${id}:${inbox}`);
  });
  canais.connect.mockImplementation(async (id, inbox) => {
    ordem.push(`post:${id}:${inbox}`);
  });
  return ordem;
};

describe('useComecarAAtender', () => {
  beforeEach(() => {
    vi.stubGlobal('navigator', { onLine: true });
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('activates and then connects, in this order', async () => {
    const ordem = chamadas();
    const { comecar, erro } = useComecarAAtender();

    const resultado = await comecar({ agente, inboxId: 10 });

    expect(resultado).toEqual({ ok: true });
    expect(erro.value).toBeNull();
    expect(ordem).toEqual(['autonomiaAgents/update:active', 'post:5:10']);
    expect(store.dispatch).toHaveBeenCalledWith('autonomiaAgents/update', {
      id: 5,
      enabled: true,
      status: 'active',
    });
  });

  it('sends the response window in the same PATCH only when it changes', async () => {
    chamadas();
    const { comecar } = useComecarAAtender();

    await comecar({ agente, inboxId: 10, janela: 'business_hours' });

    expect(store.dispatch).toHaveBeenCalledWith('autonomiaAgents/update', {
      id: 5,
      enabled: true,
      status: 'active',
      config: { response_window: 'business_hours' },
    });
  });

  it('frees the other agent before connecting when swapping a busy inbox', async () => {
    const ordem = chamadas();
    const { comecar } = useComecarAAtender();

    await comecar({
      agente,
      inboxId: 10,
      troca: { agenteId: 9, nome: 'Bia', canal: 'WhatsApp do Centro' },
    });

    expect(ordem).toEqual([
      'autonomiaAgents/update:active',
      'delete:9:10',
      'post:5:10',
    ]);
  });

  it('changes nothing when the PATCH fails', async () => {
    store.dispatch.mockRejectedValue(daStore());
    const { comecar, erro } = useComecarAAtender();

    const resultado = await comecar({ agente, inboxId: 10 });

    expect(resultado).toEqual({ ok: false, motivo: 'comecar', desfeito: true });
    expect(erro.value).toEqual({ motivo: 'comecar', desfeito: true });
    expect(canais.connect).not.toHaveBeenCalled();
    expect(canais.disconnect).not.toHaveBeenCalled();
    expect(store.dispatch).toHaveBeenCalledTimes(1);
  });

  it('undoes the status when freeing the other agent fails', async () => {
    store.dispatch.mockResolvedValue({});
    canais.disconnect.mockRejectedValue(http(500));
    const { comecar } = useComecarAAtender();

    const resultado = await comecar({
      agente,
      inboxId: 10,
      troca: { agenteId: 9, nome: 'Bia', canal: 'WhatsApp do Centro' },
    });

    expect(resultado).toEqual({ ok: false, motivo: 'comecar', desfeito: true });
    expect(canais.connect).not.toHaveBeenCalled();
    expect(store.dispatch).toHaveBeenLastCalledWith('autonomiaAgents/update', {
      id: 5,
      enabled: false,
      status: 'draft',
    });
  });

  it('undoes the status when the inbox refuses the agent (422)', async () => {
    store.dispatch.mockResolvedValue({});
    canais.connect.mockRejectedValue(http(422));
    const { comecar } = useComecarAAtender();

    const resultado = await comecar({ agente, inboxId: 10 });

    expect(resultado).toEqual({ ok: false, motivo: 'canal', desfeito: true });
    expect(store.dispatch).toHaveBeenLastCalledWith('autonomiaAgents/update', {
      id: 5,
      enabled: false,
      status: 'draft',
    });
  });

  it('restores the previous response window when undoing', async () => {
    store.dispatch.mockResolvedValue({});
    canais.connect.mockRejectedValue(http(500));
    const { comecar } = useComecarAAtender();

    await comecar({ agente, inboxId: 10, janela: 'business_hours' });

    expect(store.dispatch).toHaveBeenLastCalledWith('autonomiaAgents/update', {
      id: 5,
      enabled: false,
      status: 'draft',
      config: { response_window: 'always' },
    });
  });

  // DECISOES.md item 16 (a): o DELETE no antigo funcionou e o POST no novo falhou. Desfaz o status
  // do novo e tenta pôr o antigo de volta na caixa, nesta ordem.
  describe('when connecting fails after the other agent left the inbox', () => {
    const troca = { agenteId: 9, nome: 'Bia', canal: 'WhatsApp do Centro' };

    const trocaQueFalha = ({ reconecta, erroDoNovo = http(500) }) => {
      const ordem = chamadas();
      canais.connect.mockImplementation(async (id, inbox) => {
        ordem.push(`post:${id}:${inbox}`);
        if (id === agente.id) throw erroDoNovo;
        if (!reconecta) throw http(500);
      });
      return ordem;
    };

    it('undoes the new status and then puts the other agent back, in this order', async () => {
      const ordem = trocaQueFalha({ reconecta: true });
      const { comecar } = useComecarAAtender();

      await comecar({ agente, inboxId: 10, troca });

      expect(ordem).toEqual([
        'autonomiaAgents/update:active',
        'delete:9:10',
        'post:5:10',
        'autonomiaAgents/update:draft',
        'post:9:10',
      ]);
    });

    it('says "Nothing changed" when the other agent is back in the inbox', async () => {
      trocaQueFalha({ reconecta: true });
      const { comecar, erro } = useComecarAAtender();

      const resultado = await comecar({ agente, inboxId: 10, troca });

      expect(resultado).toEqual({
        ok: false,
        motivo: 'comecar',
        desfeito: true,
      });
      expect(erro.value).toEqual({ motivo: 'comecar', desfeito: true });
    });

    it('keeps the reason of the new agent failure once the other one is back (422)', async () => {
      trocaQueFalha({ reconecta: true, erroDoNovo: http(422) });
      const { comecar } = useComecarAAtender();

      const resultado = await comecar({ agente, inboxId: 10, troca });

      expect(resultado).toEqual({ ok: false, motivo: 'canal', desfeito: true });
    });

    it('says the inbox was left with no agent when putting the other one back fails', async () => {
      trocaQueFalha({ reconecta: false });
      const { comecar, erro } = useComecarAAtender();

      const resultado = await comecar({ agente, inboxId: 10, troca });

      expect(resultado).toEqual({
        ok: false,
        motivo: 'troca_sem_agente',
        desfeito: true,
        troca,
      });
      expect(erro.value.motivo).toBe('troca_sem_agente');
      expect(canais.connect).toHaveBeenCalledTimes(2);
      expect(canais.connect).toHaveBeenLastCalledWith(9, 10);
    });
  });

  it('reports when the undo itself fails', async () => {
    store.dispatch.mockResolvedValueOnce({}).mockRejectedValueOnce(http(500));
    canais.connect.mockRejectedValue(http(500));
    const { comecar } = useComecarAAtender();

    const resultado = await comecar({ agente, inboxId: 10 });

    expect(resultado).toEqual({
      ok: false,
      motivo: 'comecar',
      desfeito: false,
    });
  });

  it('calls a PATCH failure "offline" only when the browser is offline', async () => {
    vi.stubGlobal('navigator', { onLine: false });
    store.dispatch.mockRejectedValue(daStore());
    const { comecar } = useComecarAAtender();

    const resultado = await comecar({ agente, inboxId: 10 });

    expect(resultado.motivo).toBe('offline');
  });

  it('does not call a server error on the PATCH "offline" while online', async () => {
    store.dispatch.mockRejectedValue(daStore());
    const { comecar } = useComecarAAtender();

    const resultado = await comecar({ agente, inboxId: 10 });

    expect(resultado.motivo).toBe('comecar');
  });

  it('calls a connect failure with no answer from the server "offline"', async () => {
    store.dispatch.mockResolvedValue({});
    canais.connect.mockRejectedValue(semRede());
    const { comecar } = useComecarAAtender();

    const resultado = await comecar({ agente, inboxId: 10 });

    expect(resultado.motivo).toBe('offline');
  });

  it('does not start twice while the first one is running', async () => {
    let solta;
    store.dispatch.mockImplementation(
      () =>
        new Promise(resolve => {
          solta = resolve;
        })
    );
    canais.connect.mockResolvedValue({});
    const { comecar, comecando } = useComecarAAtender();

    const primeiro = comecar({ agente, inboxId: 10 });
    expect(comecando.value).toBe(true);
    const segundo = await comecar({ agente, inboxId: 10 });
    solta({});
    await primeiro;

    expect(segundo).toEqual({ ok: false, motivo: 'ocupado' });
    expect(store.dispatch).toHaveBeenCalledTimes(1);
    expect(comecando.value).toBe(false);
  });
});
