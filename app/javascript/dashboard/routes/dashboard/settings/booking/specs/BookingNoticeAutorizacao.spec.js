import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import BookingNoticeAutorizacao from '../components/BookingNoticeAutorizacao.vue';

// #1612: no lugar do antigo "Criar os modelos na Meta", o passo de avisos diz
// que, com a autorização ligada, o sistema pede os modelos à Meta. O resumo da
// autorização (com o caminho para ver ou mudar) só para quem a vê em Modelos:
// administrador ou whatsapp_templates_manage, com a jornada de Modelos ligada.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values) =>
      values === undefined ? key : `${key} ${JSON.stringify(values)}`,
  }),
}));
vi.mock('shared/composables/useBranding', () => ({
  useBranding: () => ({ installationName: ref('Chat2You') }),
}));
const sessao = vi.hoisted(() => ({ papel: 'administrator', jornada: true }));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  const getters = {
    getCurrentUser: () => ({
      accounts: [{ id: 1, permissions: [sessao.papel] }],
    }),
    getCurrentAccountId: () => 1,
    'accounts/isFeatureEnabledonAccount': () => () => sessao.jornada,
  };
  return { useMapGetter: name => computed(getters[name]) };
});
vi.mock(
  'dashboard/routes/dashboard/campaigns/modelos/components/AutorizacaoResumo.vue',
  async () => {
    const { h } = await import('vue');
    return {
      default: { render: () => h('a', { 'data-autorizacao-resumo': '' }) },
    };
  }
);

const montar = () => mount(BookingNoticeAutorizacao);

describe('BookingNoticeAutorizacao', () => {
  beforeEach(() => {
    sessao.papel = 'administrator';
    sessao.jornada = true;
  });

  it('diz o que vale agora, com o nome da marca', () => {
    expect(montar().text()).toBe(
      'BOOKING.NOTICES.AUTO.SYSTEM_TEMPLATES_HINT {"marca":"Chat2You"}'
    );
  });

  it('o administrador vê o resumo da autorização', () => {
    expect(montar().find('[data-autorizacao-resumo]').exists()).toBe(true);
  });

  it('função com whatsapp_templates_manage também vê', () => {
    sessao.papel = 'whatsapp_templates_manage';
    expect(montar().find('[data-autorizacao-resumo]').exists()).toBe(true);
  });

  it('quem só gerencia agendamento lê o texto, sem o resumo', () => {
    sessao.papel = 'agendamento_manage';
    const wrapper = montar();
    expect(wrapper.find('[data-autorizacao-resumo]').exists()).toBe(false);
    expect(wrapper.text()).toContain('SYSTEM_TEMPLATES_HINT');
  });

  it('sem a jornada de Modelos na conta, sem o resumo (a rota não abriria)', () => {
    sessao.jornada = false;
    expect(montar().find('[data-autorizacao-resumo]').exists()).toBe(false);
  });
});
