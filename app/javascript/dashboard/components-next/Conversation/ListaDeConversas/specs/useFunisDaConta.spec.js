import { defineComponent, h, ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { ESPERA_DEPOIS_DA_FALHA_MS, useFunisDaConta } from '../useFunisDaConta';

// #2202 — a leitura dos funis é uma por conta; se falhar, espera 30 s antes de tentar de novo.
const api = vi.hoisted(() => ({ getPipelines: vi.fn() }));
vi.mock('dashboard/api/crmKanban', () => ({ default: api }));

const montar = contaId => {
  let estado;
  mount(
    defineComponent({
      setup() {
        estado = useFunisDaConta(ref(contaId), ref(true));
        return () => h('span');
      },
    })
  );
  return () => estado.value;
};

describe('useFunisDaConta (#2202)', () => {
  beforeEach(() => {
    api.getPipelines.mockReset();
    vi.useFakeTimers();
  });
  afterEach(() => vi.useRealTimers());

  it('falhou: conta como "com funil" e os cards montados logo depois não pedem de novo', async () => {
    api.getPipelines.mockRejectedValueOnce(new Error('rede'));
    const primeiro = montar(901);
    await flushPromises();
    expect(primeiro()).toEqual({ semFunil: false });

    montar(901);
    montar(901);
    vi.advanceTimersByTime(ESPERA_DEPOIS_DA_FALHA_MS - 1);
    montar(901);
    await flushPromises();
    expect(api.getPipelines).toHaveBeenCalledTimes(1);
  });

  it('passados 30 s da falha, o próximo card lê de novo', async () => {
    api.getPipelines.mockRejectedValueOnce(new Error('rede'));
    montar(902);
    await flushPromises();

    vi.advanceTimersByTime(ESPERA_DEPOIS_DA_FALHA_MS);
    api.getPipelines.mockResolvedValueOnce({ data: { payload: [] } });
    const depois = montar(902);
    await flushPromises();
    expect(api.getPipelines).toHaveBeenCalledTimes(2);
    expect(depois()).toEqual({ semFunil: true });
  });

  it('a espera é por conta: a falha de uma não segura a outra', async () => {
    api.getPipelines.mockRejectedValueOnce(new Error('rede'));
    montar(903);
    await flushPromises();
    api.getPipelines.mockResolvedValueOnce({ data: { payload: [{ id: 1 }] } });
    montar(904);
    await flushPromises();
    expect(api.getPipelines).toHaveBeenCalledTimes(2);
  });

  it('deu certo: uma leitura só por conta, dividida pelos cards', async () => {
    api.getPipelines.mockResolvedValue({ data: { payload: [{ id: 1 }] } });
    montar(905);
    montar(905);
    await flushPromises();
    expect(api.getPipelines).toHaveBeenCalledTimes(1);
  });
});
