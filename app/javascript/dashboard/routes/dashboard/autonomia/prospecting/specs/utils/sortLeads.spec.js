// Ordenação dos leads da busca aberta (#678): campo e direção, como no Orth
// (Prioridade, Score, Rating, Reviews, Distância e Google), mais Data e Nome,
// que só o chat2you tem. Quem não tem o valor vai para o fim nas duas direções.
import {
  SORT_FIELDS,
  defaultSortDirection,
  parseSortKey,
  sortKeyFor,
  sortLeads,
} from '../../utils/sortLeads';
import { distanceKm, searchCenter } from '../../utils/leadDistance';

const lead = (name, extra = {}) => ({ name, ...extra });
const names = leads => leads.map(item => item.name);

describe('sortLeads', () => {
  it('lê e monta a chave com campo e direção, inclusive as salvas antes', () => {
    expect(parseSortKey('priority_desc')).toEqual({
      field: 'priority',
      direction: 'desc',
    });
    expect(parseSortKey('google_rank_asc')).toEqual({
      field: 'google_rank',
      direction: 'asc',
    });
    expect(parseSortKey('created_asc')).toEqual({
      field: 'created',
      direction: 'asc',
    });
    expect(parseSortKey(null)).toEqual({
      field: 'priority',
      direction: 'desc',
    });
    expect(parseSortKey('qualquer_coisa')).toEqual({
      field: 'priority',
      direction: 'desc',
    });
    expect(sortKeyFor('distance', 'asc')).toBe('distance_asc');
  });

  // Distância e Google começam do mais perto e da 1ª posição (a intenção do
  // Orth, que pelo seletor começava do pior).
  it('começa cada campo na direção que põe o melhor primeiro', () => {
    expect(SORT_FIELDS).toEqual([
      'priority',
      'score',
      'rating',
      'reviews',
      'distance',
      'google_rank',
      'created',
      'name',
    ]);
    expect(SORT_FIELDS.map(defaultSortDirection)).toEqual([
      'desc',
      'desc',
      'desc',
      'desc',
      'asc',
      'asc',
      'desc',
      'asc',
    ]);
  });

  it('ordena pela posição no Google nas duas direções, sem posição no fim', () => {
    const leads = [
      lead('Terceiro', { search_rank: 30 }),
      lead('Sem posição', { search_rank: null }),
      lead('Primeiro', { search_rank: 1 }),
      lead('Décimo', { search_rank: 10 }),
    ];

    expect(names(sortLeads(leads, 'google_rank_asc'))).toEqual([
      'Primeiro',
      'Décimo',
      'Terceiro',
      'Sem posição',
    ]);
    expect(names(sortLeads(leads, 'google_rank_desc'))).toEqual([
      'Terceiro',
      'Décimo',
      'Primeiro',
      'Sem posição',
    ]);
  });

  it('prioridade decrescente é a 1ª posição primeiro; crescente inverte', () => {
    const leads = [
      lead('Segunda', { priority_position: 2 }),
      lead('Sem posição', { priority_position: null, priority_score: 50 }),
      lead('Primeira', { priority_position: 1 }),
    ];

    expect(names(sortLeads(leads, 'priority_desc'))).toEqual([
      'Primeira',
      'Segunda',
      'Sem posição',
    ]);
    expect(names(sortLeads(leads, 'priority_asc'))).toEqual([
      'Segunda',
      'Primeira',
      'Sem posição',
    ]);
  });

  it('sem posição de prioridade desempata pela nota de prioridade', () => {
    const leads = [
      lead('Nota 30', { priority_score: 30 }),
      lead('Nota 90', { priority_score: 90 }),
    ];

    expect(names(sortLeads(leads, 'priority_desc'))).toEqual([
      'Nota 90',
      'Nota 30',
    ]);
  });

  it.each([
    ['score', 'score'],
    ['rating', 'rating'],
    ['reviews', 'reviews_count'],
  ])('%s decrescente e crescente, sem valor no fim', (field, attribute) => {
    const leads = [
      lead('Baixo', { [attribute]: 1 }),
      lead('Sem valor', { [attribute]: null }),
      lead('Alto', { [attribute]: 9 }),
    ];

    expect(names(sortLeads(leads, `${field}_desc`))).toEqual([
      'Alto',
      'Baixo',
      'Sem valor',
    ]);
    expect(names(sortLeads(leads, `${field}_asc`))).toEqual([
      'Baixo',
      'Alto',
      'Sem valor',
    ]);
  });

  it('ordena por nome e por data nas duas direções', () => {
    const leads = [
      lead('Beta', { created_at: '2026-09-02T10:00:00Z' }),
      lead('Alfa', { created_at: '2026-09-03T10:00:00Z' }),
      lead('Gama', { created_at: '2026-09-01T10:00:00Z' }),
    ];

    expect(names(sortLeads(leads, 'name_asc'))).toEqual([
      'Alfa',
      'Beta',
      'Gama',
    ]);
    expect(names(sortLeads(leads, 'name_desc'))).toEqual([
      'Gama',
      'Beta',
      'Alfa',
    ]);
    expect(names(sortLeads(leads, 'created_desc'))).toEqual([
      'Alfa',
      'Beta',
      'Gama',
    ]);
    expect(names(sortLeads(leads, 'created_asc'))).toEqual([
      'Gama',
      'Beta',
      'Alfa',
    ]);
  });

  it('ordena pela distância do centro da busca, sem coordenada no fim', () => {
    const center = { lat: -23.55, lng: -46.63 };
    const leads = [
      lead('Longe', { latitude: -23.65, longitude: -46.63 }),
      lead('Sem coordenada', { latitude: null, longitude: null }),
      lead('Perto', { latitude: -23.551, longitude: -46.63 }),
    ];

    expect(names(sortLeads(leads, 'distance_asc', { center }))).toEqual([
      'Perto',
      'Longe',
      'Sem coordenada',
    ]);
    expect(names(sortLeads(leads, 'distance_desc', { center }))).toEqual([
      'Longe',
      'Perto',
      'Sem coordenada',
    ]);
  });

  it('sem centro a distância não muda a ordem', () => {
    const leads = [
      lead('Primeiro', { latitude: -23.65, longitude: -46.63 }),
      lead('Segundo', { latitude: -23.551, longitude: -46.63 }),
    ];

    expect(names(sortLeads(leads, 'distance_asc'))).toEqual([
      'Primeiro',
      'Segundo',
    ]);
  });

  it('não altera a lista recebida', () => {
    const leads = [lead('B', { score: 1 }), lead('A', { score: 2 })];

    sortLeads(leads, 'score_desc');

    expect(names(leads)).toEqual(['B', 'A']);
  });
});

