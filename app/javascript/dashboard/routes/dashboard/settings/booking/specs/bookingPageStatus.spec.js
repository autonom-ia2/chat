import { PAGE_STATUS, isDraftPage, pageStatus } from '../bookingPageStatus';

// A regra única do selo e da gaveta do agente (#1370): no ar, pausada ou rascunho.
describe('bookingPageStatus', () => {
  it('reads live, paused and draft like the page card', () => {
    expect(pageStatus({ enabled: true, missing: ['host'] })).toBe(
      PAGE_STATUS.LIVE
    );
    expect(pageStatus({ enabled: false, missing: [] })).toBe(
      PAGE_STATUS.PAUSED
    );
    expect(pageStatus({ enabled: false })).toBe(PAGE_STATUS.PAUSED);
    expect(pageStatus({ enabled: false, missing: ['host'] })).toBe(
      PAGE_STATUS.DRAFT
    );
    expect(pageStatus(undefined)).toBe(PAGE_STATUS.PAUSED);
  });

  it('a draft is only the unpublished page with something missing', () => {
    expect(isDraftPage({ enabled: false, missing: ['location'] })).toBe(true);
    expect(isDraftPage({ enabled: false, missing: [] })).toBe(false);
    expect(isDraftPage({ enabled: true, missing: ['location'] })).toBe(false);
  });
});
