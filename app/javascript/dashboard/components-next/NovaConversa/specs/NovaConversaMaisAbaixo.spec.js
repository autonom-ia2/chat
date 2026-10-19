import { ref } from 'vue';
import { mount } from '@vue/test-utils';
import NovaConversaMaisAbaixo from '../NovaConversaMaisAbaixo.vue';

// #1869 — a gaveta avisa que tem mais embaixo, com o mesmo indicador do menu lateral.
const estado = vi.hoisted(() => ({ rolar: vi.fn() }));
const abaixo = ref(false);
vi.mock('dashboard/components-next/sidebar/fork/useSetasDeRolagem', () => ({
  useSetasDeRolagem: () => ({
    abaixo,
    respirando: ref({ abaixo: false }),
    rolarParaBaixo: estado.rolar,
  }),
}));

const montar = () =>
  mount(NovaConversaMaisAbaixo, {
    props: { controla: 'corpo-da-gaveta' },
    global: { mocks: { $t: chave => chave } },
  });

describe('NovaConversaMaisAbaixo', () => {
  beforeEach(() => {
    abaixo.value = false;
    estado.rolar.mockClear();
  });

  it('com tudo à vista, não mostra nada', () => {
    const wrapper = montar();
    expect(wrapper.find('[data-mais-abaixo]').exists()).toBe(false);
    expect(wrapper.find('[data-esmaecido-da-gaveta]').exists()).toBe(false);
  });

  it('com mais embaixo, esmaece a borda e a seta desce a tela', async () => {
    abaixo.value = true;
    const wrapper = montar();
    const seta = wrapper.get('[data-mais-abaixo]');
    expect(wrapper.find('[data-esmaecido-da-gaveta]').exists()).toBe(true);
    expect(seta.attributes('aria-controls')).toBe('corpo-da-gaveta');
    await seta.trigger('click');
    expect(estado.rolar).toHaveBeenCalledOnce();
  });

  // #1872 — a seta some no fim da lista: se o clique a focasse, o foco sumiria junto.
  it('o clique na seta não tira o foco de onde está', () => {
    abaixo.value = true;
    const seta = montar().get('[data-mais-abaixo]').element;
    const pressionar = new MouseEvent('mousedown', {
      bubbles: true,
      cancelable: true,
    });
    seta.dispatchEvent(pressionar);
    expect(pressionar.defaultPrevented).toBe(true);
  });
});
