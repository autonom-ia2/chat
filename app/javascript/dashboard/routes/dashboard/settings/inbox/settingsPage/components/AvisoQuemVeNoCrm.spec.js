import { mount, RouterLinkStub } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import AvisoQuemVeNoCrm from './AvisoQuemVeNoCrm.vue';
import en from 'dashboard/i18n/locale/en/crm.json';
import pt_BR from 'dashboard/i18n/locale/pt_BR/crm.json';

// #1149 (R16) — em Caixa → Agentes, o aviso de que quem vê o quê no CRM fica em
// Caixas no CRM, com o link para a caixa lá.
const conta = vi.hoisted(() => ({ features: {} }));
vi.mock('vuex', () => ({
  useStore: () => ({
    getters: { getCurrentAccountId: 7, 'accounts/getAccount': () => conta },
  }),
}));

const montar = () =>
  mount(AvisoQuemVeNoCrm, {
    props: { inboxId: 5 },
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'pt_BR', messages: { en, pt_BR } }),
      ],
      stubs: { RouterLink: RouterLinkStub },
    },
  });

describe('AvisoQuemVeNoCrm', () => {
  afterEach(() => {
    delete window.globalConfig;
    conta.features = {};
  });

  it('com o CRM e a tela nova ligados, avisa e leva à caixa em Caixas no CRM', () => {
    window.globalConfig = { CRM_KANBAN_ENABLED: 'true' };
    conta.features = { crm_configurar_caixas: true };
    const wrapper = montar();

    expect(wrapper.text()).toContain(
      'Quem vê o quê no CRM fica em outro lugar'
    );
    expect(wrapper.text()).toContain('cada agente de IA');
    const link = wrapper.getComponent(RouterLinkStub);
    expect(link.props('to')).toEqual({
      name: 'crm_caixa',
      params: { accountId: 7, inboxId: 5 },
    });
    expect(link.text()).toBe('Configurar em Caixas no CRM');
  });

  it('sem a tela nova ou sem CRM, não mostra nada', () => {
    window.globalConfig = { CRM_KANBAN_ENABLED: 'true' };
    expect(montar().find('[data-aviso-quem-ve]').exists()).toBe(false);

    window.globalConfig = { CRM_KANBAN_ENABLED: 'false' };
    conta.features = { crm_configurar_caixas: true };
    expect(montar().find('[data-aviso-quem-ve]').exists()).toBe(false);
  });
});
