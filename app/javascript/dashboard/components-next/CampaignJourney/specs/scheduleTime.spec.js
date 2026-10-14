import { accountTimeZone } from '../scheduleTime';

// #1456: o fuso é o da conta, o mesmo que a plataforma usa (Configurações da
// conta grava custom_attributes.timezone e o servidor copia para
// settings.reporting_timezone). O navegador só quando a conta não tem fuso.
describe('accountTimeZone', () => {
  it('reads the zone chosen in the account settings', () => {
    expect(
      accountTimeZone({ custom_attributes: { timezone: 'America/Cuiaba' } })
    ).toBe('America/Cuiaba');
  });

  it('falls back to the reporting zone the server keeps in sync', () => {
    expect(
      accountTimeZone({ settings: { reporting_timezone: 'America/Manaus' } })
    ).toBe('America/Manaus');
  });

  it('ignores a zone that is not real', () => {
    expect(
      accountTimeZone({
        custom_attributes: { timezone: 'Nowhere/Zone' },
        settings: { reporting_timezone: 'America/Belem' },
      })
    ).toBe('America/Belem');
  });
});
