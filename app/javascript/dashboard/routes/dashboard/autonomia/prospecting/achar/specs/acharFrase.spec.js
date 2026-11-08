import * as demoDados from '../demo/acharDemo';
import { criarFonte } from '../utils/acharFonte';
import { ajustesDosFiltros, filtrosDosAjustes } from '../utils/acharPedido';

// Pedido em uma frase (#2696): as duas fontes (API e demonstração) entregam o
// mesmo formato à porta, e os filtros da IA voltam às escolhas da tela.
const carregarDemo = () => Promise.resolve(demoDados);
const fonteDemo = estado =>
  criarFonte({ demo: estado, carregarDemo, atraso: 0 });
const fonteApi = api => criarFonte({ api, crm: {} });

const respostaDaApi = payload => ({
  interpretSearch: vi.fn().mockResolvedValue({ data: { payload } }),
});

describe('interpretar: o mesmo contrato na API e na demonstração', () => {
  it('as chaves do que volta são as mesmas', async () => {
    const daDemo = await fonteDemo('porta').interpretar('padarias');
    const api = respostaDaApi(demoDados.FRASE_ENTENDIDA);
    const daApi = await fonteApi(api).interpretar('padarias');

    expect(Object.keys(daApi).sort()).toEqual(Object.keys(daDemo).sort());
    expect(daApi).toEqual(daDemo);
    expect(api.interpretSearch).toHaveBeenCalledWith('padarias');
  });

  it('as duas fontes têm interpretar e a porta diz se a IA está pronta', async () => {
    const api = {
      ...respostaDaApi({}),
      getSettings: vi.fn().mockResolvedValue({
        data: { payload: { ai_credential_configured: true } },
      }),
      getSearches: vi.fn().mockResolvedValue({ data: { payload: [] } }),
    };
    const portaApi = await fonteApi(api).porta();
    const portaDemo = await fonteDemo('porta').porta();

    expect(typeof fonteDemo('porta').interpretar).toBe('function');
    expect(typeof fonteApi(api).interpretar).toBe('function');
    expect(portaApi.iaPronta).toBe(true);
    expect(portaDemo.iaPronta).toBe(true);
    expect((await fonteDemo('porta-sem-ia').porta()).iaPronta).toBe(false);
  });

  it('o que a IA entendeu vira os nomes da porta', async () => {
    const api = respostaDaApi({
      status: 'understood',
      what: 'restaurantes',
      where: null,
      advanced_filters: { reviews_min: '50', open_now: 'yes' },
      score_mode: 'gbp',
      left_out: null,
    });

    expect(await fonteApi(api).interpretar('x')).toEqual({
      entendeu: true,
      oQue: 'restaurantes',
      onde: null,
      ajustes: { avaliacoes: 'n50', aberta: true },
      primeiro: 'pouco',
      ficouDeFora: null,
    });
  });

  it('"não entendi" volta sem nada preenchido', async () => {
    const entendido = await fonteDemo('porta-frase-nao-entendeu').interpretar(
      'oi'
    );

    expect(entendido).toMatchObject({
      entendeu: false,
      oQue: null,
      onde: null,
      ajustes: {},
    });
  });

  it('a recusa da API leva o código do servidor', async () => {
    const api = {
      interpretSearch: vi.fn().mockRejectedValue({
        response: { data: { code: 'prospecting.interpret.ai_failed' } },
      }),
    };

    await expect(fonteApi(api).interpretar('x')).rejects.toMatchObject({
      codigo: 'prospecting.interpret.ai_failed',
    });
    await expect(
      fonteDemo('porta-frase-erro').interpretar('x')
    ).rejects.toBeTruthy();
  });
});

describe('ajustesDosFiltros', () => {
  it('é o caminho de volta de filtrosDosAjustes', () => {
    const ajustes = {
      nota: 'n45',
      avaliacoes: 'n20',
      site: 'nao',
      fotos: 'tem',
      aberta: true,
      mostraHorario: true,
    };

    expect(ajustesDosFiltros(filtrosDosAjustes(ajustes))).toEqual(ajustes);
    expect(ajustesDosFiltros({ rating_max: '3.9' })).toEqual({
      nota: 'abaixo_4',
    });
  });

  it('valor que a tela não tem fica de fora', () => {
    expect(
      ajustesDosFiltros({ rating_min: '2', has_website: 'talvez' })
    ).toEqual({});
  });
});
