import { computed, nextTick, ref } from 'vue';
import { flushPromises } from '@vue/test-utils';
import { useConversaAberta } from '../useConversaAberta';

// #1335: custo da mensagem escrita pela franquia do número (contrato da #1322):
// grátis até as que sobram; depois, tarifa de serviço. Sem franquia, tudo pago.
const http = vi.hoisted(() => ({ contagem: vi.fn(), escrever: vi.fn() }));
vi.mock('dashboard/api/conversaAberta', () => ({ default: http }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ locale: ref('pt_BR') }) }));

const resposta = franquia => ({
  data: {
    payload: {
      dentro: 900,
      fora: 300,
      fecham_logo: 6,
      conferido_em: '2026-10-13T12:00:00Z',
      precos: {
        modelo: { valor: '0.3217', moeda: 'BRL' },
        escrita: { valor: '0.035', moeda: 'BRL' },
      },
      franquia,
      campos: [{ chave: 'cliente.primeiro_nome', rotulo: 'Primeiro nome' }],
    },
  },
});

const montar = async () => {
  const janela = useConversaAberta(
    computed(() => ({ publicoId: 1, caixaId: 2, categoria: 'MARKETING' }))
  );
  await flushPromises();
  await nextTick();
  return janela;
};

describe('useConversaAberta', () => {
  beforeEach(() => vi.clearAllMocks());

  it('conta pelo endpoint próprio, com a categoria do modelo', async () => {
    http.contagem.mockResolvedValue(resposta({ limite: 1000, usadas: 230 }));

    const janela = await montar();

    expect(http.contagem).toHaveBeenCalledWith({
      campaignImportId: 1,
      inboxId: 2,
      categoria: 'MARKETING',
    });
    expect(janela.contagem.value.dentro).toBe(900);
    expect(janela.campos.value).toHaveLength(1);
  });

  it('cobra só o que passa das grátis que sobram', async () => {
    http.contagem.mockResolvedValue(resposta({ limite: 1000, usadas: 230 }));

    const janela = await montar();

    expect(janela.gratisRestantes.value).toBe(770);
    expect(janela.resumoDaEscrita(37).tipo).toBe('gratis');
    expect(janela.custoEscrita(37)).toBe(0);
    const resumo = janela.resumoDaEscrita(900);
    expect(resumo).toMatchObject({ tipo: 'passa', pagas: 130, gratis: 770 });
    expect(janela.custoEscrita(900)).toBeCloseTo(4.55, 5);
  });

  it('sem franquia lida, conta tudo como pago', async () => {
    http.contagem.mockResolvedValue(resposta(null));

    const janela = await montar();

    expect(janela.resumoDaEscrita(37).tipo).toBe('sem_franquia');
    expect(janela.custoEscrita(37)).toBeCloseTo(1.295, 5);
  });

  it('escreve pelo endpoint com o público, a caixa e a categoria', async () => {
    http.contagem.mockResolvedValue(resposta(null));
    http.escrever.mockResolvedValue({ data: { payload: { status: 'ok' } } });

    const janela = await montar();
    await janela.escrever({ objetivo: 'coleção nova', tom: 'curto' });

    expect(http.escrever).toHaveBeenCalledWith(
      expect.objectContaining({
        campaign_import_id: 1,
        inbox_id: 2,
        categoria: 'MARKETING',
        objetivo: 'coleção nova',
        tom: 'curto',
      })
    );
  });
});
