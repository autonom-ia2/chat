import { selectDefinitions, fieldValue } from '../presentation';

describe('relationship presentation', () => {
  const definitions = [{ id: 1 }, { id: 2 }];
  it('keeps the legacy sidebar but adds nothing to details by default', () => {
    expect(selectDefinitions(definitions, {}, 'contact_sidebar')).toEqual(
      definitions
    );
    expect(selectDefinitions(definitions, {}, 'contact_details')).toEqual([]);
  });
  it('distinguishes empty selection from legacy and ignores removed definitions', () => {
    expect(
      selectDefinitions(
        definitions,
        { surfaces: { contact_sidebar: { mode: 'custom', ids: [] } } },
        'contact_sidebar'
      )
    ).toEqual([]);
    expect(
      selectDefinitions(
        definitions,
        { surfaces: { contact_details: { mode: 'custom', ids: [2, 9] } } },
        'contact_details'
      )
    ).toEqual([{ id: 2 }]);
  });
  it('preserves zero, false and date-only and clears an empty number', () => {
    expect(fieldValue('number', '0')).toBe(0);
    expect(fieldValue('number', '')).toBe(null);
    expect(fieldValue('checkbox', false)).toBe(false);
    expect(fieldValue('date', '2026-09-29')).toBe('2026-09-29');
  });
});
