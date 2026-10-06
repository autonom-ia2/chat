import { flushPromises, mount } from '@vue/test-utils';
import MetaAdsFunnelCard from '../components/MetaAdsFunnelCard.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/crmMetaAdsConnection', () => ({
  default: { suggestStages: vi.fn(), saveFunnel: vi.fn(), stopFunnel: vi.fn() },
}));

const funnel = (overrides = {}) => ({
  id: 3,
  name: 'Viagem',
  numbers: [{ inbox_id: 38, name: '5511933779463' }],
  enabled: false,
  missing: ['sending_off', 'stages'],
  stages: [
    { id: 10, name: 'Novo', funnel_stage_type: null, result: false },
    { id: 11, name: 'Proposta', funnel_stage_type: null, result: false },
    { id: 12, name: 'Ganho', funnel_stage_type: null, result: true },
  ],
  ...overrides,
});

const mountCard = props =>
  mount(MetaAdsFunnelCard, {
    props: { funnel: funnel(), aiAvailable: true, ...props },
    global: {
      mocks: { $t: key => key },
      stubs: {
        Button: { template: '<button><slot /></button>' },
        ChoiceSelect: {
          props: ['modelValue'],
          template: '<span data-choice :data-value="modelValue" />',
        },
      },
    },
  });

const choices = wrapper =>
  wrapper.findAll('[data-choice]').map(node => node.attributes('data-value'));

describe('Anúncios da Meta · funil no passo 4 (#1047)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    CrmMetaAdsConnectionAPI.suggestStages.mockResolvedValue({
      data: {
        suggestions: [
          { stage_id: 10, type: 'lead', reason: 'Começou a conversa.' },
          { stage_id: 11, type: 'opportunity', reason: 'Recebeu a proposta.' },
        ],
      },
    });
  });

  it('asks the AI when no stage has a type, and fills only progress stages', async () => {
    const wrapper = mountCard();
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.suggestStages).toHaveBeenCalledWith(3);
    expect(choices(wrapper)).toEqual(['lead', 'opportunity']);
    expect(wrapper.findAll('[data-funnel-reason]')).toHaveLength(2);
    expect(wrapper.findAll('[data-funnel-missing] li')).toHaveLength(2);
  });

  it('does not call the AI when stages already have a type or AI is off', async () => {
    const typed = funnel({
      stages: [{ id: 10, name: 'Novo', funnel_stage_type: 'qualified' }],
    });
    mountCard({ funnel: typed });
    mountCard({ aiAvailable: false });
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.suggestStages).not.toHaveBeenCalled();
  });

  it('saves every progress stage type to the pipeline and hands back the fresh list', async () => {
    const fresh = { funnels: [], unlinked_numbers: [], ai_available: true };
    CrmMetaAdsConnectionAPI.saveFunnel.mockResolvedValue({ data: fresh });
    const wrapper = mountCard();
    await flushPromises();

    await wrapper.find('[data-funnel-save]').trigger('click');
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.saveFunnel).toHaveBeenCalledWith(3, [
      { id: 10, funnel_stage_type: 'lead' },
      { id: 11, funnel_stage_type: 'opportunity' },
    ]);
    expect(wrapper.emitted('updated')[0]).toEqual([fresh]);
  });

  it('shows a ready pipeline closed, and stops only that pipeline', async () => {
    CrmMetaAdsConnectionAPI.stopFunnel.mockResolvedValue({ data: {} });
    const ready = funnel({
      enabled: true,
      missing: [],
      stages: [{ id: 10, name: 'Novo', funnel_stage_type: 'lead' }],
    });
    const wrapper = mountCard({ funnel: ready });

    expect(wrapper.find('[data-funnel-stage]').exists()).toBe(false);
    await wrapper.find('[data-funnel-toggle]').trigger('click');
    await wrapper.find('[data-funnel-stop]').trigger('click');
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.stopFunnel).toHaveBeenCalledWith(3);
  });

  it('shows what was there before only where the AI changed a saved choice (#1068)', async () => {
    const mixed = funnel({
      stages: [
        { id: 10, name: 'Novo', funnel_stage_type: null, result: false },
        {
          id: 11,
          name: 'Proposta',
          funnel_stage_type: 'qualified',
          result: false,
        },
      ],
    });
    const wrapper = mountCard({ funnel: mixed });

    await wrapper.find('[data-funnel-suggest]').trigger('click');
    await flushPromises();

    const before = wrapper.findAll('[data-funnel-before]');
    expect(before).toHaveLength(1);
    expect(
      wrapper
        .get('[data-funnel-stage="11"]')
        .find('[data-funnel-before]')
        .exists()
    ).toBe(true);
  });
});
