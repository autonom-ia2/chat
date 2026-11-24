import { defineComponent, nextTick, ref } from 'vue';
import { mount } from '@vue/test-utils';
import {
  cantoOcupadoPelaTela,
  useOcuparCantoDaBolinha,
} from '../cantoDaBolinha';

// #3192 — a tela avisa enquanto o canto da bolinha do Guia é dela.
const montar = ocupado =>
  mount(
    defineComponent({
      setup() {
        useOcuparCantoDaBolinha(ocupado);
        return () => null;
      },
    })
  );

describe('useOcuparCantoDaBolinha (#3192)', () => {
  afterEach(() => {
    cantoOcupadoPelaTela.value = false;
  });

  it('segue a tela enquanto ela está montada', async () => {
    const ocupado = ref(false);
    const wrapper = montar(ocupado);
    expect(cantoOcupadoPelaTela.value).toBe(false);

    ocupado.value = true;
    await nextTick();
    expect(cantoOcupadoPelaTela.value).toBe(true);
    wrapper.unmount();
  });

  it('sair da tela devolve o canto à bolinha', () => {
    const wrapper = montar(ref(true));
    expect(cantoOcupadoPelaTela.value).toBe(true);

    wrapper.unmount();
    expect(cantoOcupadoPelaTela.value).toBe(false);
  });
});
