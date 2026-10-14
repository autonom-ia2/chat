import {
  mensagemDaRecusa,
  useComecarAAtender,
} from '../composables/useComecarAAtender';

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

const http = (status, data = {}) =>
  Object.assign(new Error(`${status}`), { response: { status, data } });
const semRede = () => new Error('Network Error');
// A store (updateRecord → throwErrorMessage) troca o erro do axios por um Error só com a mensagem:
// nunca chega `response`, seja 500, 422 ou falta de rede.
const daStore = () => new Error('Request failed with status code 500');

// #1366: PATCH do "quando" (só se mudou) → DELETE no antigo (troca) → POST no novo com ativar →
// relê o agente. Não há mais PATCH de status: ligar é o próprio POST.
const chamadas = () => {
  const ordem = [];
  store.dispatch.mockImplementation(async (acao, dados) => {
    ordem.push(acao === 'autonomiaAgents/show' ? `show:${dados}` : acao);
  });
  canais.disconnect.mockImplementation(async (id, inbox) => {
    ordem.push(`delete:${id}:${inbox}`);
  });
  canais.connect.mockImplementation(async (id, inbox, opcoes) => {
    ordem.push(`post:${id}:${inbox}:${opcoes?.ativar ? 'ativar' : '-'}`);
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

  it('connects with ativar and then reads the agent again, without a status PATCH', async () => {
    const ordem = chamadas();
    const { comecar, erro } = useComecarAAtender();

    const resultado = await comecar({ agente, inboxId: 10 });

    expect(resultado).toEqual({ ok: true });
    expect(erro.value).toBeNull();
    expect(ordem).toEqual(['post:5:10:ativar', 'show:5']);
    expect(store.dispatch).not.toHaveBeenCalledWith(
      'autonomiaAgents/update',
      expect.anything()
    );
  });

  it('saves the response window first, only when it changes', async () => {
    const ordem = chamadas();
    const { comecar } = useComecarAAtender();

    await comecar({ agente, inboxId: 10, janela: 'business_hours' });

    expect(ordem).toEqual([
      'autonomiaAgents/update',
      'post:5:10:ativar',
      'show:5',
    ]);
    expect(store.dispatch).toHaveBeenCalledWith('autonomiaAgents/update', {
      id: 5,
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

    expect(ordem).toEqual(['delete:9:10', 'post:5:10:ativar', 'show:5']);
  });

  it('changes nothing when saving the response window fails', async () => {
    store.dispatch.mockRejectedValue(daStore());
    const { comecar, erro } = useComecarAAtender();

    const resultado = await comecar({
      agente,
      inboxId: 10,
      janela: 'business_hours',
    });

    expect(resultado).toEqual({
      ok: false,
      motivo: 'comecar',
      desfeito: true,
      mensagem: null,
    });
    expect(erro.value).toEqual({
      motivo: 'comecar',
      desfeito: true,
      mensagem: null,
    });
    expect(canais.connect).not.toHaveBeenCalled();
    expect(canais.disconnect).not.toHaveBeenCalled();
  });

  it('turns nothing on when freeing the other agent fails', async () => {
    store.dispatch.mockResolvedValue({});
    canais.disconnect.mockRejectedValue(http(500));
    const { comecar } = useComecarAAtender();

    const resultado = await comecar({
      agente,
      inboxId: 10,
      troca: { agenteId: 9, nome: 'Bia', canal: 'WhatsApp do Centro' },
    });

    expect(resultado).toEqual({
      ok: false,
      motivo: 'comecar',
      desfeito: true,
      mensagem: null,
    });
    expect(canais.connect).not.toHaveBeenCalled();
    expect(store.dispatch).not.toHaveBeenCalled();
  });

  it('keeps the server explanation when the inbox refuses the agent (422)', async () => {
    store.dispatch.mockResolvedValue({});
    canais.connect.mockRejectedValue(
      http(422, { error: 'Esta caixa já tem um agente.' })
    );
    const { comecar } = useComecarAAtender();

    const resultado = await comecar({ agente, inboxId: 10 });

    expect(resultado).toEqual({
      ok: false,
      motivo: 'canal',
      desfeito: true,
      mensagem: 'Esta caixa já tem um agente.',
    });
    expect(store.dispatch).not.toHaveBeenCalled();
  });

  it('restores the previous response window when the connect fails', async () => {
    store.dispatch.mockResolvedValue({});
    canais.connect.mockRejectedValue(http(500));
    const { comecar } = useComecarAAtender();

    await comecar({ agente, inboxId: 10, janela: 'business_hours' });

    expect(store.dispatch).toHaveBeenLastCalledWith('autonomiaAgents/update', {
      id: 5,
      config: { response_window: 'always' },
    });
  });

  // DECISOES.md item 16 (a): o DELETE no antigo funcionou e o POST no novo falhou. Tenta pôr o
  // antigo de volta na caixa — ligado de novo só se ele atendia (sair da última caixa o parou).
  describe('when connecting fails after the other agent left the inbox', () => {
    const troca = {
      agenteId: 9,
      nome: 'Bia',
      canal: 'WhatsApp do Centro',
      atendia: true,
    };

    const trocaQueFalha = ({ reconecta, erroDoNovo = http(500) }) => {
      const ordem = chamadas();
      canais.connect.mockImplementation(async (id, inbox, opcoes) => {
        ordem.push(`post:${id}:${inbox}:${opcoes?.ativar ? 'ativar' : '-'}`);
        if (id === agente.id) throw erroDoNovo;
        if (!reconecta) throw http(500);
      });
      return ordem;
    };

    it('puts the other agent back, turned on again when it was answering', async () => {
      const ordem = trocaQueFalha({ reconecta: true });
      const { comecar } = useComecarAAtender();

      await comecar({ agente, inboxId: 10, troca });

      expect(ordem).toEqual([
        'delete:9:10',
        'post:5:10:ativar',
        'post:9:10:ativar',
      ]);
    });

    it('puts a stopped agent back without turning it on', async () => {
      const ordem = trocaQueFalha({ reconecta: true });
      const { comecar } = useComecarAAtender();

      await comecar({
        agente,
        inboxId: 10,
        troca: { ...troca, atendia: false },
      });

      expect(ordem.at(-1)).toBe('post:9:10:-');
    });

    it('says "Nothing changed" when the other agent is back in the inbox', async () => {
      trocaQueFalha({ reconecta: true });
      const { comecar, erro } = useComecarAAtender();

      const resultado = await comecar({ agente, inboxId: 10, troca });

      expect(resultado).toEqual({
        ok: false,
        motivo: 'comecar',
        desfeito: true,
        mensagem: null,
      });
      expect(erro.value.motivo).toBe('comecar');
    });

    it('keeps the reason of the new agent failure once the other one is back (422)', async () => {
      trocaQueFalha({ reconecta: true, erroDoNovo: http(422) });
      const { comecar } = useComecarAAtender();

      const resultado = await comecar({ agente, inboxId: 10, troca });

      expect(resultado.motivo).toBe('canal');
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
      expect(canais.connect).toHaveBeenLastCalledWith(9, 10, { ativar: true });
    });
  });

  it('reports when undoing the response window fails', async () => {
    store.dispatch.mockResolvedValueOnce({}).mockRejectedValueOnce(http(500));
    canais.connect.mockRejectedValue(http(500));
    const { comecar } = useComecarAAtender();

    const resultado = await comecar({
      agente,
      inboxId: 10,
      janela: 'business_hours',
    });

    expect(resultado).toEqual({
      ok: false,
      motivo: 'comecar',
      desfeito: false,
      mensagem: null,
    });
  });

  it('calls a PATCH failure "offline" only when the browser is offline', async () => {
    vi.stubGlobal('navigator', { onLine: false });
    store.dispatch.mockRejectedValue(daStore());
    const { comecar } = useComecarAAtender();

    const resultado = await comecar({
      agente,
      inboxId: 10,
      janela: 'business_hours',
    });

    expect(resultado.motivo).toBe('offline');
  });

  it('does not call a server error on the PATCH "offline" while online', async () => {
    store.dispatch.mockRejectedValue(daStore());
    const { comecar } = useComecarAAtender();

    const resultado = await comecar({
      agente,
      inboxId: 10,
      janela: 'business_hours',
    });

    expect(resultado.motivo).toBe('comecar');
  });

  it('calls a connect failure with no answer from the server "offline"', async () => {
    store.dispatch.mockResolvedValue({});
    canais.connect.mockRejectedValue(semRede());
    const { comecar } = useComecarAAtender();

    const resultado = await comecar({ agente, inboxId: 10 });

    expect(resultado.motivo).toBe('offline');
  });

  it('still succeeds when only reading the agent again fails', async () => {
    canais.connect.mockResolvedValue({});
    store.dispatch.mockRejectedValue(daStore());
    const { comecar } = useComecarAAtender();

    expect(await comecar({ agente, inboxId: 10 })).toEqual({ ok: true });
  });

  it('does not start twice while the first one is running', async () => {
    let solta;
    canais.connect.mockImplementation(
      () =>
        new Promise(resolve => {
          solta = resolve;
        })
    );
    store.dispatch.mockResolvedValue({});
    const { comecar, comecando } = useComecarAAtender();

    const primeiro = comecar({ agente, inboxId: 10 });
    expect(comecando.value).toBe(true);
    const segundo = await comecar({ agente, inboxId: 10 });
    solta({});
    await primeiro;

    expect(segundo).toEqual({ ok: false, motivo: 'ocupado' });
    expect(canais.connect).toHaveBeenCalledTimes(1);
    expect(comecando.value).toBe(false);
  });
});

describe('mensagemDaRecusa', () => {
  it('reads the server explanation of a 422 (message or error)', () => {
    expect(mensagemDaRecusa(http(422, { message: 'Sem canal.' }))).toBe(
      'Sem canal.'
    );
    expect(mensagemDaRecusa(http(422, { error: 'Ocupado.' }))).toBe('Ocupado.');
  });

  it('is null for anything else', () => {
    expect(mensagemDaRecusa(http(500, { message: 'x' }))).toBeNull();
    expect(mensagemDaRecusa(semRede())).toBeNull();
    expect(mensagemDaRecusa(http(422))).toBeNull();
  });
});
