import { flushPromises, mount } from '@vue/test-utils';
import { defineComponent, h } from 'vue';
import CalendarioReuniao from './CalendarioReuniao.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => (params?.nome ? `${key}:${params.nome}` : key),
  }),
}));
const dispatch = vi.fn();
vi.mock('vuex', () => ({ useStore: () => ({ dispatch }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const submit = vi.fn();
const formulario = nome =>
  defineComponent({
    name: nome,
    props: {
      pages: { type: Array, default: () => [] },
      card: { type: Object, default: null },
      cardId: { type: [Number, String], default: null },
      initialDay: { type: String, default: '' },
      date: { type: [Date, String], default: null },
    },
    setup(props, { expose }) {
      expose({ submit, isShowingLink: false });
      return () =>
        h('div', {
          'data-form': nome,
          'data-card': props.cardId,
          'data-dia': props.initialDay,
          'data-paginas': props.pages.length,
          'data-cliente': props.card?.contact?.name,
          'data-data': props.date ? 'sim' : '',
        });
    },
  });

const montar = (props = {}) =>
  mount(CalendarioReuniao, {
    props: {
      show: true,
      cardId: 4,
      dia: '2026-10-16',
      jeito: 'pagina',
      paginas: [{ id: 1, title: 'Conversa de 30 min' }],
      accountId: 1,
      ...props,
    },
    global: {
      stubs: {
        CrmBookingAgendaForm: formulario('CrmBookingAgendaForm'),
        CrmProviderMeetingForm: formulario('CrmProviderMeetingForm'),
        CardHeroi: {
          props: ['titulo'],
          template: '<h2 data-heroi>{{ titulo }}</h2>',
        },
      },
    },
  });

describe('CalendarioReuniao', () => {
  beforeEach(() => {
    dispatch.mockReset();
    dispatch.mockResolvedValue({
      id: 4,
      title: 'Plano anual',
      contact: { name: 'Mariana Costa' },
    });
    submit.mockClear();
  });

  it('com página, abre o agendamento novo no negócio e no dia escolhidos', async () => {
    const wrapper = montar();
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('crmKanban/fetchCard', 4);
    const form = wrapper.find('[data-form="CrmBookingAgendaForm"]');
    expect(form.attributes('data-card')).toBe('4');
    expect(form.attributes('data-dia')).toBe('2026-10-16');
    expect(wrapper.find('[data-heroi]').text()).toContain('Mariana Costa');

    await wrapper.find('[data-card-principal]').trigger('click');
    expect(submit).toHaveBeenCalled();

    wrapper
      .findComponent({ name: 'CrmBookingAgendaForm' })
      .vm.$emit('booked', { id: 9 });
    expect(wrapper.emitted('marcou')[0]).toEqual([{ id: 9 }]);
    expect(wrapper.emitted('close')).toHaveLength(1);
  });

  it('com a agenda do Google/Microsoft, usa o formulário dela, como o card', async () => {
    const wrapper = montar({ jeito: 'externa', paginas: [] });
    await flushPromises();

    expect(wrapper.find('[data-form="CrmProviderMeetingForm"]').exists()).toBe(
      true
    );
    expect(wrapper.find('[data-form="CrmBookingAgendaForm"]').exists()).toBe(
      false
    );
  });
});
