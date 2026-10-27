import { defineComponent, h, ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { useFunisDaConta } from '../useFunisDaConta';

// #2202 — a leitura dos funis é uma por conta; se falhar, a próxima montagem tenta de novo.
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
  beforeEach(() => api.getPipelines.mockReset());

  it('falhou: conta como "com funil" e a próxima montagem lê de novo', async () => {
    api.getPipelines.mockRejectedValueOnce(new Error('rede'));
    const primeiro = montar(901);
    await flushPromises();
    expect(primeiro()).toEqual({ semFunil: false });

    api.getPipelines.mockResolvedValueOnce({ data: { payload: [] } });
    const segundo = montar(901);
    await flushPromises();
    expect(api.getPipelines).toHaveBeenCalledTimes(2);
    expect(segundo()).toEqual({ semFunil: true });
  });

  it('deu certo: uma leitura só por conta, dividida pelos cards', async () => {
    api.getPipelines.mockResolvedValue({ data: { payload: [{ id: 1 }] } });
    montar(902);
    montar(902);
    await flushPromises();
    expect(api.getPipelines).toHaveBeenCalledTimes(1);
  });
});
