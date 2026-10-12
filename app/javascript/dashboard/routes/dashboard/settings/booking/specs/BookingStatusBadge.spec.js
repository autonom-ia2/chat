import { mount } from '@vue/test-utils';
import BookingStatusBadge from '../components/BookingStatusBadge.vue';

// O selo de situação (#1371) é o mesmo no cartão da lista e na gaveta do
// agente: texto, classes e a chave de cada situação.
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const CASES = [
  ['LIVE', 'bg-n-teal-3', 'bg-n-teal-9'],
  ['PAUSED', 'bg-n-slate-3', 'bg-n-slate-9'],
  ['DRAFT', 'bg-n-amber-3', 'bg-n-amber-9'],
];

describe('BookingStatusBadge', () => {
  it.each(CASES)('mostra %s com o texto e as cores dele', (status, bg, dot) => {
    const badge = mount(BookingStatusBadge, { props: { status } });
    const root = badge.find('[data-status]');
    expect(root.text()).toBe(`BOOKING.CARD.STATUS.${status}`);
    expect(root.attributes('data-status-key')).toBe(status);
    expect(root.classes()).toContain(bg);
    expect(root.find('[aria-hidden="true"]').classes()).toContain(dot);
  });

  it('deduz a situação da página como o cartão: no ar, pausada ou rascunho', () => {
    const keyOf = page =>
      mount(BookingStatusBadge, { props: { page } })
        .find('[data-status]')
        .attributes('data-status-key');
    expect(keyOf({ enabled: true, missing: ['host'] })).toBe('LIVE');
    expect(keyOf({ enabled: false, missing: [] })).toBe('PAUSED');
    expect(keyOf({ enabled: false })).toBe('PAUSED');
    expect(keyOf({ enabled: false, missing: ['host'] })).toBe('DRAFT');
  });

  it('a situação pronta vale mais que a página', () => {
    const badge = mount(BookingStatusBadge, {
      props: { status: 'DRAFT', page: { enabled: true } },
    });
    expect(badge.attributes('data-status-key')).toBe('DRAFT');
  });
});
