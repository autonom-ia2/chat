import { defineComponent, h } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { useContratados } from '../../composables/useContratados';

const api = vi.hoisted(() => ({ lista: vi.fn() }));
vi.mock('dashboard/api/autonomia/contratados', () => ({ default: api }));

// Monta um componente mínimo que usa o composable, como as telas fazem.
const montar = () => {
  let exposto;
  const Casca = defineComponent({
    setup() {
      exposto = useContratados();
      return () => h('div');
    },
  });
  mount(Casca);
  return () => exposto;
};

describe('useContratados (#3211)', () => {
  beforeEach(() => {
    api.lista.mockReset();
  });

  it('does not call the API when nobody mounts it', () => {
    useContratados();
    expect(api.lista).not.toHaveBeenCalled();
  });

  it('returns the models the server lists', async () => {
    api.lista.mockResolvedValue({
      data: { modelos: ['seguro_viagem_universal'] },
    });
    const exposto = montar();
    await flushPromises();

    expect(api.lista).toHaveBeenCalledTimes(1);
    expect(exposto().modelos.value).toEqual(['seguro_viagem_universal']);
  });

  it('returns an empty list when the account has none', async () => {
    api.lista.mockResolvedValue({ data: { modelos: [] } });
    const exposto = montar();
    await flushPromises();

    expect(exposto().modelos.value).toEqual([]);
  });

  it('returns an empty list when the answer has no list', async () => {
    api.lista.mockResolvedValue({ data: {} });
    const exposto = montar();
    await flushPromises();

    expect(exposto().modelos.value).toEqual([]);
  });

  it('returns an empty list and warns only the status when the read fails', async () => {
    const aviso = vi.spyOn(console, 'warn').mockImplementation(() => {});
    api.lista.mockRejectedValue({
      response: { status: 500 },
      message: 'detalhe que não vai para o console',
    });
    const exposto = montar();
    await flushPromises();

    expect(exposto().modelos.value).toEqual([]);
    expect(aviso).toHaveBeenCalledTimes(1);
    expect(aviso.mock.calls[0].join(' ')).toContain('500');
    expect(aviso.mock.calls[0].join(' ')).not.toContain('detalhe');
    aviso.mockRestore();
  });
});
