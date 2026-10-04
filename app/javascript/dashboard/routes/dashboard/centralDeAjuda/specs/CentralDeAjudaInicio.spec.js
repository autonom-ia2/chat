import { mount, flushPromises } from '@vue/test-utils';
import CentralDeAjudaInicio from '../pages/CentralDeAjudaInicio.vue';

const pedirAoGuia = vi.fn();
const get = vi.fn();

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (chave, valor) => `${chave}${valor ?? ''}` }),
}));
vi.mock('vuex', () => ({
  useStore: () => ({ getters: { getCurrentAccountId: 1 } }),
}));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return {
    useMapGetter: () =>
      computed(() => () => ({ autonomia_guide_available: true })),
  };
});
vi.mock('dashboard/composables/useGuiaPedido', () => ({
  useGuiaPedido: () => ({ pedirAoGuia }),
}));
vi.mock('dashboard/api/centralDeAjuda', () => ({
  default: { get: (...args) => get(...args) },
}));

const montar = () =>
  mount(CentralDeAjudaInicio, {
    global: {
      stubs: {
        BuscaDaCentral: true,
        CentralContinue: true,
        Spinner: true,
        RouterLink: { props: ['to'], template: '<a><slot /></a>' },
        Button: {
          props: ['label'],
          emits: ['click'],
          template: '<button @click="$emit(\'click\')">{{ label }}</button>',
        },
      },
    },
  });

describe('CentralDeAjudaInicio', () => {
  beforeEach(() => {
    pedirAoGuia.mockClear();
    get.mockReset();
  });

  it('mostra atalhos, sintomas e assuntos só dos artigos que vieram para a conta', async () => {
    get.mockResolvedValue({
      data: {
        preparando: false,
        capitulos: [
          {
            id: '07',
            titulo: 'Caixas de entrada',
            artigos: [{ id: '07.01', ref: '07-01', titulo: 'WhatsApp' }],
          },
        ],
      },
    });

    const tela = montar();
    await flushPromises();
    const texto = tela.text();

    expect(texto).toContain(
      'HELP_CENTER.CENTRAL_DE_AJUDA.MAIS_PROCURADOS.WHATSAPP'
    );
    expect(texto).not.toContain(
      'HELP_CENTER.CENTRAL_DE_AJUDA.MAIS_PROCURADOS.FUNIL'
    );
    expect(texto).not.toContain('HELP_CENTER.CENTRAL_DE_AJUDA.SINTOMAS.TITULO');
    expect(texto).toContain(
      'HELP_CENTER.CENTRAL_DE_AJUDA.POR_ASSUNTO.NOMES.CANAIS'
    );
    expect(texto).not.toContain('COMECE');
  });

  it('enquanto a Central é preparada, o botão abre o Guia sem pergunta', async () => {
    get.mockResolvedValue({ data: { preparando: true, capitulos: [] } });

    const tela = montar();
    await flushPromises();
    await tela.find('button').trigger('click');

    expect(pedirAoGuia).toHaveBeenCalledWith();
  });
});
