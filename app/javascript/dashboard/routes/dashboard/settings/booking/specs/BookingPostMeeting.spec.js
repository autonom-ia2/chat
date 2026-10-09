import { mount, flushPromises } from '@vue/test-utils';
import BookingPagesAPI from 'dashboard/api/crmBookingPages';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import BookingPostMeeting from '../components/BookingPostMeeting.vue';

// "Depois da reunião" na prévia (#1193, J4-A7): o admin escolhe a etapa (funil
// ativo, ChoiceSelect) e se o sistema pergunta antes ou move sozinho (cartões).
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values) =>
      values === undefined ? key : `${key} ${JSON.stringify(values)}`,
  }),
}));
vi.mock('dashboard/api/crmBookingPages', () => ({
  default: { update: vi.fn() },
}));
vi.mock('dashboard/api/crmKanban', () => ({
  default: { getPipelines: vi.fn(), getStages: vi.fn() },
}));

const PIPELINES = [
  { id: 2, name: 'Vendas', status: 'active' },
  { id: 3, name: 'Antigo', status: 'archived' },
  { id: 4, name: 'Pós-venda', status: 'active' },
];
const STAGES = {
  2: [
    { id: 20, name: 'Conversa agendada' },
    { id: 21, name: 'Proposta' },
  ],
  4: [{ id: 40, name: 'Boas-vindas' }],
};

const mountSection = async (postMeeting = {}, canManage = true) => {
  const wrapper = mount(BookingPostMeeting, {
    props: { pageId: 7, postMeeting, canManage },
  });
  await flushPromises();
  return wrapper;
};

const sentence = wrapper => wrapper.find('[data-post-meeting-sentence]').text();

describe('BookingPostMeeting', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    CrmKanbanAPI.getPipelines.mockResolvedValue({
      data: { payload: PIPELINES },
    });
    CrmKanbanAPI.getStages.mockImplementation(id =>
      Promise.resolve({ data: { payload: STAGES[id] || [] } })
    );
  });

  it('says the card stays put when no stage is chosen', async () => {
    const wrapper = await mountSection({ mode: 'ask', stage_id: null });

    expect(sentence(wrapper)).toBe('BOOKING.POST_MEETING.OFF');
  });

  it('says what happens in each mode with the stage name', async () => {
    const ask = await mountSection({
      mode: 'ask',
      stage_id: 21,
      pipeline_id: 2,
    });
    expect(sentence(ask)).toBe(
      'BOOKING.POST_MEETING.SUMMARY_ASK {"stage":"Proposta"}'
    );

    const auto = await mountSection({
      mode: 'auto',
      stage_id: 21,
      pipeline_id: 2,
    });
    expect(sentence(auto)).toBe(
      'BOOKING.POST_MEETING.SUMMARY_AUTO {"stage":"Proposta"}'
    );
    // Card de outro funil não muda: a frase diz isso quando há etapa.
    expect(auto.find('[data-post-meeting-scope]').text()).toBe(
      'BOOKING.POST_MEETING.SCOPE_HINT'
    );
  });

  it('has no scope line when the card stays put', async () => {
    const wrapper = await mountSection({ mode: 'ask', stage_id: null });

    expect(wrapper.find('[data-post-meeting-scope]').exists()).toBe(false);
  });

  it('lets the admin choose an active pipeline, the stage and the mode, then saves only post_meeting', async () => {
    const saved = {
      id: 7,
      post_meeting: { mode: 'auto', stage_id: 40, pipeline_id: 4 },
    };
    BookingPagesAPI.update.mockResolvedValue({ data: { payload: saved } });
    const wrapper = await mountSection({ mode: 'ask', stage_id: null });

    await wrapper.find('[data-post-meeting-alter]').trigger('click');
    const [pipeline, stage] = wrapper.findAllComponents(ChoiceSelect);
    expect(pipeline.props('options')).toEqual([
      { value: 2, label: 'Vendas' },
      { value: 4, label: 'Pós-venda' },
    ]);
    expect(
      wrapper.find('[data-post-meeting-save]').attributes('disabled')
    ).toBeDefined();

    pipeline.vm.$emit('update:modelValue', 4);
    await flushPromises();
    expect(stage.props('options')).toEqual([
      { value: 40, label: 'Boas-vindas' },
    ]);
    stage.vm.$emit('update:modelValue', 40);
    await wrapper.find('[data-choice="auto"] input').setValue(true);
    await wrapper.find('[data-post-meeting-save]').trigger('click');
    await flushPromises();

    expect(BookingPagesAPI.update).toHaveBeenCalledWith(7, {
      post_meeting: { mode: 'auto', stage_id: 40 },
    });
    expect(wrapper.emitted('saved')[0]).toEqual([saved]);
    expect(wrapper.find('[data-post-meeting-form]').exists()).toBe(false);
  });

  it('"Não mover o card" turns it off, and a refused save keeps the form with a lay error', async () => {
    BookingPagesAPI.update.mockResolvedValueOnce({
      data: { payload: { id: 7 } },
    });
    const wrapper = await mountSection({
      mode: 'ask',
      stage_id: 21,
      pipeline_id: 2,
    });

    await wrapper.find('[data-post-meeting-alter]').trigger('click');
    await wrapper.find('[data-post-meeting-off]').trigger('click');
    await flushPromises();
    expect(BookingPagesAPI.update).toHaveBeenLastCalledWith(7, {
      post_meeting: { stage_id: null },
    });

    BookingPagesAPI.update.mockRejectedValueOnce({ response: { status: 422 } });
    await wrapper.find('[data-post-meeting-alter]').trigger('click');
    await wrapper.find('[data-post-meeting-save]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-post-meeting-form]').exists()).toBe(true);
    expect(wrapper.text()).toContain('BOOKING.POST_MEETING.SAVE_ERROR');
  });

  it('someone who only views has no "Alterar"', async () => {
    const wrapper = await mountSection(
      { mode: 'ask', stage_id: 21, pipeline_id: 2 },
      false
    );

    expect(wrapper.find('[data-post-meeting-alter]').exists()).toBe(false);
  });
});
