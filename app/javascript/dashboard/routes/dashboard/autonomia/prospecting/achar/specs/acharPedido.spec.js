import { criarFonte } from '../utils/acharFonte';
import { buscaDoPayload } from '../utils/acharLead';
import { diaEMes } from '../utils/acharQuando';
import {
  RAIO_MAXIMO,
  montarPedido,
  podeIrMaisLonge,
} from '../utils/acharPedido';

// #2693 — o pedido de busca pela fonte da API (sem demonstração): "Mais
// ajustes" e "Quem vem primeiro" chegam ao servidor; "Buscar de novo" e
// "Procurar mais longe" fazem uma busca nova sem cache. As chaves e os valores
// são os que SearchRunner#advanced_filter_matches? e #search_score_mode leem.
const CHAVES_DO_SERVIDOR = [
  'has_website',
  'has_phone',
  'has_photos',
  'open_now',
  'has_opening_hours',
  'rating_min',
  'rating_max',
  'reviews_min',
  'outside_top',
  'search_rank_max',
];
const SO_SIM = ['open_now', 'has_opening_hours'];
const SIM_OU_NAO = ['has_website', 'has_phone', 'has_photos'];

const LUGAR = {
  rotulo: 'Centro, Campinas, SP',
  placeId: 'abc',
  latitude: -22.9,
  longitude: -47.06,
};

const apiFalsa = () => ({
  createSearch: vi
    .fn()
    .mockResolvedValue({ data: { payload: { search: { id: 77 } } } }),
  getSearches: vi.fn(),
  getSettings: vi.fn(),
});

const confereAceito = filtros => {
  Object.entries(filtros).forEach(([chave, valor]) => {
    expect(CHAVES_DO_SERVIDOR).toContain(chave);
    if (SO_SIM.includes(chave)) expect(valor).toBe('yes');
    if (SIM_OU_NAO.includes(chave)) expect(['yes', 'no']).toContain(valor);
    if (!SO_SIM.includes(chave) && !SIM_OU_NAO.includes(chave)) {
      expect(Number.isFinite(Number(valor))).toBe(true);
    }
  });
};

describe('montarPedido: "Mais ajustes" vão para o servidor', () => {
  it('cada ajuste vira a chave que o motor entende, com valor aceito', () => {
    const pedido = montarPedido({
      oQue: ' Escritórios ',
      lugar: LUGAR,
      como: {
        km: 3,
        n: 20,
        primeiro: 'pouco',
        ajustes: {
          nota: 'n45',
          avaliacoes: 'n20',
          site: 'nao',
          fotos: 'tem',
          aberta: true,
          mostraHorario: true,
        },
      },
    });

    expect(pedido).toMatchObject({
      query: 'Escritórios',
      radius: 3000,
      requested_limit: 20,
      area_type: 'radius',
      area_config: { radius: 3000, place_id: 'abc' },
    });
    expect(pedido.metadata.score_mode).toBe('gbp');
    expect(pedido.metadata.advanced_filters).toEqual({
      rating_min: '4.5',
      reviews_min: '20',
      has_website: 'no',
      has_photos: 'yes',
      open_now: 'yes',
      has_opening_hours: 'yes',
    });
    confereAceito(pedido.metadata.advanced_filters);
  });

  it('"abaixo de 4" é nota máxima; sem ajustes, modo geral e nenhum filtro', () => {
    const abaixo = montarPedido({
      oQue: 'Bares',
      lugar: LUGAR,
      como: { km: 5, n: 40, ajustes: { nota: 'abaixo_4' } },
    });
    const semNada = montarPedido({
      oQue: 'Bares',
      lugar: LUGAR,
      como: { km: 5, n: 40, primeiro: 'melhores' },
    });

    expect(abaixo.metadata.advanced_filters).toEqual({ rating_max: '3.9' });
    confereAceito(abaixo.metadata.advanced_filters);
    expect(abaixo.metadata.score_mode).toBe('general');
    expect(semNada.metadata.advanced_filters).toEqual({});
    expect(semNada.metadata.score_mode).toBe('general');
  });

  it('pela fonte da API, criarBusca manda os ajustes e devolve o id', async () => {
    const api = apiFalsa();
    const fonte = criarFonte({ carregarDemo: null, api });
    const { searchId } = await fonte.criarBusca({
      oQue: 'Padarias',
      lugar: LUGAR,
      como: {
        km: 2,
        n: 20,
        primeiro: 'pouco',
        ajustes: { site: 'tem', avaliacoes: 'n10' },
      },
    });

    expect(fonte.usaDemo).toBe(false);
    expect(searchId).toBe(77);
    expect(api.createSearch).toHaveBeenCalledWith(
      expect.objectContaining({
        query: 'Padarias',
        metadata: expect.objectContaining({
          score_mode: 'gbp',
          advanced_filters: { has_website: 'yes', reviews_min: '10' },
        }),
      })
    );
  });
});

