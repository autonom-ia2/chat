import { nextTick } from 'vue';
import { mount } from '@vue/test-utils';
import GavetaFerramentas from '../../components/pagina/GavetaFerramentas.vue';

vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return {
    useStore: () => ({ dispatch: vi.fn(), getters: {} }),
    useMapGetter: () => computed(() => false),
  };
});

// O PanelTools real busca ferramentas na API; aqui um dublê com o mesmo formato do formulário
// (um <form> dentro de um `div fixed`), aberto ou fechado por fora.
const estado = vi.hoisted(() => ({ formAberto: null }));
vi.mock('../../../components/panel/PanelTools.vue', async () => {
  const { defineComponent, h, ref } = await import('vue');
  estado.formAberto = ref(false);
  return {
    default: defineComponent({
      props: { agentId: { type: Number, required: true } },
      setup(props) {
        return () =>
          h('section', { 'data-agente': props.agentId }, [
            estado.formAberto.value
              ? h('div', { class: 'fixed inset-0' }, [h('form', [h('input')])])
              : null,
          ]);
      },
    }),
  };
});

const montar = () =>
  mount(GavetaFerramentas, {
    props: { agente: { id: 7 } },
    attachTo: document.body,
  });

const apertarEsc = () =>
  document.dispatchEvent(
    new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })
  );

describe('GavetaFerramentas', () => {
  afterEach(() => {
    estado.formAberto.value = false;
    document.body.innerHTML = '';
  });

  it('closes on Escape when no tool form is open', async () => {
    const wrapper = montar();
    await nextTick();
    apertarEsc();
    expect(document.querySelector('[data-agente="7"]')).not.toBeNull();
    expect(wrapper.emitted('fechar')).toHaveLength(1);
    wrapper.unmount();
  });

  it('does not close on Escape or backdrop click while the tool form is open', async () => {
    estado.formAberto.value = true;
    const wrapper = montar();
    await nextTick();
    apertarEsc();
    document.querySelector('[data-fundo]').click();
    expect(wrapper.emitted('fechar')).toBeUndefined();
    wrapper.unmount();
  });
});
