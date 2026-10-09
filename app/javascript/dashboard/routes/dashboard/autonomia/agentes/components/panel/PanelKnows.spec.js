import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import AutonomiaSourcesAPI from 'dashboard/api/autonomia/sources';
import PanelKnows from './PanelKnows.vue';

vi.mock('dashboard/api/autonomia/sources', () => ({
  default: {
    get: vi.fn(),
    create: vi.fn(),
    delete: vi.fn(),
    resync: vi.fn(),
  },
}));

withFullI18n('pt_BR');
enableAutoUnmount(afterEach);

const source = (id, kind = 'knowledge', state = 'ready') => ({
  id,
  kind,
  source_type: 'pdf',
  reference: `manual-${id}.pdf`,
  status: 'ready',
  screen_state: state,
  uses: true,
  review: { status: 'accepted' },
});

const DialogStub = {
  template: `
    <form data-testid="dialog" @submit.prevent="$emit('confirm')">
      <slot />
      <slot name="footer" />
    </form>
  `,
  props: ['title', 'description', 'confirmButtonLabel', 'isLoading'],
  emits: ['confirm', 'close'],
  methods: { open() {}, close() {} },
};

const AddStub = {
  template: '<div data-testid="add-dialog" />',
  props: ['agentId', 'disabled'],
  methods: { open() {} },
};

const FaqStub = {
  template: '<div data-testid="faq-review" />',
  emits: ['updated'],
};

const mountPanel = (props = {}) =>
  mount(PanelKnows, {
    props: {
      agentId: 42,
      agent: { id: 42, name: 'Lia', config: { knowledge_confidence: 0.8 } },
      canManage: true,
      ...props,
    },
    global: {
      stubs: {
        AddMaterialDialog: AddStub,
        Dialog: DialogStub,
        FaqReviewList: FaqStub,
        Spinner: true,
      },
    },
  });

describe('PanelKnows', () => {
  beforeEach(() => {
    AutonomiaSourcesAPI.get.mockReset();
    AutonomiaSourcesAPI.delete.mockReset();
    AutonomiaSourcesAPI.resync.mockReset();
    AutonomiaSourcesAPI.get.mockResolvedValue({
      data: { payload: [source(1), source(2, 'media')] },
    });
    AutonomiaSourcesAPI.delete.mockResolvedValue({ data: {} });
    AutonomiaSourcesAPI.resync.mockResolvedValue({ data: {} });
  });

  it('carrega somente knowledge, mostra contador real e exclui mídia', async () => {
    const wrapper = mountPanel();
    await flushPromises();

    expect(AutonomiaSourcesAPI.get).toHaveBeenCalledWith(
      42,
      expect.objectContaining({ signal: expect.any(AbortSignal) })
    );
    expect(wrapper.get('[data-testid="knowledge-count"]').text()).toContain(
      '1'
    );
    expect(wrapper.findAll('[data-testid="knowledge-material"]')).toHaveLength(
      1
    );
    expect(wrapper.find('[data-testid="faq-review"]').exists()).toBe(true);
  });

  it('separa a confiança da base do contador de materiais', async () => {
    AutonomiaSourcesAPI.get.mockResolvedValueOnce({
      data: { payload: [] },
    });
    const wrapper = mountPanel({
      agent: {
        id: 42,
        name: 'Lia',
        config: { knowledge_confidence: 0.71 },
      },
    });
    await flushPromises();

    expect(wrapper.get('[data-testid="knowledge-confidence"]').text()).toBe(
      '71% · boa'
    );
    expect(wrapper.get('[data-testid="knowledge-count"]').text()).toContain(
      '0 de 30 materiais'
    );
    expect(wrapper.get('[role="progressbar"]').attributes('aria-label')).toBe(
      'Confiança da base de conhecimento'
    );
  });

  it('desabilita adicionar no limite de 30 sem esconder os materiais', async () => {
    AutonomiaSourcesAPI.get.mockResolvedValueOnce({
      data: {
        payload: Array.from({ length: 30 }, (_, index) => source(index + 1)),
      },
    });
    const wrapper = mountPanel();
    await flushPromises();

    expect(wrapper.get('[data-testid="knowledge-limit"]').exists()).toBe(true);
    expect(
      wrapper.get('[data-action="add-material"]').attributes('disabled')
    ).toBe('');
    expect(wrapper.findAll('[data-testid="knowledge-material"]')).toHaveLength(
      30
    );
  });

  it('mostra erro explícito e permite tentar novamente', async () => {
    AutonomiaSourcesAPI.get
      .mockRejectedValueOnce(new Error('network'))
      .mockResolvedValueOnce({ data: { payload: [] } });
    const wrapper = mountPanel();
    await flushPromises();

    expect(wrapper.find('[data-state="error"]').exists()).toBe(true);
    await wrapper.get('[data-action="retry-sources"]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-state="empty"]').exists()).toBe(true);
  });

  it('confirma remoção antes do DELETE', async () => {
    const wrapper = mountPanel();
    await flushPromises();
    await wrapper.get('[data-action="remove"]').trigger('click');
    expect(AutonomiaSourcesAPI.delete).not.toHaveBeenCalled();

    await wrapper.get('[data-testid="dialog"]').trigger('submit');
    await flushPromises();
    expect(AutonomiaSourcesAPI.delete).toHaveBeenCalledWith(42, 1);
  });

  it('propaga a mudança de FAQ para reler a projeção do agente', async () => {
    const wrapper = mountPanel();
    await flushPromises();
    wrapper.findComponent(FaqStub).vm.$emit('updated', false);
    expect(wrapper.emitted('updated')).toHaveLength(1);
  });

  it('não monta ações FAQ nem botão de escrita sem canManage', async () => {
    const wrapper = mountPanel({ canManage: false });
    await flushPromises();

    expect(wrapper.find('[data-testid="faq-review"]').exists()).toBe(false);
    expect(wrapper.find('[data-action="add-material"]').exists()).toBe(false);
  });
});
