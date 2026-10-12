import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import en from 'dashboard/i18n/locale/en/modelosWhatsapp.json';
import ModelosListaPage from '../pages/ModelosListaPage.vue';

// Caixa com message_templates = {} em produção (12/10/2026): a API devolve
// payload [] e a tela mostra "sem modelos ainda", com o botão de criar.
const api = vi.hoisted(() => ({
  listarNumeros: vi.fn(),
  listarModelos: vi.fn(),
  obterFranquia: vi.fn(),
  custoPorEnvio: vi.fn(),
}));
vi.mock('../api/modelosWhatsapp', () => ({ default: api }));
vi.mock('vue-router', () => ({
  useRouter: () => ({ push: vi.fn(), resolve: () => ({ href: '#' }) }),
}));

const montar = () =>
  mount(ModelosListaPage, {
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'en', messages: { en } }),
        createStore({
          getters: {
            getCurrentAccountId: () => 1,
            getCurrentUser: () => ({ id: 1, accounts: [] }),
            getCurrentCustomRoleId: () => null,
          },
        }),
      ],
    },
  });

beforeEach(() => {
  Object.values(api).forEach(fn => fn.mockReset());
  api.obterFranquia.mockResolvedValue(null);
  api.custoPorEnvio.mockResolvedValue(null);
});

describe('ModelosListaPage sem modelos', () => {
  it('shows "no templates yet" with the create button when the box has none', async () => {
    api.listarNumeros.mockResolvedValue([
      {
        id: 7,
        nome: 'Atendimento',
        conta: { id: 7, nome: 'Hub2you' },
        situacao: 'conectada',
      },
    ]);
    api.listarModelos.mockResolvedValue([]);

    const wrapper = montar();
    await flushPromises();

    expect(wrapper.find('[data-vazio]').text()).toContain(
      en.MODELOS_WHATSAPP.VAZIO.TITULO
    );
    expect(wrapper.find('[data-criar]').exists()).toBe(true);
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
  });
});
