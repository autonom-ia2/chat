import { flushPromises, mount } from '@vue/test-utils';
import { defineComponent, h, reactive, ref } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import CrmPipelineDrawer from './CrmPipelineDrawer.vue';

vi.mock('vuex', () => ({
  useStore: () => ({ getters: { 'globalConfig/get': { crmAiEnabled: true } } }),
}));
vi.mock('../composables/useCrmPermissions', () => ({
  useCrmPermissions: () => ({ canManageAi: ref(true) }),
}));
vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: () => {},
}));
vi.mock('dashboard/api/crmKanban', () => ({
  default: { improveStageCriteria: vi.fn() },
}));

describe('pipeline description AI actions', () => {
  let wrapper;

  beforeEach(async () => {
    vi.clearAllMocks();
    wrapper = mount(CrmPipelineDrawer, {
      props: {
        show: true,
        mode: 'edit',
        pipeline: { id: 1, name: 'Funil' },
        stages: [
          { id: 10, name: 'Novo', color: '#2563eb' },
          { id: 11, name: 'Proposta', color: '#0891b2' },
        ],
      },
      global: {
        stubs: {
          CrmStageAutomationsPanel: true,
          CrmAiSettingsPanel: defineComponent({
            setup(_, { expose }) {
              expose({
                form: reactive({
                  stageCriteria: { 10: '  ', 11: 'Oferta apresentada.' },
                }),
                isLoading: false,
                loadFailed: false,
              });
              return () => h('div');
            },
          }),
        },
      },
    });
    wrapper.vm.openStage(wrapper.vm.form.stages[0]);
    await wrapper.vm.$nextTick();
  });

  afterEach(() => wrapper.unmount());

  it('offers creation for a blank description and improvement after entering text', async () => {
    const action = wrapper
      .findAllComponents(Button)
      .find(button => button.props('icon') === 'i-lucide-sparkles');
    expect(action.props('label')).toBe('CRM_KANBAN.PIPELINE_EDITOR.CREATE');
    expect(action.element.disabled).toBe(false);

    await wrapper.find('#stage-ai-criteria').setValue('Primeiro contato.');

    expect(action.props('label')).toBe('CRM_KANBAN.PIPELINE_EDITOR.IMPROVE');
    await wrapper.find('#stage-ai-criteria').setValue('');
    expect(action.props('label')).toBe('CRM_KANBAN.PIPELINE_EDITOR.CREATE');
  });

  it('previews creation and applies only the selected description after acceptance', async () => {
    CrmKanbanAPI.improveStageCriteria.mockResolvedValue({
      data: {
        description: 'Primeiro contato antes da qualificação.',
        note: '',
      },
    });
    const action = wrapper
      .findAllComponents(Button)
      .find(button => button.props('icon') === 'i-lucide-sparkles');
    await action.trigger('click');
    await flushPromises();

    expect(CrmKanbanAPI.improveStageCriteria).toHaveBeenCalledWith(1, {
      stages: [
        { name: 'Novo', description: '  ' },
        { name: 'Proposta', description: 'Oferta apresentada.' },
      ],
      stage_index: 0,
    });
    expect(wrapper.vm.selectedCriteria).toBe('  ');
    expect(wrapper.vm.aiPanel.form.stageCriteria[11]).toBe(
      'Oferta apresentada.'
    );
    expect(wrapper.text()).toContain('CRM_KANBAN.PIPELINE_EDITOR.DISMISS');
    const accept = wrapper
      .findAllComponents(Button)
      .find(
        button => button.props('label') === 'CRM_KANBAN.PIPELINE_EDITOR.APPLY'
      );
    await accept.trigger('click');

    expect(wrapper.vm.selectedCriteria).toBe(
      'Primeiro contato antes da qualificação.'
    );
    expect(wrapper.vm.aiPanel.form.stageCriteria[11]).toBe(
      'Oferta apresentada.'
    );
    expect(wrapper.vm.form.stages.map(stage => stage.name)).toEqual([
      'Novo',
      'Proposta',
    ]);
    expect(action.props('label')).toBe('CRM_KANBAN.PIPELINE_EDITOR.IMPROVE');
  });

  it('explains why AI needs every stage name before allowing creation', async () => {
    wrapper.vm.form.stages[1].name = '';
    await wrapper.vm.$nextTick();
    const action = wrapper
      .findAllComponents(Button)
      .find(button => button.props('icon') === 'i-lucide-sparkles');
    expect(action.element.disabled).toBe(true);
    expect(wrapper.text()).toContain(
      'CRM_KANBAN.PIPELINE_EDITOR.NAMES_REQUIRED'
    );

    wrapper.vm.form.stages[1].name = 'Proposta';
    await wrapper.vm.$nextTick();

    expect(action.element.disabled).toBe(false);
    expect(wrapper.text()).toContain('CRM_KANBAN.PIPELINE_EDITOR.CREATE_HELP');
  });

  it('shows only the save-first notice before the pipeline exists', async () => {
    await wrapper.setProps({ mode: 'create' });
    wrapper.vm.openStage(wrapper.vm.form.stages[0]);
    await wrapper.vm.$nextTick();

    expect(wrapper.text()).toContain('CRM_KANBAN.PIPELINE_EDITOR.SAVE_FIRST');
    expect(wrapper.text()).not.toContain(
      'CRM_KANBAN.PIPELINE_EDITOR.CREATE_HELP'
    );
    expect(
      wrapper
        .findAllComponents(Button)
        .some(button => button.props('icon') === 'i-lucide-sparkles')
    ).toBe(false);
  });
});
