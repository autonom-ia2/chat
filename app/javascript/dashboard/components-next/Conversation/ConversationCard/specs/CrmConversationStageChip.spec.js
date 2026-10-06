import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import CrmConversationStageChip from '../CrmConversationStageChip.vue';

const push = vi.fn();
const etapa = ref(null);

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 16 } }),
  useRouter: () => ({ push }),
}));
vi.mock(
  'dashboard/routes/dashboard/crm/composables/useCrmConversationStages',
  () => ({ useCrmConversationStage: () => etapa })
);

const montar = () =>
  mount(CrmConversationStageChip, {
    props: { conversationId: 100 },
    global: { mocks: { $t: (key, valores) => `${key} ${valores?.etapa}` } },
  });

describe('CrmConversationStageChip', () => {
  afterEach(() => {
    push.mockClear();
    etapa.value = null;
  });

  // Conta 16 (06/10/2026): clicar em "Email Comercial · Novo" na conversa leva
  // direto ao card no CRM, e não abre a conversa junto.
  it('abre o card no CRM sem deixar o clique chegar ao cartão da conversa', async () => {
    etapa.value = {
      card_id: 1840,
      pipeline_name: 'Email Comercial',
      stage_name: 'Novo',
      multiple_pipelines: true,
    };
    const cliqueNoCartao = vi.fn();
    const wrapper = mount(
      {
        components: { CrmConversationStageChip },
        template:
          '<div @click="cliqueNoCartao"><CrmConversationStageChip :conversation-id="100" /></div>',
        setup: () => ({ cliqueNoCartao }),
      },
      {
        global: { mocks: { $t: (key, valores) => `${key} ${valores?.etapa}` } },
      }
    );

    const selo = wrapper.find('button[data-crm-stage-chip]');
    expect(selo.text()).toContain('Email Comercial · Novo');
    expect(selo.attributes('aria-label')).toContain('Email Comercial · Novo');
    await selo.trigger('click');

    expect(push).toHaveBeenCalledWith({
      name: 'crm_kanban_index',
      params: { accountId: 16 },
      query: { card_id: 1840 },
    });
    expect(cliqueNoCartao).not.toHaveBeenCalled();
  });

  it('sem o id do card, o selo continua só informando a etapa', () => {
    etapa.value = { pipeline_name: 'Email Comercial', stage_name: 'Novo' };
    const wrapper = montar();

    expect(wrapper.find('button').exists()).toBe(false);
    expect(wrapper.find('[data-crm-stage-chip]').text()).toBe('Novo');
  });
});
