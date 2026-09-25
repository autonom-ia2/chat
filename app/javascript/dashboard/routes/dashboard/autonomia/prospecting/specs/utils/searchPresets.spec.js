// Catálogo das jogadas (#677, frente de modo): espelho de
// lib/services/scoring/presets.ts do Orth com as chaves de filtro do c2.
import {
  SEARCH_PRESETS,
  filtersMatchPreset,
  findPreset,
  presetFilters,
  presetsForScoreMode,
} from '../../utils/searchPresets';
import { defaultAdvancedLeadFilters } from '../../utils/advancedLeadFilters';

describe('searchPresets', () => {
  it('tem as seis jogadas do Orth, três por modo, com os filtros mapeados', () => {
    expect(
      SEARCH_PRESETS.map(({ id, scoreMode, filters }) => ({
        id,
        scoreMode,
        filters,
      }))
    ).toEqual([
      { id: 'vender-site', scoreMode: 'gbp', filters: { has_website: 'no' } },
      {
        id: 'gestao-reviews',
        scoreMode: 'gbp',
        filters: { rating_max: 4.2, reviews_min: 10 },
      },
      {
        id: 'otimizacao-gbp',
        scoreMode: 'gbp',
        filters: { has_phone: 'yes', has_website: 'yes', rating_min: 4 },
      },
      {
        id: 'prova-social',
        scoreMode: 'general',
        filters: { rating_min: 4.2 },
      },
      {
        id: 'mercado-maduro',
        scoreMode: 'general',
        filters: { rating_min: 4, reviews_min: 20 },
      },
      {
        id: 'presenca-digital',
        scoreMode: 'general',
        filters: { has_website: 'yes', has_phone: 'yes' },
      },
    ]);
  });

  it('só usa chaves que existem nos filtros avançados', () => {
    const known = Object.keys(defaultAdvancedLeadFilters());
    SEARCH_PRESETS.forEach(preset => {
      Object.keys(preset.filters).forEach(key => {
        expect(known).toContain(key);
      });
    });
  });

  it('filtra as jogadas pelo modo', () => {
    expect(presetsForScoreMode('gbp').map(preset => preset.id)).toEqual([
      'vender-site',
      'gestao-reviews',
      'otimizacao-gbp',
    ]);
    expect(presetsForScoreMode('general').map(preset => preset.id)).toEqual([
      'prova-social',
      'mercado-maduro',
      'presenca-digital',
    ]);
  });

  it('acha a jogada pelo id e devolve undefined para o resto', () => {
    expect(findPreset('prova-social').scoreMode).toBe('general');
    expect(findPreset('inventada')).toBeUndefined();
    expect(findPreset(null)).toBeUndefined();
  });

  it('monta os filtros da jogada sobre os filtros vazios', () => {
    expect(presetFilters(findPreset('gestao-reviews'))).toEqual({
      ...defaultAdvancedLeadFilters(),
      rating_max: 4.2,
      reviews_min: 10,
    });
  });

  describe('filtersMatchPreset', () => {
    const reviews = findPreset('gestao-reviews');

    it('bate com os filtros da própria jogada', () => {
      expect(filtersMatchPreset(presetFilters(reviews), reviews)).toBe(true);
    });

    it('trata número digitado como texto igual ao número', () => {
      const filters = {
        ...presetFilters(reviews),
        rating_max: '4.2',
        reviews_min: '10',
      };
      expect(filtersMatchPreset(filters, reviews)).toBe(true);
    });

    it('diverge quando um filtro da jogada muda ou é apagado', () => {
      expect(
        filtersMatchPreset(
          { ...presetFilters(reviews), rating_max: 4 },
          reviews
        )
      ).toBe(false);
      expect(
        filtersMatchPreset(
          { ...presetFilters(reviews), reviews_min: '' },
          reviews
        )
      ).toBe(false);
    });

    it('diverge quando entra um filtro que a jogada não tem', () => {
      expect(
        filtersMatchPreset(
          { ...presetFilters(reviews), has_phone: 'yes' },
          reviews
        )
      ).toBe(false);
    });

    it('trata vazio, nulo e ausente como a mesma coisa', () => {
      expect(
        filtersMatchPreset(
          { rating_max: 4.2, reviews_min: 10, has_phone: null, open_now: '' },
          reviews
        )
      ).toBe(true);
    });
  });
});
