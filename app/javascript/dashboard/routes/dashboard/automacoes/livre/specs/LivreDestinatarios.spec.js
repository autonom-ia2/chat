import { mount } from '@vue/test-utils';
import LivreDestinatarios from '../components/LivreDestinatarios.vue';

// #2552 — a reserva da caixa é um Switch (nunca um <select>) que só aparece
// com o responsável ligado; desligar o responsável tira a reserva também.
const SwitchFalso = {
  name: 'Switch',
  props: { modelValue: Boolean },
  emits: ['update:modelValue'],
  template:
    '<button type="button" :aria-pressed="modelValue" @click="$emit(\'update:modelValue\', !modelValue)" />',
};

const montar = modelValue =>
  mount(LivreDestinatarios, {
    props: { rotulo: 'Quem', modelValue, opcoes: { time: [], pessoa: [] } },
    global: {
      stubs: { Switch: SwitchFalso, LivreMarcar: true },
      mocks: { $t: chave => chave },
    },
  });

describe('LivreDestinatarios', () => {
  it('sem o responsável, não oferece a reserva; nada de <select>', () => {
    const wrapper = montar({ times: [3] });

    expect(wrapper.find('[data-reserva-caixa]').exists()).toBe(false);
    expect(wrapper.find('select').exists()).toBe(false);
  });

  it('com o responsável, liga a reserva da caixa', async () => {
    const wrapper = montar({ responsavel: true });

    await wrapper.find('[data-reserva-caixa]').trigger('click');

    expect(wrapper.emitted('update:modelValue')[0][0]).toEqual({
      responsavel: true,
      se_nao_houver: 'caixa',
    });
  });

  it('desligar o responsável tira a reserva e guarda o resto', async () => {
    const wrapper = montar({
      responsavel: true,
      se_nao_houver: 'caixa',
      pessoas: [7],
    });

    await wrapper.find('[data-responsavel]').trigger('click');

    expect(wrapper.emitted('update:modelValue')[0][0]).toEqual({
      pessoas: [7],
    });
  });
});
