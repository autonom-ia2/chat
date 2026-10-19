import { defineComponent, h, nextTick } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import NomesDeEtiquetasAPI from 'dashboard/api/nomesDeEtiquetas';
import { useNomeDaEtiqueta } from '../useNomeDaEtiqueta';

vi.mock('dashboard/api/nomesDeEtiquetas', () => ({
  default: { listar: vi.fn(), gravar: vi.fn() },
}));

const ETIQUETAS = [
  { id: 1, title: 'aguardando_retorno' },
  { id: 2, title: 'vip' },
];

// Um componente só, que guarda o que o composable devolveu.
let ultimaApi;
const Sonda = defineComponent({
  setup() {
    ultimaApi = useNomeDaEtiqueta();
    return () => h('span');
  },
});

// Cada teste usa uma conta própria: o cache é por conta e vive no módulo.
const montar = ({ accountId, ligada = true, etiquetas = ETIQUETAS }) => {
  const store = createStore({
    getters: {
      getCurrentAccountId: () => accountId,
      'accounts/isFeatureEnabledonAccount': () => () => ligada,
      'labels/getLabels': () => etiquetas,
    },
  });
  mount(Sonda, { global: { plugins: [store] } });
  return ultimaApi;
};

describe('useNomeDaEtiqueta', () => {
  beforeEach(() => {
    NomesDeEtiquetasAPI.listar.mockResolvedValue({
      data: { payload: [{ label_id: 2, nome: 'Cliente VIP' }] },
    });
  });

  afterEach(() => vi.clearAllMocks());

  it('keeps the title and does not call the API with the flag off', async () => {
    const { nomeDe, buscar, ligada } = montar({ accountId: 10, ligada: false });
    await flushPromises();

    expect(ligada.value).toBe(false);
    expect(nomeDe('aguardando_retorno')).toBe('aguardando_retorno');
    expect(buscar(ETIQUETAS, 'retorno').map(({ id }) => id)).toEqual([1]);
    expect(NomesDeEtiquetasAPI.listar).not.toHaveBeenCalled();
  });

  it('shows the saved name, else the name derived from the title', async () => {
    const { nomeDe } = montar({ accountId: 11 });
    await flushPromises();

    expect(nomeDe('vip')).toBe('Cliente VIP');
    expect(nomeDe('aguardando_retorno')).toBe('Aguardando retorno');
    // Texto que não é etiqueta da conta (SLA, Linear) fica como está.
    expect(nomeDe('sla_breach')).toBe('sla_breach');
  });

  it('loads the names once per account for all the chips', async () => {
    montar({ accountId: 12 });
    montar({ accountId: 12 });
    await flushPromises();

    expect(NomesDeEtiquetasAPI.listar).toHaveBeenCalledTimes(1);
  });

  it('finds a label by the technical title and by the shown name', async () => {
    const { buscar } = montar({ accountId: 13 });
    await flushPromises();

    const ids = termo => buscar(ETIQUETAS, termo).map(({ id }) => id);
    expect(ids('aguardando_retorno')).toEqual([1]);
    expect(ids('aguardando retorno')).toEqual([1]);
    expect(ids('cliente vip')).toEqual([2]);
  });

  it('recognizes typed text as an existing label by either name', async () => {
    const { etiquetaDoTexto } = montar({ accountId: 14 });
    await flushPromises();

    expect(etiquetaDoTexto(ETIQUETAS, 'Aguardando retorno')?.id).toBe(1);
    expect(etiquetaDoTexto(ETIQUETAS, 'aguardando_retorno')?.id).toBe(1);
    expect(etiquetaDoTexto(ETIQUETAS, ' cliente vip ')?.id).toBe(2);
    expect(etiquetaDoTexto(ETIQUETAS, 'novo cliente')).toBeNull();
    expect(etiquetaDoTexto(ETIQUETAS, '  ')).toBeNull();
  });

  it('shows a name saved here right away, without reloading', async () => {
    NomesDeEtiquetasAPI.gravar.mockResolvedValue({
      data: { payload: { label_id: 1, nome: 'Esperando o cliente' } },
    });
    const { nomeDe, guardarNome } = montar({ accountId: 15 });
    await flushPromises();

    await guardarNome(1, 'Esperando o cliente');
    await nextTick();

    expect(NomesDeEtiquetasAPI.gravar).toHaveBeenCalledWith(
      1,
      'Esperando o cliente'
    );
    expect(nomeDe('aguardando_retorno')).toBe('Esperando o cliente');
    expect(nomeDe('vip')).toBe('Cliente VIP');
  });

  it('falls back to the derived name when loading fails', async () => {
    NomesDeEtiquetasAPI.listar.mockRejectedValue(new Error('falhou'));
    vi.spyOn(console, 'error').mockImplementation(() => {});
    const { nomeDe } = montar({ accountId: 16 });
    await flushPromises();

    expect(nomeDe('vip')).toBe('Vip');
  });

  it('keeps the loaded names when a forced reload fails', async () => {
    const { nomeDe, recarregar } = montar({ accountId: 17 });
    await flushPromises();
    NomesDeEtiquetasAPI.listar.mockRejectedValue(new Error('falhou'));
    vi.spyOn(console, 'error').mockImplementation(() => {});

    await recarregar();

    expect(nomeDe('vip')).toBe('Cliente VIP');
  });

  it('does not let an older list overwrite a name saved meanwhile', async () => {
    let responder;
    NomesDeEtiquetasAPI.listar.mockReturnValue(
      new Promise(resolve => {
        responder = resolve;
      })
    );
    NomesDeEtiquetasAPI.gravar.mockResolvedValue({
      data: { payload: { label_id: 2, nome: 'VIP de verdade' } },
    });
    const { nomeDe, guardarNome } = montar({ accountId: 18 });

    await guardarNome(2, 'VIP de verdade');
    responder({
      data: {
        payload: [
          { label_id: 1, nome: 'Esperando' },
          { label_id: 2, nome: 'Cliente VIP' },
        ],
      },
    });
    await flushPromises();

    expect(nomeDe('vip')).toBe('VIP de verdade');
    expect(nomeDe('aguardando_retorno')).toBe('Esperando');
  });

  it('counts the flag as off when mounted without the dashboard store', () => {
    mount(Sonda);

    expect(ultimaApi.ligada.value).toBe(false);
    expect(ultimaApi.nomeDe('vip')).toBe('vip');
  });
});
