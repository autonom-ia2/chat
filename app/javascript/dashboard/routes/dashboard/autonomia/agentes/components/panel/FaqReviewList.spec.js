import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import AutonomiaAgentsAPI from 'dashboard/api/autonomia/agents';
import AutonomiaFaqSuggestionsAPI from 'dashboard/api/autonomia/faqSuggestions';
import FaqReviewList from './FaqReviewList.vue';

vi.mock('dashboard/api/autonomia/agents', () => ({
  default: { update: vi.fn() },
}));
vi.mock('dashboard/api/autonomia/faqSuggestions', () => ({
  default: {
    list: vi.fn(),
    approve: vi.fn(),
    ignore: vi.fn(),
  },
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 1 } }),
}));

withFullI18n();
enableAutoUnmount(afterEach);

const suggestion = (id = 1) => ({
  id,
  question: `Como funciona ${id}?`,
  answer: `Resposta ${id}`,
  conversation_display_id: 100 + id,
});

const mountList = (props = {}) =>
  mount(FaqReviewList, {
    props: {
      agentId: 42,
      agent: { id: 42, config: { faq_suggestions: true } },
      canManage: true,
      ...props,
    },
    global: {
      stubs: {},
    },
  });

describe('FaqReviewList', () => {
  beforeEach(() => {
    AutonomiaAgentsAPI.update.mockReset();
    AutonomiaFaqSuggestionsAPI.list.mockReset();
    AutonomiaFaqSuggestionsAPI.approve.mockReset();
    AutonomiaFaqSuggestionsAPI.ignore.mockReset();
    AutonomiaAgentsAPI.update.mockResolvedValue({ data: {} });
    AutonomiaFaqSuggestionsAPI.approve.mockResolvedValue({ data: {} });
    AutonomiaFaqSuggestionsAPI.ignore.mockResolvedValue({ data: {} });
    AutonomiaFaqSuggestionsAPI.list.mockResolvedValue({
      data: {
        payload: [suggestion()],
        meta: { count: 26, pending_count: 26, current_page: 1, per_page: 25 },
      },
    });
  });

  it('carrega a primeira página e oferece carregamento explícito da próxima', async () => {
    const wrapper = mountList();
    await flushPromises();

    expect(AutonomiaFaqSuggestionsAPI.list).toHaveBeenCalledWith(
      42,
      expect.objectContaining({ status: 'pending', page: 1 })
    );
    expect(wrapper.findAll('[data-testid="faq-suggestion"]')).toHaveLength(1);
    expect(wrapper.get('[data-action="load-more"]').exists()).toBe(true);

    AutonomiaFaqSuggestionsAPI.list.mockResolvedValueOnce({
      data: {
        payload: [suggestion(2)],
        meta: { count: 26, pending_count: 26, current_page: 2, per_page: 25 },
      },
    });
    await wrapper.get('[data-action="load-more"]').trigger('click');
    await flushPromises();

    expect(AutonomiaFaqSuggestionsAPI.list).toHaveBeenLastCalledWith(
      42,
      expect.objectContaining({ page: 2 })
    );
    expect(wrapper.findAll('[data-testid="faq-suggestion"]')).toHaveLength(2);
  });

  it('envia o toggle com payload de agente e ações de aprovação', async () => {
    const wrapper = mountList();
    await flushPromises();

    await wrapper.get('[data-testid="faq-toggle"]').trigger('click');
    await flushPromises();
    expect(AutonomiaAgentsAPI.update).toHaveBeenCalledWith(42, {
      agent: { config: { faq_suggestions: false } },
    });

    await wrapper.get('[data-action="approve"]').trigger('click');
    await flushPromises();
    expect(AutonomiaFaqSuggestionsAPI.approve).toHaveBeenCalledWith(
      42,
      1,
      null
    );
  });

  it('não busca nem expõe FAQ para quem não pode gerenciar', async () => {
    const wrapper = mountList({ canManage: false });
    await flushPromises();

    expect(AutonomiaFaqSuggestionsAPI.list).not.toHaveBeenCalled();
    expect(wrapper.find('[data-state="forbidden"]').exists()).toBe(true);
  });

  it('aborta a leitura anterior ao trocar de agente', async () => {
    let resolve;
    let firstSignal;
    AutonomiaFaqSuggestionsAPI.list.mockImplementationOnce(
      (_id, { signal }) => {
        firstSignal = signal;
        return new Promise(res => {
          resolve = res;
        });
      }
    );
    const wrapper = mountList();
    await wrapper.setProps({ agentId: 43, agent: { id: 43, config: {} } });

    expect(firstSignal.aborted).toBe(true);
    resolve({ data: { payload: [], meta: {} } });
    await flushPromises();
  });
});
