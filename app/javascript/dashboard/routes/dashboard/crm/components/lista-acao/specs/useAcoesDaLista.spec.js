import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { useAlert } from 'dashboard/composables';
import { useFaixas, TEMPO_DA_FAIXA } from '../useFaixas';
import { useAcoesDaLista } from '../useAcoesDaLista';

vi.mock('dashboard/api/crmKanban', () => ({
  default: {
    completeFollowUp: vi.fn(),
    createFollowUp: vi.fn(),
    rescheduleFollowUp: vi.fn(),
    updateCard: vi.fn(),
  },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/helper/deviseAuthHeaders', () => ({
  getDeviseAuthHeaders: () => ({ 'access-token': 'x', client: 'c', uid: 'u' }),
}));

const FUSO = 'America/Sao_Paulo';
const t = (chave, valores) =>
  valores ? `${chave}:${JSON.stringify(valores)}` : chave;

const montar = () => {
  const faixas = useFaixas();
  const dados = {
    tirarLinha: vi.fn(),
    trocarLinha: vi.fn(),
    atualizarContagem: vi.fn(),
    carregar: vi.fn(),
  };
  const anunciar = vi.fn();
  const acoes = useAcoesDaLista({
    t,
    fuso: () => FUSO,
    dados,
    faixas,
    anunciar,
    nomeDe: card => card.contact.name,
  });
  return { acoes, faixas, dados, anunciar };
};

const RETORNO = {
  id: 10,
  contact: { name: 'Ana' },
  action_group: 'retorno',
  next_follow_up_id: 77,
};

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(new Date('2026-10-28T15:00:00Z'));
  vi.clearAllMocks();
  CrmKanbanAPI.completeFollowUp.mockResolvedValue({ data: {} });
});
afterEach(() => vi.useRealTimers());

describe('"Feito" com "Desfazer" (decisão 3)', () => {
  it('mostra a faixa e só chama o complete quando ela sai, 10 s depois', async () => {
    const { acoes, faixas, dados, anunciar } = montar();

    acoes.feito(RETORNO);

    expect(faixas.faixas.value[10]).toMatchObject({ desfazivel: true });
    expect(anunciar).toHaveBeenCalledWith(
      'CRM_LISTA_ACAO.FAIXA.FEITO:{"nome":"Ana"}'
    );
    expect(CrmKanbanAPI.completeFollowUp).not.toHaveBeenCalled();

    await vi.advanceTimersByTimeAsync(TEMPO_DA_FAIXA);

    expect(dados.tirarLinha).toHaveBeenCalledWith(10);
    expect(CrmKanbanAPI.completeFollowUp).toHaveBeenCalledWith(77);
    expect(dados.atualizarContagem).toHaveBeenCalled();
    expect(faixas.faixas.value[10]).toBeUndefined();
  });

  it('"Desfazer" tira a faixa e nunca chama a API', async () => {
    const { acoes, faixas, dados } = montar();

    acoes.feito(RETORNO);
    acoes.desfazer(RETORNO);
    await vi.advanceTimersByTimeAsync(TEMPO_DA_FAIXA * 2);

    expect(faixas.faixas.value[10]).toBeUndefined();
    expect(CrmKanbanAPI.completeFollowUp).not.toHaveBeenCalled();
    expect(dados.tirarLinha).not.toHaveBeenCalled();
  });

  it('o mouse ou o foco na faixa seguram o tempo', async () => {
    const { acoes, faixas } = montar();

    acoes.feito(RETORNO);
    faixas.pausar(10);
    await vi.advanceTimersByTimeAsync(TEMPO_DA_FAIXA * 2);
    expect(CrmKanbanAPI.completeFollowUp).not.toHaveBeenCalled();

    faixas.seguir(10);
    await vi.advanceTimersByTimeAsync(TEMPO_DA_FAIXA);
    expect(CrmKanbanAPI.completeFollowUp).toHaveBeenCalledWith(77);
  });

  it('ao fechar a aba, o "Feito" pendente vai por fetch keepalive', () => {
    const fetch = vi.fn(() => Promise.resolve());
    vi.stubGlobal('fetch', fetch);
    window.history.pushState({}, '', '/app/accounts/3/crm');
    const { acoes, faixas } = montar();

    acoes.feito(RETORNO);
    faixas.sairTodas({ saindoDaPagina: true });

    expect(fetch).toHaveBeenCalledWith(
      '/api/v1/accounts/3/crm/follow_ups/77/complete',
      expect.objectContaining({ method: 'POST', keepalive: true })
    );
    expect(CrmKanbanAPI.completeFollowUp).not.toHaveBeenCalled();
    vi.unstubAllGlobals();
  });

  it('se o servidor recusar, avisa e recarrega a lista', async () => {
    CrmKanbanAPI.completeFollowUp.mockRejectedValue(new Error('403'));
    const { acoes, dados } = montar();

    acoes.feito(RETORNO);
    await vi.advanceTimersByTimeAsync(TEMPO_DA_FAIXA);

    expect(useAlert).toHaveBeenCalledWith('CRM_LISTA_ACAO.ERROS.ACAO');
    expect(dados.carregar).toHaveBeenCalled();
  });
});

