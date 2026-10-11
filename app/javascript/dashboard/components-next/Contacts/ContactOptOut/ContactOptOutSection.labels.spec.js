import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import ContactOptOutSection from './ContactOptOutSection.vue';

// Texto real do rótulo da origem (chat#1325), em en e pt_BR. Fica num arquivo à parte porque o outro spec compara
// chaves, com o i18n vazio do setup global.
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const i18n = withFullI18n('en');

const mountFollowUpReply = () =>
  mount(ContactOptOutSection, {
    props: {
      contact: {
        id: 7,
        optedOutAt: 1790000000,
        optOutSource: 'follow_up_reply',
      },
    },
  });

describe('ContactOptOutSection: rótulo da recusa pedida no follow-up', () => {
  it.each([
    ['en', 'Asked to stop in a follow-up reply', 'Reactivate follow-up'],
    ['pt_BR', 'Pediu para parar no follow-up', 'Reativar retorno automático'],
  ])(
    'em %s mostra a origem e onde a recusa sai, sem botão de desfazer',
    (locale, label, whereItGoes) => {
      i18n.global.locale.value = locale;
      const wrapper = mountFollowUpReply();

      expect(wrapper.get('[data-test="opt-out-details"]').text()).toContain(
        label
      );
      expect(wrapper.get('[data-test="opt-out-origin-hint"]').text()).toContain(
        whereItGoes
      );
      expect(wrapper.find('[data-test="opt-out-action"]').exists()).toBe(false);
    }
  );
});
