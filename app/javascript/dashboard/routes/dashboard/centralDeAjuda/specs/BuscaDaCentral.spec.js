import { mount, flushPromises } from '@vue/test-utils';
import BuscaDaCentral from '../components/BuscaDaCentral.vue';

const pedirAoGuia = vi.fn();
const buscar = vi.fn();

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: chave => chave }) }));
vi.mock('vue-router', () => ({ useRouter: () => ({ push: vi.fn() }) }));
vi.mock('dashboard/composables/useGuiaPedido', () => ({
  useGuiaPedido: () => ({ pedirAoGuia }),
}));
vi.mock('dashboard/api/centralDeAjuda', () => ({
  default: { buscar: (...args) => buscar(...args) },
}));

const montar = props =>
  mount(BuscaDaCentral, {
    props,
    global: {
      stubs: {
        RouterLink: { props: ['to'], template: '<a><slot /></a>' },
        Spinner: true,
        Button: {
          props: ['label'],
          emits: ['click'],
          template: '<button @click="$emit(\'click\')">{{ label }}</button>',
        },
      },
    },
  });

const botaoDoGuia = tela =>
  tela
    .findAll('button')
    .find(botao =>
      botao.text().includes('HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.PERGUNTAR_GUIA')
    );

describe('BuscaDaCentral', () => {
  beforeEach(() => {
    pedirAoGuia.mockClear();
    buscar.mockReset();
    buscar.mockResolvedValue({ data: { resultados: [] } });
  });

  it('manda o texto digitado como pergunta ao Guia', async () => {
    const tela = montar({ guiaDisponivel: true });

    await tela.find('input').setValue('como conectar o whatsapp');
    await botaoDoGuia(tela).trigger('click');

    expect(pedirAoGuia).toHaveBeenCalledWith('como conectar o whatsapp');
  });

  it('com a busca vazia, o botão só abre o Guia', async () => {
    const tela = montar({ guiaDisponivel: true });

    await botaoDoGuia(tela).trigger('click');

    expect(pedirAoGuia).toHaveBeenCalledWith('');
  });

  it('esconde o botão quando o Guia não está disponível', async () => {
    const tela = montar({ guiaDisponivel: false });
    await flushPromises();

    expect(botaoDoGuia(tela)).toBeUndefined();
  });
});
