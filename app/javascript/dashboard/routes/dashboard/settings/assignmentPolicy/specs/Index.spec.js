import { mount } from '@vue/test-utils';
import Index from '../Index.vue';

const permissions = vi.hoisted(() => ({ keys: [] }));
vi.mock('vue-router', () => ({
  useRouter: () => ({ push: vi.fn() }),
  useRoute: () => ({ params: { accountId: '16' } }),
}));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return { useMapGetter: () => computed(() => () => true) };
});
vi.mock('dashboard/composables/useCanManage', async () => {
  const { computed } = await import('vue');
  return {
    useCanManage: key => computed(() => permissions.keys.includes(key)),
  };
});

// #1797: com assignment_manage a função chega ao hub de Atribuição; o cartão da passagem do CRM só aparece para quem
// abre a passagem (administrador ou crm_manage_ai), senão o clique cairia numa rota barrada.
const mountIndex = () =>
  mount(Index, {
    global: {
      stubs: {
        SettingsLayout: {
          template: '<div><slot name="header" /><slot name="body" /></div>',
        },
        BaseSettingsHeader: true,
        AssignmentCard: {
          props: ['title'],
          template: '<article data-card>{{ title }}</article>',
        },
      },
    },
  });

const titles = wrapper =>
  wrapper.findAll('[data-card]').map(card => card.text());

describe('Atribuição · hub', () => {
  beforeEach(() => {
    window.globalConfig = {
      CRM_KANBAN_ENABLED: 'true',
      CRM_AI_ENABLED: 'true',
    };
  });

  it('hides the CRM handoff card from a role that only manages assignment', () => {
    permissions.keys = [];
    const wrapper = mountIndex();

    expect(titles(wrapper)).not.toContain(
      'ASSIGNMENT_POLICY.INDEX.CRM_HANDOFF.TITLE'
    );
    expect(titles(wrapper)).toContain(
      'ASSIGNMENT_POLICY.INDEX.ASSIGNMENT_POLICY.TITLE'
    );
  });

  it('shows the CRM handoff card to who can open it', () => {
    permissions.keys = ['crm_manage_ai'];

    expect(titles(mountIndex())).toContain(
      'ASSIGNMENT_POLICY.INDEX.CRM_HANDOFF.TITLE'
    );
  });
});
