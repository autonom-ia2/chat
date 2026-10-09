import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import PanelToolsV2 from './PanelToolsV2.vue';

withFullI18n();
enableAutoUnmount(afterEach);

const { getTools, deleteTool, testTool } = vi.hoisted(() => ({
  getTools: vi.fn(() =>
    Promise.resolve({
      data: {
        payload: [
          {
            id: 7,
            name: 'Busca',
            slug: 'buscar',
            description: 'Consulta',
            enabled: true,
            http_method: 'GET',
            endpoint_url: 'https://example.test/search',
            param_schema: [],
          },
        ],
      },
    })
  ),
  deleteTool: vi.fn(() => Promise.resolve()),
  testTool: vi.fn(() =>
    Promise.resolve({ data: { status: 'ok', body: '{"ok":true}' } })
  ),
}));

vi.mock('dashboard/api/autonomia/agents', () => ({
  default: {
    getTools,
    createTool: vi.fn(),
    updateTool: vi.fn(),
    deleteTool,
    testTool,
  },
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({ value: { type: 'SuperAdmin' } }),
}));

const DialogStub = {
  emits: ['close'],
  data: () => ({ isOpen: false }),
  methods: {
    open() {
      this.isOpen = true;
    },
    close() {
      this.isOpen = false;
      this.$emit('close');
    },
  },
  template: `
    <div v-if="isOpen" data-test="dialog-stub">
      <slot />
      <slot name="footer" />
    </div>
  `,
};

const ToolDialogStub = {
  template: '<div data-test="tool-dialog-stub" />',
};

const panelGlobal = {
  mocks: { $t: key => key },
  stubs: { Dialog: DialogStub, ToolDialog: ToolDialogStub },
};

describe('PanelToolsV2', () => {
  it('lê o payload do envelope documentado pelo backend', async () => {
    const wrapper = mount(PanelToolsV2, {
      props: {
        agentId: 42,
        agent: { agent_type: 'standard' },
        canManage: true,
      },
      global: panelGlobal,
    });

    await flushPromises();

    expect(getTools).toHaveBeenCalledWith(42, expect.any(Object));
    expect(wrapper.text()).toContain('Busca');
  });

  it('testa a ferramenta com parâmetros e mostra o resultado', async () => {
    const wrapper = mount(PanelToolsV2, {
      props: {
        agentId: 42,
        agent: { agent_type: 'standard' },
        canManage: true,
      },
      global: panelGlobal,
    });

    await flushPromises();
    await wrapper.find('[data-test="tool-test-7"]').trigger('click');
    await flushPromises();

    expect(testTool).toHaveBeenCalledWith(42, 7, {});
    expect(wrapper.find('[data-test="tool-result"]').text()).toContain('ok');
  });

  it('pede os parâmetros antes de testar a ferramenta', async () => {
    getTools.mockResolvedValueOnce({
      data: {
        payload: [
          {
            id: 8,
            name: 'Estoque',
            slug: 'estoque',
            description: 'Consulta',
            enabled: true,
            http_method: 'GET',
            endpoint_url: 'https://example.test/stock',
            param_schema: [
              {
                name: 'q',
                type: 'string',
                description: 'Produto',
                required: true,
              },
            ],
          },
        ],
      },
    });
    testTool.mockClear();
    const wrapper = mount(PanelToolsV2, {
      props: {
        agentId: 42,
        agent: { agent_type: 'standard' },
        canManage: true,
      },
      global: panelGlobal,
    });

    await flushPromises();
    await wrapper.find('[data-test="tool-test-8"]').trigger('click');
    const field = wrapper.find('input[data-test="test-param-q"]');
    expect(field.exists()).toBe(true);
    await field.setValue('cadeira');
    await wrapper.find('[data-test="test-run"]').trigger('click');
    await flushPromises();

    expect(testTool).toHaveBeenCalledWith(42, 8, { q: 'cadeira' });
  });

  it('usa confirmação do aplicativo para excluir', async () => {
    const wrapper = mount(PanelToolsV2, {
      props: {
        agentId: 42,
        agent: { agent_type: 'standard' },
        canManage: true,
      },
      global: panelGlobal,
    });

    await flushPromises();
    await wrapper.find('[data-test="tool-delete-7"]').trigger('click');

    expect(wrapper.find('[data-test="delete-confirm"]').exists()).toBe(true);
    expect(deleteTool).not.toHaveBeenCalled();
    await wrapper.find('[data-test="delete-confirm"]').trigger('click');
    expect(deleteTool).toHaveBeenCalledWith(42, 7);
  });
});
