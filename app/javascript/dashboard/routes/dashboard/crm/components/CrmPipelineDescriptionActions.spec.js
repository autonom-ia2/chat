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
  default: {
    improveStageCriteria: vi.fn(),
    improveDraftStageCriteria: vi.fn(),
    getStageCriteriaDefaults: vi.fn(),
  },
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
          // #2414 F1.3: o resumo das ações da etapa lê a chave da função no store, que este spec não monta.
          FunilEtapaAcoes: true,
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

  const sparkles = () =>
    wrapper
      .findAllComponents(Button)
      .find(button => button.props('icon') === 'i-lucide-sparkles');

  it('offers creation for a blank description and improvement after entering text', async () => {
    // Vazia: o cartão âmbar com um único botão, sem campo aberto.
    expect(wrapper.find('[data-etapa-falta]').exists()).toBe(true);
    expect(sparkles().props('label')).toBe('CRM_FUNIL.ETAPAS.CRIAR_IA');
    expect(sparkles().element.disabled).toBe(false);

    await wrapper.find('#stage-ai-criteria').setValue('Primeiro contato.');

    expect(sparkles().props('label')).toBe('CRM_FUNIL.ETAPA.MELHORAR');
    await wrapper.find('#stage-ai-criteria').setValue('');
    expect(sparkles().props('label')).toBe('CRM_FUNIL.ETAPAS.CRIAR_IA');
  });

  it('previews creation and applies only the selected description after acceptance', async () => {
    CrmKanbanAPI.improveStageCriteria.mockResolvedValue({
      data: {
        description: 'Primeiro contato antes da qualificação.',
        note: '',
      },
    });
    await sparkles().trigger('click');
    await flushPromises();

    expect(CrmKanbanAPI.improveStageCriteria).toHaveBeenCalledWith(1, {
      stages: [
        { name: 'Novo', description: '  ' },
        { name: 'Proposta', description: 'Oferta apresentada.' },
      ],
      stage_index: 0,
    });
    expect(wrapper.vm.selectedCriteria).toBe('  ');
    // Um estado por vez: com a sugestão na tela, o botão da IA sai.
    expect(sparkles()).toBeUndefined();
    expect(wrapper.text()).toContain('CRM_FUNIL.ETAPA.DESCARTAR');
    await wrapper.get('[data-usar-sugestao]').trigger('click');

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
    expect(sparkles().props('label')).toBe('CRM_FUNIL.ETAPA.MELHORAR');
  });

  it('shows the current and the suggested sentence side by side', async () => {
    wrapper.vm.selectedCriteria = 'Cliente pediu o preço';
    CrmKanbanAPI.improveStageCriteria.mockResolvedValue({
      data: {
        description: 'Cliente pediu o preço pela primeira vez.',
        note: '',
      },
    });
    await wrapper.vm.$nextTick();
    await sparkles().trigger('click');
    await flushPromises();

    // #1384: sem marcar palavra por palavra; "Como está" e "Como fica" bastam.
    expect(wrapper.find('mark').exists()).toBe(false);
    const sugestao = wrapper.get('[data-funil-sugestao]').text();
    expect(sugestao).toContain('Cliente pediu o preço');
    expect(sugestao).toContain('Cliente pediu o preço pela primeira vez.');
    expect(wrapper.text()).toContain('CRM_FUNIL.ETAPA.MANTER');
  });

  it('explains why AI needs every stage name before allowing creation', async () => {
    wrapper.vm.form.stages[1].name = '';
    await wrapper.vm.$nextTick();
    expect(sparkles().element.disabled).toBe(true);
    expect(wrapper.text()).toContain('CRM_FUNIL.ETAPA.NOMES_FALTAM');

    wrapper.vm.form.stages[1].name = 'Proposta';
    await wrapper.vm.$nextTick();

    expect(sparkles().element.disabled).toBe(false);
    expect(wrapper.text()).not.toContain('CRM_FUNIL.ETAPA.NOMES_FALTAM');
  });

  // #1384: o funil novo já vem com a descrição padrão e a IA funciona antes de salvar.
  describe('before the pipeline exists', () => {
    // #1498: o funil novo só ganha etapas depois de escolher o tipo.
    const mountCreate = async () => {
      const created = mount(CrmPipelineDrawer, {
        props: { show: true, mode: 'create' },
        global: { stubs: { CrmStageAutomationsPanel: true } },
      });
      await created.get('[data-tipo="VENDER"]').trigger('click');
      return created;
    };

    it('fills each default stage with the server default description', async () => {
      CrmKanbanAPI.getStageCriteriaDefaults.mockImplementation(async names => ({
        data: {
          payload: names.map((name, index) => ({
            name,
            criteria: index === 1 ? '' : `Padrão de ${name}`,
          })),
        },
      }));
      const created = await mountCreate();
      await flushPromises();

      const names = created.vm.form.stages.map(stage => stage.name);
      // #1548: o modelo e a posição de cada etapa nele vão junto dos nomes.
      expect(CrmKanbanAPI.getStageCriteriaDefaults).toHaveBeenCalledWith(
        names,
        {
          atender: false,
          template: 'VENDAS',
          positions: [1, 2, 3, 4, 5],
        }
      );
      expect(created.vm.criteriaFor(created.vm.form.stages[0])).toBe(
        `Padrão de ${names[0]}`
      );
      expect(created.vm.criteriaFor(created.vm.form.stages[1])).toBe('');
      created.unmount();
    });

    it('keeps what the person typed when the defaults arrive late', async () => {
      let answer;
      CrmKanbanAPI.getStageCriteriaDefaults.mockReturnValue(
        new Promise(resolve => {
          answer = resolve;
        })
      );
      const created = await mountCreate();
      created.vm.form.stages[0].aiCriteria = 'Meu texto';
      answer({
        data: {
          payload: created.vm.form.stages.map(stage => ({
            name: stage.name,
            criteria: 'Padrão',
          })),
        },
      });
      await flushPromises();

      expect(created.vm.form.stages[0].aiCriteria).toBe('Meu texto');
      expect(created.vm.form.stages[2].aiCriteria).toBe('Padrão');
      created.unmount();
    });

    it('shows the AI action and drafts through the account route', async () => {
      CrmKanbanAPI.getStageCriteriaDefaults.mockResolvedValue({
        data: { payload: [] },
      });
      CrmKanbanAPI.improveDraftStageCriteria.mockResolvedValue({
        data: { description: 'Primeiro contato.', note: '' },
      });
      const created = await mountCreate();
      await flushPromises();
      created.vm.form.name = ' Funil novo ';
      created.vm.openStage(created.vm.form.stages[0]);
      await created.vm.$nextTick();

      const action = created
        .findAllComponents(Button)
        .find(button => button.props('icon') === 'i-lucide-sparkles');
      expect(action.props('label')).toBe('CRM_FUNIL.ETAPAS.CRIAR_IA');
      await action.trigger('click');
      await flushPromises();

      expect(CrmKanbanAPI.improveStageCriteria).not.toHaveBeenCalled();
      expect(CrmKanbanAPI.improveDraftStageCriteria).toHaveBeenCalledWith(
        expect.objectContaining({ pipeline_name: 'Funil novo', stage_index: 0 })
      );
      expect(created.text()).toContain('Primeiro contato.');
      expect(created.text()).not.toContain('SAVE_FIRST');
      created.unmount();
    });
  });
});
