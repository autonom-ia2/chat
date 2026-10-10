import { mount, flushPromises } from '@vue/test-utils';
import BookingPagesAPI from 'dashboard/api/crmBookingPages';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import BookingReassignPanel from '../components/BookingReassignPanel.vue';

// Passar reuniões (#1195, J8-A10): escolher de quem e para quem, ver antes
// (prévia sem gravar), confirmar, conflitos e recusas do servidor.
vi.mock('vue-i18n', async () => {
  const { ref } = await import('vue');
  return {
    useI18n: () => ({
      locale: ref('pt-BR'),
      t: (key, values) =>
        values === undefined ? key : `${key} ${JSON.stringify(values)}`,
    }),
  };
});
vi.mock('dashboard/api/crmBookingPages', () => ({
  default: { people: vi.fn(), reassignPreview: vi.fn(), reassign: vi.fn() },
}));

const PEOPLE = [
  { id: 4, name: 'Rui' },
  { id: 5, name: 'Camila' },
  { id: 6, name: 'Paula' },
];

const mountPanel = async (page = { id: 7, title: 'Vendas' }) => {
  BookingPagesAPI.people.mockResolvedValue({ data: { payload: PEOPLE } });
  const wrapper = mount(BookingReassignPanel, { props: { page } });
  await flushPromises();
  return wrapper;
};

const choose = async (wrapper, from, to) => {
  const [fromSelect, toSelect] = wrapper.findAllComponents(ChoiceSelect);
  fromSelect.vm.$emit('update:modelValue', from);
  await flushPromises();
  toSelect.vm.$emit('update:modelValue', to);
  await flushPromises();
};