// A busca como o servidor devolve (search_payload): 3 km pedidos, 6 km
// alcançados pela expansão automática.
const buscaSalva = (extra = {}) =>
  buscaDoPayload({
    id: 9,
    query: 'Padarias',
    location: 'Taquaral, Campinas, SP',
    location_label: 'Taquaral, Campinas, SP',
    location_place_id: 'p1',
    location_latitude: -22.87,
    location_longitude: -47.05,
    radius: 6000,
    requested_radius: 3000,
    area_type: 'radius',
    area_config: { center: { lat: -22.87, lng: -47.05 }, radius: 6000 },
    requested_limit: 40,
    score_mode: 'gbp',
    advanced_filters: { rating_min: '4' },
    search_filters: { auto_expand_radius: true },
    preset_id: 'preset-1',
    user_id: 7,
    user_name: 'Lucas',
    ...extra,
  });

describe('"Buscar de novo" e "Procurar mais longe" pela API', () => {
  it('"Buscar de novo" refaz a busca salva sem cache, com o raio pedido', async () => {
    const api = apiFalsa();
    const fonte = criarFonte({ carregarDemo: null, api });
    const { searchId } = await fonte.repetirBusca({ busca: buscaSalva() });

    expect(searchId).toBe(77);
    expect(api.createSearch).toHaveBeenCalledWith({
      query: 'Padarias',
      location: 'Taquaral, Campinas, SP',
      radius: 3000,
      area_type: 'radius',
      area_config: { center: { lat: -22.87, lng: -47.05 }, radius: 3000 },
      requested_limit: 40,
      fresh: true,
      metadata: {
        location_place_id: 'p1',
        location_latitude: -22.87,
        location_longitude: -47.05,
        location_label: 'Taquaral, Campinas, SP',
        score_mode: 'gbp',
        advanced_filters: { rating_min: '4' },
        filters: { auto_expand_radius: true },
        preset_id: 'preset-1',
      },
    });
  });

  it('"Procurar mais longe" dobra o raio alcançado, até o teto de 50 km', async () => {
    const api = apiFalsa();
    const fonte = criarFonte({ carregarDemo: null, api });

    await fonte.repetirBusca({ busca: buscaSalva(), maisLonge: true });
    expect(api.createSearch.mock.calls[0][0]).toMatchObject({
      radius: 12000,
      area_config: { radius: 12000 },
      fresh: true,
    });

    await fonte.repetirBusca({
      busca: buscaSalva({ radius: 40000 }),
      maisLonge: true,
    });
    expect(api.createSearch.mock.calls[1][0].radius).toBe(RAIO_MAXIMO);
  });

  it('só oferece "mais longe" na busca por raio abaixo do teto', () => {
    expect(podeIrMaisLonge(buscaSalva().pedido)).toBe(true);
    expect(podeIrMaisLonge(buscaSalva({ radius: RAIO_MAXIMO }).pedido)).toBe(
      false
    );
    expect(
      podeIrMaisLonge(buscaSalva({ area_type: 'polygon', radius: 0 }).pedido)
    ).toBe(false);
    expect(podeIrMaisLonge(undefined)).toBe(false);
  });
});

describe('"Suas buscas" pela API', () => {
  it('lê a página pedida e diz se há mais (meta.has_more)', async () => {
    const api = apiFalsa();
    api.getSearches.mockResolvedValue({
      data: {
        payload: [{ id: 3, query: 'Bares', user_id: 7, user_name: 'Lucas' }],
        meta: { page: 2, has_more: true },
      },
    });
    const fonte = criarFonte({ carregarDemo: null, api, usuarioId: 7 });
    const { buscas, temMais } = await fonte.buscas(2);

    expect(api.getSearches).toHaveBeenCalledWith({ page: 2 });
    expect(temMais).toBe(true);
    expect(buscas[0]).toMatchObject({
      id: 3,
      feitaPor: 'Lucas',
      feitaPorId: 7,
    });
  });

  it('a porta traz as buscas com o dono e o lugar salvo da própria pessoa', async () => {
    const api = apiFalsa();
    api.getSettings.mockResolvedValue({ data: { payload: {} } });
    api.getSearches.mockResolvedValue({
      data: {
        payload: [
          {
            id: 1,
            query: 'Bares',
            user_id: 8,
            user_name: 'Paula',
            location_place_id: 'da-paula',
            location_label: 'Cambuí',
          },
          {
            id: 2,
            query: 'Padarias',
            user_id: 7,
            user_name: 'Lucas',
            location_place_id: 'do-lucas',
            location_label: 'Taquaral',
          },
        ],
        meta: { has_more: false },
      },
    });
    const fonte = criarFonte({ carregarDemo: null, api, usuarioId: 7 });
    const { ultimas, lugarSalvo } = await fonte.porta();

    expect(ultimas.map(busca => [busca.feitaPorId, busca.feitaPor])).toEqual([
      [8, 'Paula'],
      [7, 'Lucas'],
    ]);
    expect(lugarSalvo).toMatchObject({ placeId: 'do-lucas' });
  });
});

