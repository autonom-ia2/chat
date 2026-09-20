import {
  timeZoneOptions,
  timeZoneOptionsWith,
  browserTimeZone,
} from '../businessHour';

describe('timeZoneOptionsWith', () => {
  it('keeps the list untouched when the timezone is already there', () => {
    const saoPaulo = timeZoneOptions().find(
      option => option.value === 'America/Sao_Paulo'
    );
    expect(saoPaulo).toBeTruthy();

    expect(timeZoneOptionsWith('America/Sao_Paulo')).toHaveLength(
      timeZoneOptions().length
    );
  });

  it('adds a timezone the list does not cover, such as the UTC default', () => {
    expect(timeZoneOptions().some(option => option.value === 'UTC')).toBe(
      false
    );

    const options = timeZoneOptionsWith('UTC');

    expect(options[0]).toEqual({ label: 'UTC (GMT+00:00)', value: 'UTC' });
    expect(options).toHaveLength(timeZoneOptions().length + 1);
  });

  it('makes the injected label readable', () => {
    expect(timeZoneOptionsWith('America/Porto_Velho')[0]).toEqual({
      label: 'America/Porto Velho',
      value: 'America/Porto_Velho',
    });
  });

  it('returns the plain list when there is no timezone yet', () => {
    expect(timeZoneOptionsWith(undefined)).toHaveLength(
      timeZoneOptions().length
    );
  });
});

describe('browserTimeZone', () => {
  it('uses the timezone reported by the browser', () => {
    const spy = vi.spyOn(Intl, 'DateTimeFormat').mockReturnValue({
      resolvedOptions: () => ({ timeZone: 'America/Sao_Paulo' }),
    });

    expect(browserTimeZone()).toBe('America/Sao_Paulo');

    spy.mockRestore();
  });

  it('falls back to UTC when the browser does not tell', () => {
    const spy = vi.spyOn(Intl, 'DateTimeFormat').mockImplementation(() => {
      throw new Error('sem Intl');
    });

    expect(browserTimeZone()).toBe('UTC');

    spy.mockRestore();
  });
});
