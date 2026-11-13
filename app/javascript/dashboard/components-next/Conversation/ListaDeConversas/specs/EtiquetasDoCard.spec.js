import { createStore } from 'vuex';
import { mount, enableAutoUnmount } from '@vue/test-utils';
import EtiquetasDoCard from '../EtiquetasDoCard.vue';
import { criarI18n } from './apoio';

// #2996 — a linha de etiquetas do card: só as marcadas para a lista, até 2 à vista,
// e o "+N" mostra todas, com as cores.
vi.mock('dashboard/composables/useNomeDaEtiqueta', () => ({
  useNomeDaEtiqueta: () => ({ nomeDe: titulo => titulo }),
}));

enableAutoUnmount(afterEach);

const etiqueta = (id, title, naLista = true) => ({
  id,
  title,
  color: `#00000${id}`,
  show_on_conversation_list: naLista,
});
const DA_CONTA = [
  etiqueta(1, 'cobrança'),
  etiqueta(2, 'vip'),
  etiqueta(3, 'auto'),
  etiqueta(4, 'interno', false),
];

const montar = (titulos, raiz = { onClick: vi.fn() }) =>
  mount(
    {
      components: { EtiquetasDoCard },
      props: ['titulos'],
      emits: ['click'],
      template:
        '<div @click="$emit(\'click\')"><EtiquetasDoCard :titulos="titulos" /></div>',
    },
    {
      props: { titulos, ...raiz },
      global: {
        plugins: [
          createStore({ getters: { 'labels/getLabels': () => DA_CONTA } }),
          criarI18n(),
        ],
      },
    }
  );

const nomes = wrapper =>
  wrapper.findAll('[data-etiqueta]').map(item => item.text());

describe('EtiquetasDoCard', () => {
  it('não mostra a linha quando nenhuma etiqueta da conversa está marcada para a lista', () => {
    expect(montar(['interno']).find('[data-etiquetas]').isVisible()).toBe(
      false
    );
    expect(montar([]).find('[data-etiquetas]').isVisible()).toBe(false);
  });

  it('mostra só as marcadas para a lista, com a cor de cada uma', () => {
    const wrapper = montar(['cobrança', 'interno']);

    expect(nomes(wrapper)).toEqual(['cobrança']);
    expect(wrapper.find('[data-etiqueta] span').attributes('style')).toContain(
      'background-color'
    );
    expect(wrapper.find('[data-mais-etiquetas]').exists()).toBe(false);
  });

  it('mostra até 2 e o "+N"; clicar no "+N" mostra todas sem abrir a conversa', async () => {
    const onClick = vi.fn();
    const wrapper = montar(['vip', 'cobrança', 'auto', 'interno'], { onClick });

    expect(nomes(wrapper)).toEqual(['auto', 'cobrança']);
    const mais = wrapper.find('[data-mais-etiquetas]');
    expect(mais.text()).toBe('+1');
    expect(mais.attributes('aria-label')).toBe('+1, ver todas as etiquetas');
    expect(mais.attributes('aria-expanded')).toBe('false');

    await mais.trigger('click');

    expect(nomes(wrapper)).toEqual(['auto', 'cobrança', 'vip']);
    const menos = wrapper.find('[data-mais-etiquetas]');
    expect(menos.text()).toBe('menos');
    expect(menos.attributes('aria-expanded')).toBe('true');
    expect(onClick).not.toHaveBeenCalled();

    await menos.trigger('click');
    expect(nomes(wrapper)).toEqual(['auto', 'cobrança']);
  });
});