describe('mandar ao funil pela API', () => {
  it('created e existing voltam com o card; failed, com o motivo', async () => {
    const api = {
      createCrmCards: vi.fn().mockResolvedValue({
        data: {
          payload: {
            created: [{ lead_id: 1, card_id: 501, contact_id: 9 }],
            existing: [{ lead_id: 2, card_id: 502 }],
            failed: [{ lead_id: 3, reason_code: 'invalid_data', message: 'x' }],
          },
        },
      }),
    };
    const fonte = criarFonte({ carregarDemo: null, api });
    const resumo = await fonte.mandarParaFunil({
      ids: [1, 2, 3],
      funilId: 4,
      etapaId: 40,
    });

    expect(api.createCrmCards).toHaveBeenCalledWith({
      leadIds: [1, 2, 3],
      pipelineId: 4,
      stageId: 40,
      ownerId: null,
    });
    expect(resumo).toEqual({
      created: [{ id: 1, cardId: 501 }],
      existing: [{ id: 2, cardId: 502 }],
      failed: [{ id: 3, motivo: 'invalid_data', codigo: null }],
    });
  });

  // #2694: o dono escolhido vai junto; a recusa do servidor guarda o código.
  it('o dono escolhido vai como ownerId e a recusa do pedido guarda o código', async () => {
    const api = {
      createCrmCards: vi.fn().mockRejectedValue({
        response: {
          data: { code: 'prospecting.crm_send.owner_forbidden', error: 'x' },
        },
      }),
    };
    const fonte = criarFonte({ carregarDemo: null, api });
    const resumo = await fonte.mandarParaFunil({
      ids: [1],
      funilId: 4,
      etapaId: 40,
      donoId: 8,
    });

    expect(api.createCrmCards).toHaveBeenCalledWith(
      expect.objectContaining({ ownerId: 8 })
    );
    expect(resumo.failed).toEqual([
      {
        id: 1,
        motivo: 'request_failed',
        codigo: 'prospecting.crm_send.owner_forbidden',
      },
    ]);
  });
});

describe('com quem fica pela API (#2694)', () => {
  it('pede ao servidor as pessoas do funil, com "você" no topo', async () => {
    const api = {
      getCrmOwners: vi.fn().mockResolvedValue({
        data: {
          payload: [
            { id: 8, name: 'Paula Ribeiro' },
            { id: 7, name: 'Lucas Andrade' },
          ],
        },
      }),
    };
    const fonte = criarFonte({ carregarDemo: null, api, usuarioId: 7 });

    expect(await fonte.pessoas({ funilId: 4 })).toEqual([
      { id: 'voce', nome: 'Lucas Andrade', voce: true },
      { id: 8, nome: 'Paula Ribeiro' },
    ]);
    expect(api.getCrmOwners).toHaveBeenCalledWith(4);
  });

  it('sem funil, só "você", sem perguntar ao servidor', async () => {
    const api = { getCrmOwners: vi.fn() };
    const fonte = criarFonte({
      carregarDemo: null,
      api,
      usuarioId: 7,
      usuarioNome: 'Lucas Andrade',
    });

    expect(await fonte.pessoas()).toEqual([
      { id: 'voce', nome: 'Lucas Andrade', voce: true },
    ]);
    expect(api.getCrmOwners).not.toHaveBeenCalled();
  });
});

describe('data do nome da lista na língua do painel', () => {
  it('usa a língua do i18n (pt_BR e en), não pt-BR fixo', () => {
    const data = new Date(2026, 10, 7);

    expect(diaEMes(data, 'pt_BR')).toBe('07/11');
    expect(diaEMes(data, 'en')).toBe('11/07');
  });
});
