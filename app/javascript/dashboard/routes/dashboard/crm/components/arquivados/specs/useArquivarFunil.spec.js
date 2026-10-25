import { flushPromises } from '@vue/test-utils';
import CrmArquivadosAPI from 'dashboard/api/crmArquivados';
import { useArquivarFunil } from '../useArquivarFunil';

vi.mock('dashboard/api/crmArquivados', () => ({
  default: { previaDoArquivarFunil: vi.fn(), arquivarFunil: vi.fn() },
}));

const vendas = { id: 1, name: 'Vendas', is_default: true };
const pos = { id: 2, name: 'Pós-venda', is_default: false };
const extra = { id: 3, name: 'Extra', is_default: false };
const etapas = {
  1: [{ id: 11, name: 'Novo' }],
  2: [
    { id: 21, name: 'Boas-vindas' },
    { id: 22, name: 'Acompanhamento' },
  ],
  3: [{ id: 31, name: 'Entrada' }],
};
const montar = () =>
  useArquivarFunil({ carregarEtapas: id => Promise.resolve(etapas[id]) });

const previa = (payload = {}) =>
  CrmArquivadosAPI.previaDoArquivarFunil.mockResolvedValue({
    data: {
      payload: {
        open_cards_count: 2,
        inboxes: [{ id: 5, name: 'WhatsApp', auto_create_card: true }],
        follow_ups_count: 1,
        follow_up_series_count: 0,
        upcoming_meetings_count: 1,
        ...payload,
      },
    },
  });

describe('useArquivarFunil', () => {
  beforeEach(() => vi.clearAllMocks());

  it('único funil ativo: não deixa arquivar e nem pergunta ao servidor', async () => {
    const estado = montar();
    await estado.abrir({ alvo: vendas, ativos: [vendas] });
    expect(estado.passo.value).toBe('unico');
    expect(CrmArquivadosAPI.previaDoArquivarFunil).not.toHaveBeenCalled();
  });

  it('funil principal: pede o novo principal antes e manda junto', async () => {
    previa();
    CrmArquivadosAPI.arquivarFunil.mockResolvedValue({ data: { payload: {} } });
    const estado = montar();
    await estado.abrir({ alvo: vendas, ativos: [vendas, pos, extra] });
    expect(estado.passo.value).toBe('principal');
    expect(estado.pronto.value).toBe(false);
    estado.novoPrincipal.value = 3;
    await estado.continuarComPrincipal();
    await flushPromises();
    expect(estado.passo.value).toBe('escolha');
    expect(estado.funilDestino.value).toBe(3);
    expect(estado.funilDasCaixas.value).toBe(3);
    await estado.arquivar();
    expect(CrmArquivadosAPI.arquivarFunil).toHaveBeenCalledWith(1, {
      move_to_stage_id: 31,
      inboxes_to_pipeline_id: 3,
      new_default_pipeline_id: 3,
    });
  });

  it('já vem marcado: mover os cards e passar as caixas para o mesmo funil', async () => {
    previa();
    CrmArquivadosAPI.arquivarFunil.mockResolvedValue({ data: { payload: {} } });
    const estado = montar();
    await estado.abrir({ alvo: pos, ativos: [vendas, pos] });
    await flushPromises();
    expect(estado.destino.value).toBe('mover');
    expect(estado.caixas.value).toBe('passar');
    expect(estado.pronto.value).toBe(true);
    await estado.arquivar();
    expect(CrmArquivadosAPI.arquivarFunil).toHaveBeenCalledWith(2, {
      move_to_stage_id: 11,
      inboxes_to_pipeline_id: 1,
    });
  });

  it('caixas escolhidas à mão não seguem mais o destino dos cards', async () => {
    previa();
    const estado = montar();
    await estado.abrir({ alvo: extra, ativos: [vendas, pos, extra] });
    await estado.escolherFunilDasCaixas(2);
    await estado.escolherDestino(1);
    expect(estado.funilDasCaixas.value).toBe(2);
    expect(estado.etapaDestino.value).toBe(11);
  });

  it('guardar junto e deixar as caixas: sem destino, pede para parar os retornos', async () => {
    previa();
    CrmArquivadosAPI.arquivarFunil.mockResolvedValue({ data: { payload: {} } });
    const estado = montar();
    await estado.abrir({ alvo: pos, ativos: [vendas, pos] });
    estado.destino.value = 'guardar';
    estado.caixas.value = 'parar';
    await estado.arquivar();
    expect(CrmArquivadosAPI.arquivarFunil).toHaveBeenCalledWith(2, {
      stop_follow_ups: true,
    });
    expect(estado.retornos.value).toBe(1);
    expect(estado.reunioes.value).toBe(1);
  });

  it('sem cards abertos e sem caixas, não manda nada além do arquivar', async () => {
    previa({ open_cards_count: 0, inboxes: [] });
    CrmArquivadosAPI.arquivarFunil.mockResolvedValue({ data: { payload: {} } });
    const estado = montar();
    await estado.abrir({ alvo: pos, ativos: [vendas, pos] });
    expect(estado.pronto.value).toBe(true);
    await estado.arquivar();
    expect(CrmArquivadosAPI.arquivarFunil).toHaveBeenCalledWith(2, {});
  });

  it('erro na prévia: não fica pronto', async () => {
    CrmArquivadosAPI.previaDoArquivarFunil.mockRejectedValue(new Error('x'));
    const estado = montar();
    await estado.abrir({ alvo: pos, ativos: [vendas, pos] });
    expect(estado.erroPrevia.value).toBeTruthy();
    expect(estado.pronto.value).toBe(false);
  });

  it('recusa depois de parte dos cards levada (#2145): a prévia volta com os abertos de agora', async () => {
    previa();
    const estado = montar();
    await estado.abrir({ alvo: pos, ativos: [vendas, pos, extra] });
    expect(estado.abertos.value).toBe(2);

    previa({ open_cards_count: 1 });
    await estado.recarregarPrevia();
    await flushPromises();

    expect(CrmArquivadosAPI.previaDoArquivarFunil).toHaveBeenLastCalledWith(2);
    expect(estado.abertos.value).toBe(1);
  });
});
