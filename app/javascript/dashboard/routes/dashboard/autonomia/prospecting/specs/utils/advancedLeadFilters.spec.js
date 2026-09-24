// Refino local dos leads (#677, frente B): as mesmas regras do motor
// (search_runner.rb) e da gaveta do Orth, para a busca aberta e para Listas.
import {
  activeAdvancedLeadFiltersCount,
  advancedFilterGroupCounts,
  defaultAdvancedLeadFilters,
  filterLeadsByAdvancedFilters,
} from '../../utils/advancedLeadFilters';

const lead = (name, extra = {}) => ({
  name,
  website: 'https://exemplo.com.br',
  phone: '+5541999990000',
  has_photos: true,
  open_now: true,
  opening_hours_summary: ['segunda-feira: 08:00 – 18:00'],
  rating: 4.5,
  reviews_count: 50,
  search_rank: 1,
  ...extra,
});

const LEADS = [
  lead('A'),
  lead('B', { has_photos: false, open_now: false, search_rank: 4 }),
  lead('C', { open_now: null, opening_hours_summary: null, search_rank: 7 }),
  lead('D', { rating: null, search_rank: 12 }),
  lead('E', { rating: 3.9, search_rank: 40 }),
];

const names = filters =>
  filterLeadsByAdvancedFilters(LEADS, {
    ...defaultAdvancedLeadFilters(),
    ...filters,
  }).map(item => item.name);

describe('advancedLeadFilters · refino local', () => {
  it('tem as chaves novas da gaveta, vazias por padrão', () => {
    expect(defaultAdvancedLeadFilters()).toEqual({
      has_website: '',
      has_phone: '',
      has_photos: '',
      open_now: '',
      has_opening_hours: '',
      rating_min: '',
      rating_max: '',
      reviews_min: '',
      outside_top: '',
      search_rank_max: '',
    });
  });

  it('fotos sim e não', () => {
    expect(names({ has_photos: 'yes' })).toEqual(['A', 'C', 'D', 'E']);
    expect(names({ has_photos: 'no' })).toEqual(['B']);
  });

  it('aberto agora só filtra com sim; não fica sem efeito, como no motor', () => {
    expect(names({ open_now: 'yes' })).toEqual(['A', 'D', 'E']);
    expect(names({ open_now: 'no' })).toEqual(['A', 'B', 'C', 'D', 'E']);
  });

  it('tem horário mantém só quem tem horário cadastrado', () => {
    expect(names({ has_opening_hours: 'yes' })).toEqual(['A', 'B', 'D', 'E']);
  });

  it('acima de descarta quem não tem nota; abaixo de deixa passar', () => {
    expect(names({ rating_min: 4 })).toEqual(['A', 'B', 'C']);
    expect(names({ rating_max: 4 })).toEqual(['D', 'E']);
  });

  it('faixa de posição no Google corta pelas duas pontas', () => {
    expect(names({ outside_top: 3 })).toEqual(['B', 'C', 'D', 'E']);
    expect(names({ outside_top: 3, search_rank_max: 10 })).toEqual(['B', 'C']);
  });

  it('conta um filtro por controle da gaveta, por grupo', () => {
    const filters = {
      ...defaultAdvancedLeadFilters(),
      has_website: 'no',
      rating_min: 4,
      rating_max: 5,
      outside_top: 2,
      search_rank_max: 20,
      open_now: 'yes',
      has_opening_hours: 'yes',
    };

    expect(advancedFilterGroupCounts(filters)).toEqual({
      pain: 1,
      qualification: 1,
      visibility: 1,
      operational: 2,
    });
    expect(activeAdvancedLeadFiltersCount(filters)).toBe(5);
    expect(
      activeAdvancedLeadFiltersCount({
        ...defaultAdvancedLeadFilters(),
        open_now: 'no',
      })
    ).toBe(0);
  });
});
