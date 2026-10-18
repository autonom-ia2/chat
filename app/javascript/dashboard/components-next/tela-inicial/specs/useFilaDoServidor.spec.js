import { defineComponent } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { emitter } from 'shared/helpers/mitt';
import { buscarFila } from '../filaDoServidor';
import {
  EVENTO_CONVERSAS_MUDARAM,
  useFilaDoServidor,
} from '../useFilaDoServidor';

vi.mock('../filaDoServidor', () => ({ buscarFila: vi.fn() }));

const montar = () => {
  let api;
  const wrapper = mount(
    defineComponent({
      setup() {
        api = useFilaDoServidor();
        return () => null;
      },
    })
  );
  return { wrapper, api: () => api };
};

describe('useFilaDoServidor', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.useFakeTimers();
  });
  afterEach(() => vi.useRealTimers());

  it('carrega ao abrir', async () => {
    buscarFila.mockResolvedValue({
      esperamVoce: 2,
      esperamAlguem: 1,
      proxima: null,
    });
    const { wrapper, api } = montar();
    await flushPromises();
    expect(buscarFila).toHaveBeenCalledTimes(1);
    expect(api().estado.value).toBe('pronto');
    expect(api().fila.value.esperamVoce).toBe(2);
    wrapper.unmount();
  });

  it('uma rajada de avisos vira uma consulta só', async () => {
    buscarFila.mockResolvedValue({
      esperamVoce: 1,
      esperamAlguem: 0,
      proxima: null,
    });
    const { wrapper, api } = montar();
    await flushPromises();
    buscarFila.mockResolvedValue({
      esperamVoce: 5,
      esperamAlguem: 0,
      proxima: null,
    });
    emitter.emit(EVENTO_CONVERSAS_MUDARAM);
    emitter.emit(EVENTO_CONVERSAS_MUDARAM);
    emitter.emit(EVENTO_CONVERSAS_MUDARAM);
    await vi.advanceTimersByTimeAsync(2000);
    await flushPromises();
    expect(buscarFila).toHaveBeenCalledTimes(2);
    expect(api().fila.value.esperamVoce).toBe(5);
    wrapper.unmount();
  });

  it('falha sem número bom: estado de erro', async () => {
    buscarFila.mockRejectedValue(new Error('rede'));
    const { wrapper, api } = montar();
    await flushPromises();
    expect(api().estado.value).toBe('erro');
    wrapper.unmount();
  });

  it('falha depois de carregar: fica o último número', async () => {
    buscarFila.mockResolvedValue({
      esperamVoce: 3,
      esperamAlguem: 0,
      proxima: null,
    });
    const { wrapper, api } = montar();
    await flushPromises();
    buscarFila.mockRejectedValue(new Error('rede'));
    emitter.emit(EVENTO_CONVERSAS_MUDARAM);
    await vi.advanceTimersByTimeAsync(2000);
    await flushPromises();
    expect(api().estado.value).toBe('pronto');
    expect(api().fila.value.esperamVoce).toBe(3);
    wrapper.unmount();
  });

  it('para de ouvir quando a tela sai', async () => {
    buscarFila.mockResolvedValue({
      esperamVoce: 0,
      esperamAlguem: 0,
      proxima: null,
    });
    const { wrapper } = montar();
    await flushPromises();
    wrapper.unmount();
    emitter.emit(EVENTO_CONVERSAS_MUDARAM);
    await vi.advanceTimersByTimeAsync(2000);
    expect(buscarFila).toHaveBeenCalledTimes(1);
  });
});
