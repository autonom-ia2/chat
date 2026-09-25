// Jogadas salvas (#732): a jogada da conta entra no mesmo formato das prontas,
// aparece na grade do modo dela e tem o resumo dos filtros em etiquetas.
import {
  filterSummaryTags,
  filtersMatchPreset,
  findPreset,
  presetFilters,
  presetsForScoreMode,
  savedPresetToPreset,
} from '../../utils/searchPresets';
import { defaultAdvancedLeadFilters } from '../../utils/advancedLeadFilters';

const savedPayload = (extra = {}) => ({
  id: 7,
  preset_id: 'saved-7',
  name: 'Sem site com telefone',
  score_mode: 'gbp',
  filters: { has_website: 'no', has_phone: 'yes' },
  ...extra,
});

const t = (key, values) => (values ? `${key}(${JSON.stringify(values)})` : key);
const TAG = key => `PROSPECTING.SEARCH.SAVED_PRESETS.TAGS.${key}`;

describe('jogadas salvas', () => {
  it('vira jogada com o id da busca, o nome dado e os filtros guardados', () => {
    expect(savedPresetToPreset(savedPayload())).toMatchObject({
      id: 'saved-7',
      savedId: 7,
      scoreMode: 'gbp',
      name: 'Sem site com telefone',
      filters: { has_website: 'no', has_phone: 'yes' },
      isSaved: true,
    });
  });

  it('aparece depois das prontas e só no modo em que foi salva', () => {
    const saved = [
      savedPresetToPreset(savedPayload()),
      savedPresetToPreset(
        savedPayload({ id: 8, preset_id: 'saved-8', score_mode: 'general' })
      ),
    ];

    expect(presetsForScoreMode('gbp', saved).map(preset => preset.id)).toEqual([
      'vender-site',
      'gestao-reviews',
      'otimizacao-gbp',
      'saved-7',
    ]);
    expect(
      presetsForScoreMode('general', saved).map(preset => preset.id)
    ).toEqual([
      'prova-social',
      'mercado-maduro',
      'presenca-digital',
      'saved-8',
    ]);
  });

  it('é achada pelo id junto com as prontas, e a apagada some', () => {
    const saved = [savedPresetToPreset(savedPayload())];

    expect(findPreset('saved-7', saved).name).toBe('Sem site com telefone');
    expect(findPreset('vender-site', saved).id).toBe('vender-site');
    expect(findPreset('saved-9', saved)).toBeUndefined();
    expect(findPreset('saved-7')).toBeUndefined();
  });

  it('aplica e reconhece os filtros como as prontas', () => {
    const preset = savedPresetToPreset(savedPayload());
    const filters = presetFilters(preset);

    expect(filters).toEqual({
      ...defaultAdvancedLeadFilters(),
      has_website: 'no',
      has_phone: 'yes',
    });
    expect(filtersMatchPreset(filters, preset)).toBe(true);
    expect(filtersMatchPreset({ ...filters, rating_min: 4 }, preset)).toBe(
      false
    );
  });

  it('resume os filtros preenchidos em etiquetas, na ordem da gaveta', () => {
    expect(
      filterSummaryTags(
        {
          ...defaultAdvancedLeadFilters(),
          has_website: 'no',
          has_phone: 'yes',
          has_photos: 'yes',
          rating_min: 4,
          rating_max: '4.5',
          reviews_min: 10,
          outside_top: 3,
          search_rank_max: 20,
          open_now: 'yes',
          has_opening_hours: 'yes',
        },
        t
      )
    ).toEqual([
      TAG('HAS_WEBSITE_NO'),
      TAG('HAS_PHOTOS_YES'),
      `${TAG('REVIEWS_MIN')}({"value":10})`,
      `${TAG('RATING_MIN')}({"value":4})`,
      `${TAG('RATING_MAX')}({"value":"4.5"})`,
      `${TAG('OUTSIDE_TOP')}({"value":3})`,
      `${TAG('SEARCH_RANK_MAX')}({"value":20})`,
      TAG('HAS_PHONE_YES'),
      TAG('OPEN_NOW'),
      TAG('HAS_OPENING_HOURS'),
    ]);
    expect(filterSummaryTags(defaultAdvancedLeadFilters(), t)).toEqual([]);
  });
});
