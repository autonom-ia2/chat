import { mount, flushPromises } from '@vue/test-utils';
import crmMeetingsAPI from 'dashboard/api/crmMeetings';
import CrmMeetingDetail from './CrmMeetingDetail.vue';

// O detalhe da reunião no dia (#1193): o resultado usa o registro de sempre
// (J4-A3) e, depois de "Aconteceu", mostra a pergunta de mover o card que veio
// na resposta (J4-A7); depois de "Não compareceu", o link para remarcar (J4-A6).
vi.mock('vue-router', () => ({ useRouter: () => ({ push: vi.fn() }) }));
vi.mock('dashboard/api/crmMeetings', () => ({
  default: { show: vi.fn(), sync: vi.fn(), recordOutcome: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const finished = (extra = {}) => ({
  id: 7,
  card_id: 30,
  title: 'Conversa de 30 min',
  status: 'scheduled',
  provider: 'internal',
  online_meeting_type: 'whatsapp_video',
  location_type: 'whatsapp_video',
  starts_at: '2026-01-15T14:00:00Z',
  ends_at: '2026-01-15T14:30:00Z',
  timezone: 'UTC',
  booking: true,
  confirmation_status: 'confirmed',
  notices: [],
  guests: [],
  outcome: null,
  client: {
    name: 'Ana Souza',
    phone: '+5511988887777',
    whatsapp_url: 'https://wa.me/5511988887777',
  },
  ...extra,
});

const mountDetail = async event => {
  crmMeetingsAPI.sync.mockResolvedValue({ data: { payload: event } });
  const wrapper = mount(CrmMeetingDetail, {
    props: { show: true, event, accountId: 1, timezone: 'UTC' },
    global: {
      stubs: {
        Dialog: true,
        Spinner: true,
        Button: {
          props: ['label'],
          emits: ['click'],
          template:
            '<button :data-label="label" @click="$emit(\'click\')">{{ label }}</button>',
        },
      },
    },
  });
  await flushPromises();
  return wrapper;
};

const outcomeButton = (wrapper, key) =>
  wrapper.find(
    `button[data-label="CRM_KANBAN.CALENDAR.MEETING_DETAIL.${key}"]`
  );

describe('CrmMeetingDetail: dia da reunião', () => {
  beforeEach(() => vi.clearAllMocks());

  it('after "Aconteceu" shows the question to move the card that came with the outcome', async () => {
    crmMeetingsAPI.recordOutcome.mockResolvedValue({
      data: {
        payload: finished({ outcome: 'held' }),
        post_meeting: {
          mode: 'ask',
          moved: false,
          stage: { id: 9, name: 'Proposta' },
        },
      },
    });
    const wrapper = await mountDetail(finished());
    expect(wrapper.find('[data-test="meeting-post-move"]').exists()).toBe(
      false
    );

    await outcomeButton(wrapper, 'OUTCOME_HELD').trigger('click');
    await flushPromises();

    expect(crmMeetingsAPI.recordOutcome).toHaveBeenCalledWith(1, '7', {
      outcome: 'held',
    });
    const prompt = wrapper.find('[data-test="meeting-post-move"]');
    expect(prompt.attributes('data-mode')).toBe('ask');
    expect(prompt.text()).toContain(
      'CRM_KANBAN.CALENDAR.MEETING_DAY.MOVE_QUESTION'
    );
    expect(wrapper.emitted('updated')).toHaveLength(1);
  });

  it('after "Não compareceu" offers the link to pick another time, and no move question', async () => {
    crmMeetingsAPI.recordOutcome.mockResolvedValue({
      data: { payload: finished({ outcome: 'no_show' }), post_meeting: null },
    });
    const wrapper = await mountDetail(finished());

    await outcomeButton(wrapper, 'OUTCOME_NO_SHOW').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-test="meeting-rebook"]').exists()).toBe(true);
    expect(wrapper.find('[data-test="meeting-post-move"]').exists()).toBe(
      false
    );
  });

  it('shows the client number in the detail', async () => {
    const wrapper = await mountDetail(finished());

    expect(wrapper.find('[data-test="meeting-client-phone"]').text()).toContain(
      '+55 11 98888 7777'
    );
  });
});
