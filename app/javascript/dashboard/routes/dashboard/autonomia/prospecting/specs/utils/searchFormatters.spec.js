// Área da busca no histórico e nos resultados. Com a expansão de raio do Orth
// (#732 item 4), a busca que ficou com o raio maior mostra os dois raios.
import { formatSearchArea } from '../../utils/searchFormatters';

const t = (key, params) => (params ? `${key} ${JSON.stringify(params)}` : key);

describe('formatSearchArea', () => {
  it('mostra o raio da busca', () => {
    expect(formatSearchArea({ area_type: 'radius', radius: 2000 }, t)).toBe(
      'PROSPECTING.SEARCH.RADIUS_KM_VALUE {"value":2}'
    );
  });

  it('mostra o raio alcançado e o pedido quando a busca ficou com a expansão', () => {
    const search = {
      area_type: 'radius',
      radius: 2000,
      requested_radius: 1000,
      summary: { radius_expanded: true },
    };

    expect(formatSearchArea(search, t)).toBe(
      'PROSPECTING.SEARCH.RADIUS_EXPANDED_VALUE {"value":2,"requested":1}'
    );
  });

  it('não fala em expansão quando a tentativa não trouxe mais e o raio ficou o pedido', () => {
    const search = {
      area_type: 'radius',
      radius: 1500,
      requested_radius: 1500,
      summary: { radius_expanded: false },
    };

    expect(formatSearchArea(search, t)).toBe(
      'PROSPECTING.SEARCH.RADIUS_KM_VALUE {"value":"1.5"}'
    );
  });
});