describe('leadDistance', () => {
  it('calcula a distância em km entre o centro e o lead', () => {
    const km = distanceKm(
      { lat: -23.55, lng: -46.63 },
      { latitude: '-23.65', longitude: '-46.63' }
    );

    expect(km).toBeCloseTo(11.1, 1);
  });

  it('devolve null sem centro ou sem coordenada do lead', () => {
    expect(distanceKm(null, { latitude: 1, longitude: 1 })).toBeNull();
    expect(distanceKm({ lat: 1, lng: 1 }, { latitude: null })).toBeNull();
  });

  it('acha o centro da busca pela área, pelos limites ou pelo local', () => {
    expect(
      searchCenter({ area_config: { center: { lat: '1', lng: 2 } } })
    ).toEqual({ lat: 1, lng: 2 });
    expect(
      searchCenter({
        area_config: { bounds: { north: 2, south: 0, east: 4, west: 2 } },
      })
    ).toEqual({ lat: 1, lng: 3 });
    expect(
      searchCenter({
        area_config: {
          path: [
            { lat: 0, lng: 0 },
            { lat: 2, lng: 0 },
            { lat: 2, lng: 4 },
          ],
        },
      })
    ).toEqual({ lat: 4 / 3, lng: 4 / 3 });
    expect(
      searchCenter({ location_latitude: '-25.4', location_longitude: '-49.2' })
    ).toEqual({ lat: -25.4, lng: -49.2 });
    expect(searchCenter({})).toBeNull();
    expect(searchCenter(null)).toBeNull();
  });
});
