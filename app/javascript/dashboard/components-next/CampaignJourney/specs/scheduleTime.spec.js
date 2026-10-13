import { timeZoneName } from '../scheduleTime';

// #1387 (L15): the review shows the zone by its name, not the IANA id.
describe('timeZoneName', () => {
  it('names the zone for people', () => {
    const nome = timeZoneName('America/Sao_Paulo', 'pt_BR');
    expect(nome).not.toBe('America/Sao_Paulo');
    expect(nome).toContain('Brasília');
  });

  it('names the zone at the scheduled instant (summer time)', () => {
    expect(timeZoneName('America/New_York', 'en', '2026-07-01T12:00:00Z')).toBe(
      'Eastern Daylight Time'
    );
    expect(timeZoneName('America/New_York', 'en', '2026-12-01T12:00:00Z')).toBe(
      'Eastern Standard Time'
    );
  });

  it('falls back to the id when the zone is unknown', () => {
    expect(timeZoneName('Nowhere/Zone', 'pt_BR')).toBe('Nowhere/Zone');
  });
});
