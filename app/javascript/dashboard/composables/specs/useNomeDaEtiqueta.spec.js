import { defineComponent, h, nextTick } from 'vue';
import { mount, flushPromises, enableAutoUnmount } from '@vue/test-utils';
import { createStore } from 'vuex';
import NomesDeEtiquetasAPI from 'dashboard/api/nomesDeEtiquetas';
import EtiquetasDoCelularAPI from 'dashboard/api/etiquetasDoCelular';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { useNomeDaEtiqueta } from '../useNomeDaEtiqueta';

vi.mock('dashboard/api/nomesDeEtiquetas', () => ({
  default: { listar: vi.fn(), gravar: vi.fn() },
}));
vi.mock('dashboard/api/etiquetasDoCelular', () => ({
  default: { listar: vi.fn() },
}));

// Estado único no módulo, que segue a store do último componente montado.
enableAutoUnmount(afterEach);

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
const montar = ({
  accountId,
  ligada = true,
  celular = false,
  etiquetas = ETIQUETAS,
}) => {
  const flags = {
    [FEATURE_FLAGS.ETIQUETAS_DO_WHATSAPP]: ligada,
    [FEATURE_FLAGS.ETIQUETAS_DO_CELULAR]: celular,
  };
  const store = createStore({
    getters: {
      getCurrentAccountId: () => accountId,
      'accounts/isFeatureEnabledonAccount': () => (_conta, flag) =>
        Boolean(flags[flag]),
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
    EtiquetasDoCelularAPI.listar.mockResolvedValue({
      data: {
        payload: [
          {
            label_id: 1,
            inbox_id: 7,
            caixa: 'Atendimento',
            nome_no_celular: 'Esperando 🔥',
            color_index: 3,
            criada_pelo_celular: true,
          },
          {
            label_id: 1,
            inbox_id: 8,
            caixa: 'Vendas',
            nome_no_celular: 'Esperando',
            color_index: 3,
            criada_pelo_celular: false,
          },
        ],
      },
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

  it('does not cache a failed load of the names: the next load tries again', async () => {
    NomesDeEtiquetasAPI.listar.mockRejectedValueOnce(new Error('falhou'));
    vi.spyOn(console, 'error').mockImplementation(() => {});
    montar({ accountId: 19 });
    await flushPromises();
    expect(ultimaApi.nomeDe('vip')).toBe('Vip');

    // Troca de conta e volta: carga comum (sem forçar), que só vai à API
    // porque a falha não deixou a conta 19 no cache.
    montar({ accountId: 20 });
    await flushPromises();
    const { nomeDe } = montar({ accountId: 19 });
    await flushPromises();

    expect(NomesDeEtiquetasAPI.listar).toHaveBeenCalledTimes(3);
    expect(nomeDe('vip')).toBe('Cliente VIP');
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

  describe('etiquetas do celular (F1b)', () => {
    it('does not load nor show phone links without the etiquetas_do_celular flag', async () => {
      const { vinculosDe, nomeDe, celularLigado } = montar({ accountId: 30 });
      await flushPromises();

      expect(celularLigado.value).toBe(false);
      expect(vinculosDe('aguardando_retorno')).toEqual([]);
      expect(nomeDe('aguardando_retorno')).toBe('Aguardando retorno');
      expect(EtiquetasDoCelularAPI.listar).not.toHaveBeenCalled();
    });

    it('lists one link per inbox and shows the phone name when there is no saved name', async () => {
      const { vinculosDe, nomeDe } = montar({ accountId: 31, celular: true });
      await flushPromises();

      expect(vinculosDe('aguardando_retorno')).toEqual([
        {
          caixa: 'Atendimento',
          inboxId: 7,
          nomeNoCelular: 'Esperando 🔥',
          criadaPeloCelular: true,
        },
        {
          caixa: 'Vendas',
          inboxId: 8,
          nomeNoCelular: 'Esperando',
          criadaPeloCelular: false,
        },
      ]);
      expect(vinculosDe('vip')).toEqual([]);
      expect(nomeDe('aguardando_retorno')).toBe('Esperando 🔥');
      // O nome guardado aqui continua na frente do nome do celular.
      expect(nomeDe('vip')).toBe('Cliente VIP');
    });

    it('keeps the technical title when only the phone flag is on', async () => {
      const { nomeDe, vinculosDe } = montar({
        accountId: 32,
        ligada: false,
        celular: true,
      });
      await flushPromises();

      expect(vinculosDe('aguardando_retorno')).toHaveLength(2);
      expect(nomeDe('aguardando_retorno')).toBe('aguardando_retorno');
      expect(NomesDeEtiquetasAPI.listar).not.toHaveBeenCalled();
    });

    it('loads the links once per account for many chips (one shared loader)', async () => {
      montar({ accountId: 33, celular: true });
      montar({ accountId: 33, celular: true });
      montar({ accountId: 33, celular: true });
      await flushPromises();

      expect(EtiquetasDoCelularAPI.listar).toHaveBeenCalledTimes(1);
    });

    it('does not cache a failed load: the next load tries again', async () => {
      EtiquetasDoCelularAPI.listar.mockRejectedValueOnce(new Error('falhou'));
      vi.spyOn(console, 'error').mockImplementation(() => {});
      const { vinculosDe, recarregar } = montar({
        accountId: 34,
        celular: true,
      });
      await flushPromises();
      expect(vinculosDe('aguardando_retorno')).toEqual([]);

      await recarregar();

      expect(EtiquetasDoCelularAPI.listar).toHaveBeenCalledTimes(2);
      expect(vinculosDe('aguardando_retorno')).toHaveLength(2);
    });
  });

  it('counts the flag as off when mounted without the dashboard store', async () => {
    // Módulo novo: o estado é único por módulo e os outros testes já deram store.
    vi.resetModules();
    const { useNomeDaEtiqueta: semStore } = await import(
      '../useNomeDaEtiqueta'
    );
    let api;
    mount(
      defineComponent({
        setup() {
          api = semStore();
          return () => h('span');
        },
      })
    );

    expect(api.ligada.value).toBe(false);
    expect(api.celularLigado.value).toBe(false);
    expect(api.nomeDe('vip')).toBe('vip');
  });
});
