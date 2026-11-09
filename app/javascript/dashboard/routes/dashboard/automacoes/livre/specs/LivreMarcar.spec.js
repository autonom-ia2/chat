import { mount } from '@vue/test-utils';
import LivreMarcar from '../components/LivreMarcar.vue';

// #2702 G29 — o "Pôr" etiqueta também aceita um dado ("o anúncio do
// formulário"): a etiqueta sai com o nome que o dado tiver na hora. Na receita
// vai `{ $valor }`; a pessoa vê o nome do dado entre colchetes.
const EscolhaFalsa = {
  name: 'ChoiceSelect',
  props: ['options', 'modelValue'],
  emits: ['update:modelValue'],
  template: '<div data-escolha-falsa />',
};

const DADOS = [
  { value: 'card.anuncio', label: 'Anúncio do formulário' },
  { value: 'contato.nome', label: 'Nome do contato' },
];

const montar = (props = {}) =>
  mount(LivreMarcar, {
    props: {
      rotulo: 'Pôr',
      opcoes: [{ value: 'vip', label: 'vip' }],
      ...props,
    },
    global: {
      mocks: { $t: chave => chave },
      stubs: { ChoiceSelect: EscolhaFalsa },
    },
  });

describe('LivreMarcar', () => {
  it('sem dados, só marca a lista: nada de "pôr um dado"', () => {
    expect(montar().find('[data-por-dado]').exists()).toBe(false);
  });

  it('põe um dado na lista e não o oferece de novo', async () => {
    const wrapper = montar({ dados: DADOS, modelValue: ['vip'] });

    wrapper
      .findComponent(EscolhaFalsa)
      .vm.$emit('update:modelValue', 'card.anuncio');

    expect(wrapper.emitted('update:modelValue').at(-1)[0]).toEqual([
      'vip',
      { $valor: 'card.anuncio' },
    ]);

    await wrapper.setProps({
      modelValue: ['vip', { $valor: 'card.anuncio' }],
    });
    expect(wrapper.findComponent(EscolhaFalsa).props('options')).toEqual([
      DADOS[1],
    ]);
  });

  it('mostra o dado posto pelo nome e o tira com um toque', async () => {
    const wrapper = montar({
      dados: DADOS,
      modelValue: ['vip', { $valor: 'card.anuncio' }],
    });

    const posto = wrapper.find('[data-dado-posto]');
    expect(posto.text()).toContain('[Anúncio do formulário]');

    await posto.trigger('click');
    expect(wrapper.emitted('update:modelValue').at(-1)[0]).toEqual(['vip']);
  });
});
