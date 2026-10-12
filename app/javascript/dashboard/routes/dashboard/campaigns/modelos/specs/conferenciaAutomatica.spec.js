import { defineComponent, h, ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import { createMemoryHistory, createRouter } from 'vue-router';
import en from 'dashboard/i18n/locale/en/modelosWhatsapp.json';
import {
  INTERVALO_MS,
  MAXIMO_DE_RODADAS,
  mudancasDeSituacao,
  useConferenciaAutomatica,
} from '../helpers/useConferenciaAutomatica';
import ModelosListaPage from '../pages/ModelosListaPage.vue';

// #1394: enquanto houver modelo em análise, a tela confere sozinha a cada 60 s,
// só com a aba visível, e para sem nada em análise ou depois de 30 rodadas.
const api = vi.hoisted(() => ({
  listarNumeros: vi.fn(),
  listarModelos: vi.fn(),
  obterFranquia: vi.fn(),
  custoPorEnvio: vi.fn(),
}));
vi.mock('../api/modelosWhatsapp', () => ({ default: api }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const vazio = () => ({ template: '<div />' });

let visibilidade = 'visible';
const mudarAba = async estado => {
  visibilidade = estado;
  document.dispatchEvent(new Event('visibilitychange'));
  await flushPromises();
};

const passar = async ms => {
  await vi.advanceTimersByTimeAsync(ms);
  await flushPromises();
};

const hospedar = (emAnalise, conferir) =>
  mount(
    defineComponent({
      setup() {
        useConferenciaAutomatica(emAnalise, conferir);
        return () => h('div');
      },
    })
  );

beforeEach(() => {
  vi.useFakeTimers();
  visibilidade = 'visible';
  vi.spyOn(document, 'visibilityState', 'get').mockImplementation(
    () => visibilidade
  );
});

afterEach(() => {
  vi.useRealTimers();
  vi.restoreAllMocks();
});

describe('useConferenciaAutomatica', () => {
  it('liga com modelo em análise: uma conferência a cada 60 s', async () => {
    const conferir = vi.fn().mockResolvedValue();
    hospedar(ref(true), conferir);

    await passar(INTERVALO_MS - 1);
    expect(conferir).not.toHaveBeenCalled();
    await passar(1);
    expect(conferir).toHaveBeenCalledTimes(1);
    await passar(INTERVALO_MS);
    expect(conferir).toHaveBeenCalledTimes(2);
  });

  it('não liga sem modelo em análise e para quando nada mais está em análise', async () => {
    const conferir = vi.fn().mockResolvedValue();
    const emAnalise = ref(false);
    hospedar(emAnalise, conferir);
    await passar(5 * INTERVALO_MS);
    expect(conferir).not.toHaveBeenCalled();

    emAnalise.value = true;
    await passar(INTERVALO_MS);
    expect(conferir).toHaveBeenCalledTimes(1);
    emAnalise.value = false;
    await passar(5 * INTERVALO_MS);
    expect(conferir).toHaveBeenCalledTimes(1);
  });

  it('para quando a aba some e confere na hora quando ela volta', async () => {
    const conferir = vi.fn().mockResolvedValue();
    hospedar(ref(true), conferir);

    await mudarAba('hidden');
    await passar(10 * INTERVALO_MS);
    expect(conferir).not.toHaveBeenCalled();

    await mudarAba('visible');
    expect(conferir).toHaveBeenCalledTimes(1);
    await passar(INTERVALO_MS);
    expect(conferir).toHaveBeenCalledTimes(2);
  });

  it('para depois de 30 minutos de conferência (30 rodadas)', async () => {
    const conferir = vi.fn().mockResolvedValue();
    hospedar(ref(true), conferir);

    await passar(45 * INTERVALO_MS);
    expect(MAXIMO_DE_RODADAS).toBe(30);
    expect(conferir).toHaveBeenCalledTimes(30);
  });

  it('a Meta falhou numa rodada: tenta de novo na seguinte', async () => {
    const conferir = vi
      .fn()
      .mockRejectedValueOnce(new Error('meta_unreachable'))
      .mockResolvedValue();
    hospedar(ref(true), conferir);

    await passar(2 * INTERVALO_MS);
    expect(conferir).toHaveBeenCalledTimes(2);
  });

  it('para ao sair da página', async () => {
    const conferir = vi.fn().mockResolvedValue();
    const wrapper = hospedar(ref(true), conferir);
    wrapper.unmount();

    await passar(5 * INTERVALO_MS);
    await mudarAba('visible');
    expect(conferir).not.toHaveBeenCalled();
  });

  it('avisa só o que saiu de "em análise" para pronto ou recusado', () => {
    const antes = [
      { id: '1', nome: 'Boleto', situacao: 'em_analise' },
      { id: '2', nome: 'Oferta', situacao: 'em_analise' },
      { id: '3', nome: 'Boas-vindas', situacao: 'em_analise' },
      { id: '4', nome: 'Lembrete', situacao: 'pronto' },
    ];
    const depois = [
      { id: '1', nome: 'Boleto', situacao: 'pronto' },
      { id: '2', nome: 'Oferta', situacao: 'recusado' },
      { id: '3', nome: 'Boas-vindas', situacao: 'em_analise' },
      { id: '4', nome: 'Lembrete', situacao: 'pronto' },
    ];
    expect(mudancasDeSituacao(antes, depois)).toEqual([
      { nome: 'Boleto', situacao: 'pronto' },
      { nome: 'Oferta', situacao: 'recusado' },
    ]);
  });
});

describe('Lista de modelos com modelo em análise', () => {
  const modelo = (id, nome, situacao) => ({
    id,
    nome,
    nomeNoWhatsapp: nome,
    situacao,
    tipo: 'aviso',
    numeros: [7],
    conta: 7,
    conteudo: { formato: 'padrao', texto: [{ t: 'texto', v: nome }] },
    edicoes: {},
  });

  it('atualiza no lugar, mantém a busca e avisa quem ficou pronto', async () => {
    api.listarNumeros.mockResolvedValue([
      { id: 7, nome: 'Atendimento', conta: { id: 7, nome: 'Hub2you' } },
    ]);
    api.obterFranquia.mockResolvedValue(null);
    api.custoPorEnvio.mockResolvedValue(null);
    api.listarModelos
      .mockResolvedValueOnce([
        modelo('1', 'Boleto', 'em_analise'),
        modelo('2', 'Oferta', 'pronto'),
      ])
      .mockResolvedValue([
        modelo('1', 'Boleto', 'pronto'),
        modelo('2', 'Oferta', 'pronto'),
      ]);
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [
        { path: '/', name: 'modelos_whatsapp_lista', component: vazio() },
        {
          path: '/:pathMatch(.*)*',
          name: 'settings_inbox_new',
          component: vazio(),
        },
      ],
    });
    const wrapper = mount(ModelosListaPage, {
      global: {
        plugins: [
          createI18n({ legacy: false, locale: 'en', messages: { en } }),
          createStore({
            getters: {
              getCurrentAccountId: () => 1,
              getCurrentUser: () => ({
                id: 1,
                accounts: [{ id: 1, role: 'administrator' }],
              }),
            },
          }),
          router,
        ],
        stubs: { 'router-link': { template: '<a><slot /></a>' } },
      },
    });
    await flushPromises();
    await wrapper.find('[data-busca]').setValue('bol');

    await passar(INTERVALO_MS);

    expect(api.listarModelos).toHaveBeenCalledTimes(2);
    expect(api.listarModelos).toHaveBeenLastCalledWith({ atualizar: true });
    expect(wrapper.find('[aria-busy="true"]').exists()).toBe(false);
    expect(wrapper.find('[data-busca]').element.value).toBe('bol');
    const aviso = wrapper.find('[data-aviso-de-situacao]');
    expect(aviso.attributes('aria-live')).toBe('polite');
    expect(aviso.text()).toBe('“Boleto” is ready to use.');

    // Nada mais em análise: para.
    await passar(5 * INTERVALO_MS);
    expect(api.listarModelos).toHaveBeenCalledTimes(2);
  });
});
