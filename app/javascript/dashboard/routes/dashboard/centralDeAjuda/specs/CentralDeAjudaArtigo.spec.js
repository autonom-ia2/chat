import { reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import CentralDeAjudaArtigo from '../pages/CentralDeAjudaArtigo.vue';

const artigo = vi.fn();
const marcarVisto = vi.fn();
const route = reactive({ params: { ref: '10-04' } });

vi.mock('vue-i18n', async () => {
  const { ref } = await import('vue');
  return { useI18n: () => ({ t: chave => chave, locale: ref('pt_BR') }) };
});
vi.mock('vue-router', () => ({ useRoute: () => route }));
vi.mock('vuex', () => ({
  useStore: () => ({ getters: { getCurrentAccountId: 1 } }),
}));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return {
    useMapGetter: () =>
      computed(() => () => ({ autonomia_guide_available: false })),
  };
});
vi.mock('dashboard/composables/useGuiaPedido', () => ({
  useGuiaPedido: () => ({ pedirAoGuia: vi.fn() }),
}));
vi.mock('dashboard/composables/useLevarAteLa', () => ({
  useLevarAteLa: () => ({ destino: () => null, levar: vi.fn() }),
}));
vi.mock('../composables/useTamanhoDaLetra', () => ({
  useTamanhoDaLetra: () => ({ classe: 'prose-lg' }),
}));
vi.mock('../composables/useArtigosVistos', () => ({
  useArtigosVistos: () => ({ marcarVisto }),
}));
vi.mock('dashboard/api/centralDeAjuda', () => ({
  default: { artigo: (...args) => artigo(...args) },
}));

const DADOS = {
  id: '10.04',
  ref: '10-04',
  titulo: 'Mover card',
  capitulo: 'CRM',
  conteudo: 'Texto',
};

const montar = () =>
  mount(CentralDeAjudaArtigo, {
    global: {
      stubs: {
        Spinner: true,
        ConteudoDoArtigo: true,
        VideoDoTrajeto: true,
        TamanhoDaLetra: true,
        Button: true,
        RouterLink: {
          props: ['to'],
          template: '<a :data-to="JSON.stringify(to)"><slot /></a>',
        },
      },
    },
  });

const erroComStatus = status =>
  Object.assign(new Error('x'), { response: { status } });

describe('CentralDeAjudaArtigo', () => {
  beforeEach(() => {
    artigo.mockReset();
    marcarVisto.mockClear();
    route.params.ref = '10-04';
  });

  it('marca o artigo como visto quando ele abre', async () => {
    artigo.mockResolvedValue({ data: DADOS });

    montar();
    await flushPromises();

    expect(artigo).toHaveBeenCalledWith('10-04');
    expect(marcarVisto).toHaveBeenCalledWith('10.04');
  });

  it('não marca artigo que não existe para a conta', async () => {
    artigo.mockRejectedValue(erroComStatus(404));

    const tela = montar();
    await flushPromises();

    expect(marcarVisto).not.toHaveBeenCalled();
    expect(tela.text()).toContain(
      'HELP_CENTER.CENTRAL_DE_AJUDA.ARTIGO.NAO_ENCONTRADO'
    );
  });

  it('não marca quando a leitura falha', async () => {
    artigo.mockRejectedValue(erroComStatus(500));

    const tela = montar();
    await flushPromises();

    expect(marcarVisto).not.toHaveBeenCalled();
    expect(tela.text()).toContain('HELP_CENTER.CENTRAL_DE_AJUDA.ERRO.TEXTO');
  });

  it('só marca o pedido mais novo quando a pessoa troca de artigo rápido', async () => {
    let soltarPrimeiro;
    artigo
      .mockReturnValueOnce(
        new Promise(resolve => {
          soltarPrimeiro = resolve;
        })
      )
      .mockResolvedValueOnce({ data: { ...DADOS, id: '10.05', ref: '10-05' } });

    montar();
    route.params.ref = '10-05';
    await flushPromises();
    soltarPrimeiro({ data: DADOS });
    await flushPromises();

    expect(marcarVisto).toHaveBeenCalledTimes(1);
    expect(marcarVisto).toHaveBeenCalledWith('10.05');
  });

  it('o nome do capítulo leva à página do assunto', async () => {
    artigo.mockResolvedValue({ data: DADOS });

    const tela = montar();
    await flushPromises();
    const link = tela.findAll('a').find(item => item.text() === 'CRM');

    expect(JSON.parse(link.attributes('data-to'))).toEqual({
      name: 'central_de_ajuda_assunto',
      params: { capitulo: '10' },
    });
  });
});
