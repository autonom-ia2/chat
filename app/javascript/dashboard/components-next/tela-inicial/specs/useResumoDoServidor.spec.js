import { defineComponent } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { emitter } from 'shared/helpers/mitt';
import { buscarResumo } from '../resumoDoServidor';
import {
  EVENTO_CONVERSAS_MUDARAM,
  useResumoDoServidor,
} from '../useResumoDoServidor';

vi.mock('../resumoDoServidor', async original => ({
  ...(await original()),
  buscarResumo: vi.fn(),
}));

const resumo = esperamVoce => ({
  esperamVoce,
  semResponsavel: 0,
  foraDoPrazo: null,
  proxima: null,
  equipe: null,
});

const montar = () => {
  let api;
  const wrapper = mount(
    defineComponent({
      setup() {
        api = useResumoDoServidor();
        return () => null;
      },
    })
  );
  return { wrapper, api: () => api };
};

describe('useResumoDoServidor', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.useFakeTimers();
  });
  afterEach(() => vi.useRealTimers());

  it('carrega ao abrir', async () => {
    buscarResumo.mockResolvedValue(resumo(2));
    const { wrapper, api } = montar();
    await flushPromises();
    expect(buscarResumo).toHaveBeenCalledTimes(1);
    expect(api().estado.value).toBe('pronto');
    expect(api().resumo.value.esperamVoce).toBe(2);
    wrapper.unmount();
  });

  it('uma rajada de avisos vira uma consulta só', async () => {
    buscarResumo.mockResolvedValue(resumo(1));
    const { wrapper, api } = montar();
    await flushPromises();
    buscarResumo.mockResolvedValue(resumo(5));
    emitter.emit(EVENTO_CONVERSAS_MUDARAM);
    emitter.emit(EVENTO_CONVERSAS_MUDARAM);
    emitter.emit(EVENTO_CONVERSAS_MUDARAM);
    await vi.advanceTimersByTimeAsync(2000);
    await flushPromises();
    expect(buscarResumo).toHaveBeenCalledTimes(2);
    expect(api().resumo.value.esperamVoce).toBe(5);
    wrapper.unmount();
  });

  it('falha sem resumo bom: estado de erro', async () => {
    buscarResumo.mockRejectedValue(new Error('rede'));
    const { wrapper, api } = montar();
    await flushPromises();
    expect(api().estado.value).toBe('erro');
    wrapper.unmount();
  });

  it('falha depois de carregar: fica o último resumo', async () => {
    buscarResumo.mockResolvedValue(resumo(3));
    const { wrapper, api } = montar();
    await flushPromises();
    buscarResumo.mockRejectedValue(new Error('rede'));
    emitter.emit(EVENTO_CONVERSAS_MUDARAM);
    await vi.advanceTimersByTimeAsync(2000);
    await flushPromises();
    expect(api().estado.value).toBe('pronto');
    expect(api().resumo.value.esperamVoce).toBe(3);
    wrapper.unmount();
  });

  it('para de ouvir quando a tela sai', async () => {
    buscarResumo.mockResolvedValue(resumo(0));
    const { wrapper } = montar();
    await flushPromises();
    wrapper.unmount();
    emitter.emit(EVENTO_CONVERSAS_MUDARAM);
    await vi.advanceTimersByTimeAsync(2000);
    expect(buscarResumo).toHaveBeenCalledTimes(1);
  });
});
