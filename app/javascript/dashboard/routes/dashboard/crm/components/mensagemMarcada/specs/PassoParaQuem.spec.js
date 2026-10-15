import { flushPromises, mount } from '@vue/test-utils';
import PassoParaQuem from '../PassoParaQuem.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
const getCards = vi.fn();
vi.mock('dashboard/api/crmKanban', () => ({
  default: { getCards: (...args) => getCards(...args) },
}));

const CARDS = [
  { id: 1, title: 'Plano anual', contact: { name: 'Mariana' } },
  { id: 2, title: 'Vitrine', contact: { name: 'Roberto' } },
  { id: 3, title: 'Café', contact: { name: 'Lucas' } },
];
const ESTADO = {
  1: { conectada: true, oficial: true },
  2: { conectada: true, oficial: false },
  3: { conectada: false, oficial: false },
};
const paraAlvo = card => ({
  cardId: card.id,
  nome: card.contact.name,
  negocio: card.title,
  telefone: '',
  ...ESTADO[card.id],
});

describe('PassoParaQuem', () => {
  beforeEach(() => {
    getCards.mockReset();
    getCards.mockResolvedValue({ data: { payload: CARDS } });
  });

  it('mostra os mexidos por último e trata cada caixa do jeito dela', async () => {
    const wrapper = mount(PassoParaQuem, { props: { paraAlvo } });
    await flushPromises();

    expect(getCards).toHaveBeenCalledWith({ search: undefined, per_page: 6 });
    await wrapper.find('[data-para-quem="1"]').trigger('click');
    await wrapper.find('[data-para-quem="2"]').trigger('click');
    await wrapper.find('[data-para-quem="3"]').trigger('click');

    expect(wrapper.emitted('escolher')).toEqual([[CARDS[0]]]);
    expect(wrapper.emitted('abrirNegocio')).toEqual([[2]]);
    expect(wrapper.find('[data-para-quem="2"]').text()).toContain(
      'PELO_NEGOCIO'
    );
    expect(
      wrapper.find('[data-para-quem="3"]').attributes('aria-disabled')
    ).toBe('true');
  });
});