describe('BookingReassignPanel', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('carrega as pessoas da página e não deixa escolher a mesma pessoa dos dois lados', async () => {
    const wrapper = await mountPanel();
    expect(BookingPagesAPI.people).toHaveBeenCalledWith(7);
    const [fromSelect, toSelect] = wrapper.findAllComponents(ChoiceSelect);
    expect(fromSelect.props('options').map(item => item.value)).toEqual([
      4, 5, 6,
    ]);
    expect(toSelect.props('disabled')).toBe(true);

    fromSelect.vm.$emit('update:modelValue', 4);
    await flushPromises();
    expect(toSelect.props('options').map(item => item.value)).toEqual([5, 6]);
    expect(toSelect.props('disabled')).toBe(false);
    expect(
      wrapper.find('[data-preview-button]').attributes('disabled')
    ).toBeDefined();
  });

  it('De quem inclui quem não atende mais e ficou com reunião; Para quem, não (#1195)', async () => {
    const wrapper = await mountPanel({
      id: 7,
      title: 'Vendas',
      orphaned: [
        { id: 9, name: 'Vendedor', upcoming_meetings_count: 1 },
        { id: 5, name: 'Camila', upcoming_meetings_count: 1 },
      ],
    });
    const [fromSelect, toSelect] = wrapper.findAllComponents(ChoiceSelect);

    expect(fromSelect.props('options')).toEqual([
      { value: 4, label: 'Rui' },
      { value: 5, label: 'Camila' },
      { value: 6, label: 'Paula' },
      { value: 9, label: 'BOOKING.REASSIGN.FORMER {"name":"Vendedor"}' },
    ]);
    fromSelect.vm.$emit('update:modelValue', 9);
    await flushPromises();
    expect(toSelect.props('options').map(item => item.value)).toEqual([
      4, 5, 6,
    ]);
  });

  it('mostra antes o que vai acontecer, com os conflitos, sem passar nada', async () => {
    BookingPagesAPI.reassignPreview.mockResolvedValue({
      data: {
        payload: {
          moved: 2,
          conflicts: [
            {
              meeting_id: 91,
              starts_at: '2026-10-20T13:00:00Z',
              title: 'Conversa',
            },
          ],
        },
      },
    });
    const wrapper = await mountPanel();
    await choose(wrapper, 4, 5);

    await wrapper.find('[data-preview-button]').trigger('click');
    await flushPromises();

    expect(BookingPagesAPI.reassignPreview).toHaveBeenCalledWith({
      fromUserId: 4,
      toUserId: 5,
      pageId: 7,
    });
    expect(BookingPagesAPI.reassign).not.toHaveBeenCalled();
    const preview = wrapper.find('[data-preview]');
    expect(preview.text()).toContain(
      'BOOKING.REASSIGN.WILL_MOVE {"name":"Camila","count":2}'
    );
    expect(preview.find('[data-conflict="91"]').text()).toContain('Conversa');
    expect(wrapper.find('[data-confirm-reassign]').exists()).toBe(true);
  });

  it('desligar "só desta página" passa as de todas as páginas', async () => {
    BookingPagesAPI.reassignPreview.mockResolvedValue({
      data: { payload: { moved: 1, conflicts: [] } },
    });
    const wrapper = await mountPanel();
    await choose(wrapper, 4, 6);
    await wrapper.find('[data-only-page]').trigger('click');

    await wrapper.find('[data-preview-button]').trigger('click');
    await flushPromises();

    expect(BookingPagesAPI.reassignPreview).toHaveBeenCalledWith({
      fromUserId: 4,
      toUserId: 6,
      pageId: null,
    });
  });

  it('confirmar passa, mostra o resultado e avisa quem abriu o painel', async () => {
    BookingPagesAPI.reassignPreview.mockResolvedValue({
      data: { payload: { moved: 3, conflicts: [] } },
    });
    BookingPagesAPI.reassign.mockResolvedValue({
      data: { payload: { moved: 3, conflicts: [] } },
    });
    const wrapper = await mountPanel();
    await choose(wrapper, 4, 5);
    await wrapper.find('[data-preview-button]').trigger('click');
    await flushPromises();

    await wrapper.find('[data-confirm-reassign]').trigger('click');
    await flushPromises();

    expect(BookingPagesAPI.reassign).toHaveBeenCalledWith({
      fromUserId: 4,
      toUserId: 5,
      pageId: 7,
    });
    expect(wrapper.find('[data-result]').text()).toBe(
      'BOOKING.REASSIGN.DONE {"name":"Camila","count":3}'
    );
    expect(wrapper.emitted('done')).toEqual([[{ moved: 3, conflicts: [] }]]);
  });

  it('sem reunião para passar, o botão de confirmar fica desligado', async () => {
    BookingPagesAPI.reassignPreview.mockResolvedValue({
      data: { payload: { moved: 0, conflicts: [] } },
    });
    const wrapper = await mountPanel();
    await choose(wrapper, 4, 5);
    await wrapper.find('[data-preview-button]').trigger('click');
    await flushPromises();

    expect(
      wrapper.find('[data-confirm-reassign]').attributes('disabled')
    ).toBeDefined();
  });

  it('trocar a pessoa depois da prévia apaga a prévia (nada passa sem ver antes)', async () => {
    BookingPagesAPI.reassignPreview.mockResolvedValue({
      data: { payload: { moved: 1, conflicts: [] } },
    });
    const wrapper = await mountPanel();
    await choose(wrapper, 4, 5);
    await wrapper.find('[data-preview-button]').trigger('click');
    await flushPromises();

    wrapper.findAllComponents(ChoiceSelect)[1].vm.$emit('update:modelValue', 6);
    await flushPromises();

    expect(wrapper.find('[data-preview]').exists()).toBe(false);
    expect(wrapper.find('[data-confirm-reassign]').exists()).toBe(false);
  });

  it('pessoa que não pode receber reuniões mostra o aviso próprio', async () => {
    BookingPagesAPI.reassignPreview.mockRejectedValue({
      response: { data: { error: 'crm.booking_v2.people_invalid' } },
    });
    const wrapper = await mountPanel();
    await choose(wrapper, 4, 5);
    await wrapper.find('[data-preview-button]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[role="alert"]').text()).toBe(
      'BOOKING.REASSIGN.PEOPLE_INVALID'
    );
    expect(wrapper.emitted('done')).toBeUndefined();
  });
});