describe('"Combinar retorno" e "Combinar outro"', () => {
  const PARADO = { id: 20, contact: { name: 'Bia' }, action_group: 'parado' };

  it('no parado, cria o lembrete para a pessoa no fuso da conta', async () => {
    CrmKanbanAPI.createFollowUp.mockResolvedValue({
      data: { payload: { id: 99 } },
    });
    const { acoes, faixas, dados } = montar();

    const ok = await acoes.combinar(PARADO, {
      quando: '2026-10-29T09:00',
      formatado: 'amanhã às 09:00',
    });

    expect(ok).toBe(true);
    expect(CrmKanbanAPI.createFollowUp).toHaveBeenCalledWith({
      card_id: 20,
      due_at: '2026-10-29T12:00:00.000Z',
      timezone: FUSO,
      title: 'CRM_LISTA_ACAO.COMBINAR.TITULO_DO_RETORNO:{"nome":"Bia"}',
      follow_up_type: 'task',
      automation_mode: 'reminder_only',
    });
    expect(faixas.faixas.value[20]).toMatchObject({ desfazivel: false });

    await vi.advanceTimersByTimeAsync(TEMPO_DA_FAIXA);
    expect(dados.trocarLinha).toHaveBeenCalledWith(20, {
      next_follow_up_id: 99,
      next_follow_up_due_at: '2026-10-29T12:00:00.000Z',
      action_group: 'demais',
    });
  });

  it('no retorno, "Combinar outro" adia o mesmo retorno (reschedule)', async () => {
    CrmKanbanAPI.rescheduleFollowUp.mockResolvedValue({
      data: { payload: { id: 77 } },
    });
    const { acoes } = montar();

    await acoes.combinar(RETORNO, {
      quando: '2026-10-28T17:00',
      formatado: 'hoje às 17:00',
    });

    expect(CrmKanbanAPI.rescheduleFollowUp).toHaveBeenCalledWith(
      77,
      '2026-10-28T20:00:00.000Z'
    );
    expect(CrmKanbanAPI.createFollowUp).not.toHaveBeenCalled();
  });

  it('horário que já passou: avisa e não chama a API', async () => {
    const { acoes } = montar();

    const ok = await acoes.combinar(PARADO, {
      quando: '2026-10-28T08:00',
      formatado: 'hoje às 08:00',
    });

    expect(ok).toBe(false);
    expect(useAlert).toHaveBeenCalledWith('CRM_LISTA_ACAO.ERROS.PASSOU');
    expect(CrmKanbanAPI.createFollowUp).not.toHaveBeenCalled();
  });
});

describe('"Passar para alguém" e "Ficar com este cliente" (decisão 2)', () => {
  it('grava só o dono do card', async () => {
    CrmKanbanAPI.updateCard.mockResolvedValue({
      data: { payload: { id: 30 } },
    });
    const { acoes, anunciar } = montar();
    const ninguem = { id: 30, contact: { name: 'Caio' }, owner_id: null };

    await acoes.passar(ninguem, { id: 7, name: 'Eu' }, { eu: true });

    expect(CrmKanbanAPI.updateCard).toHaveBeenCalledWith(30, { owner_id: 7 });
    expect(anunciar).toHaveBeenCalledWith(
      'CRM_LISTA_ACAO.FAIXA.FICOU:{"nome":"Caio"}'
    );
  });
});
