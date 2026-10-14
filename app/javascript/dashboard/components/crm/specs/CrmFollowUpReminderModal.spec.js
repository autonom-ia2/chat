import { mount } from '@vue/test-utils';
import { ref, computed } from 'vue';
import CrmFollowUpReminderModal from '../CrmFollowUpReminderModal.vue';

const reminder = ref(null);
const push = vi.fn();
const emit = vi.fn();
const currentRoute = { value: { name: 'home', params: { accountId: '16' } } };
const completeReminder = vi.fn();
const dismissReminder = vi.fn();

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => (params ? `${key} ${JSON.stringify(params)}` : key),
    locale: { value: 'pt_BR' },
  }),
}));
vi.mock('vue-router', () => ({
  useRouter: () => ({ push, currentRoute }),
}));
vi.mock('shared/helpers/mitt', () => ({
  emitter: { emit: (...args) => emit(...args) },
}));
vi.mock('dashboard/composables/emitter', () => ({ useEmitter: vi.fn() }));
vi.mock('dashboard/composables/useCrmFollowUpReminders', () => ({
  useCrmFollowUpReminders: () => ({
    activeReminder: reminder,
    hasReminder: computed(() => !!reminder.value),
    enqueueReminder: vi.fn(),
    fetchMissedReminders: vi.fn(),
    completeReminder,
    dismissReminder,
    isCrmEnabled: () => false,
  }),
}));

const KEY = 'CRM_KANBAN.FOLLOW_UP_REMINDER';
const BASE = {
  id: 7,
  account_id: 16,
  card_id: 42,
  card: { id: 42, title: 'Rodrigo Victor - Chat2you' },
  automation_mode: 'reminder_only',
  due_at: '2026-10-11T08:24:02Z',
};
const noticeFailed = metadata => ({
  ...BASE,
  title:
    'O aviso no WhatsApp para Rodrigo Victor não saiu. O horário de 20/10 às 10:00 continua marcado: fale com o cliente.',
  metadata: {
    source: 'booking_agent_alert',
    event: 'notice_failed',
    meeting_id: 3,
    ...metadata,
  },
});

const mountModal = value => {
  reminder.value = value;
  return mount(CrmFollowUpReminderModal, {
    global: {
      stubs: {
        transition: false,
        Button: {
          props: ['label'],
          template: '<button :data-label="label">{{ label }}</button>',
        },
      },
    },
  });
};

describe('CrmFollowUpReminderModal', () => {
  beforeEach(() => {
    push.mockReset();
    emit.mockReset();
    currentRoute.value = { name: 'home', params: { accountId: '16' } };
    completeReminder.mockReset();
    dismissReminder.mockReset();
  });

  it('lembrete comum do CRM continua como lembrete de retorno', () => {
    const wrapper = mountModal({ ...BASE, title: 'Retornar para o cliente' });
    const text = wrapper.text();

    expect(text).toContain(`${KEY}.HEADING`);
    expect(text).toContain('Retornar para o cliente');
    expect(text).toContain(`${KEY}.DUE`);
    expect(text).toContain(`${KEY}.MODE_REMINDER`);
    expect(text).not.toContain('BOOKING_ALERT');
    expect(
      wrapper.findAll('button').map(button => button.attributes('data-label'))
    ).toEqual([`${KEY}.OPEN_CRM`, `${KEY}.DISMISS`, `${KEY}.COMPLETE`]);
  });

  it('aviso que não saiu ganha título próprio, frase inteira com o motivo e nada de "Venceu em"', () => {
    const wrapper = mountModal(
      noticeFailed({
        contact_name: 'Rodrigo Victor',
        starts_at: '2026-10-20T13:00:00Z',
        kind: 'booked',
        reason: 'template_required',
      })
    );
    const text = wrapper.text();
    const body = wrapper.find('[data-test-id="booking-alert-text"]');

    expect(text).toContain(`${KEY}.BOOKING_ALERT.NOTICE_FAILED_HEADING`);
    expect(text).not.toContain(`${KEY}.HEADING`);
    expect(body.text()).toContain(
      `${KEY}.BOOKING_ALERT.NOTICE_FAILED_BODY_REASON`
    );
    expect(body.text()).toContain('"name":"Rodrigo Victor"');
    expect(body.text()).toContain(
      'CRM_KANBAN.CALENDAR.MEETING_DETAIL.NOTICES.SKIP_REASONS.TEMPLATE_REQUIRED'
    );
    expect(body.classes()).not.toContain('truncate');
    expect(text).toContain(`${KEY}.BOOKING_ALERT.NOTICE_FAILED_HINT`);
    expect(text).not.toContain(`${KEY}.DUE`);
    expect(text).not.toContain(`${KEY}.MODE_REMINDER`);
    expect(
      wrapper.findAll('button').map(button => button.attributes('data-label'))
    ).toEqual([`${KEY}.BOOKING_ALERT.ACK`, `${KEY}.BOOKING_ALERT.OPEN_CARD`]);
  });

  it('erro do envio sem motivo com texto diz só que o aviso não saiu', () => {
    const wrapper = mountModal(
      noticeFailed({
        contact_name: 'Rodrigo Victor',
        starts_at: '2026-10-20T13:00:00Z',
        reason: 'Net::ReadTimeout',
      })
    );
    const body = wrapper.find('[data-test-id="booking-alert-text"]').text();

    expect(body).toContain(`${KEY}.BOOKING_ALERT.NOTICE_FAILED_BODY `);
    expect(body).not.toContain('SKIP_REASONS');
  });

  it('alerta gravado antes da mudança mostra o texto do backend inteiro', () => {
    const wrapper = mountModal(noticeFailed({}));
    const body = wrapper.find('[data-test-id="booking-alert-text"]');

    expect(body.text()).toBe(reminder.value.title);
    expect(wrapper.text()).not.toContain(`${KEY}.DUE`);
  });

  it('o que o cliente fez pela página aparece como agendamento, sem "Venceu em"', () => {
    const wrapper = mountModal({
      ...BASE,
      title: 'Rodrigo Victor cancelou o horário de 20/10 às 10:00',
      metadata: { source: 'booking_agent_alert', event: 'canceled' },
    });
    const text = wrapper.text();

    expect(text).toContain(`${KEY}.BOOKING_ALERT.HEADING`);
    expect(text).toContain('Rodrigo Victor cancelou o horário');
    expect(text).not.toContain(`${KEY}.BOOKING_ALERT.NOTICE_FAILED_HINT`);
    expect(text).not.toContain(`${KEY}.DUE`);
  });

  it('"Abrir o card" leva ao card no CRM e tira o cartão da tela; "Entendi" conclui', async () => {
    const wrapper = mountModal(noticeFailed({ contact_name: 'Rodrigo' }));
    const [ack, openCard] = wrapper.findAll('button');

    await openCard.trigger('click');
    await vi.waitFor(() => expect(dismissReminder).toHaveBeenCalledWith(7, 16));
    expect(push).toHaveBeenCalledWith({
      path: '/app/accounts/16/crm',
      query: { card_id: '42' },
    });

    expect(emit).not.toHaveBeenCalled();

    await ack.trigger('click');
    expect(completeReminder).toHaveBeenCalledWith(7, 16);
  });

  it('com o quadro do CRM desta conta já aberto, "Abrir o card" pede a abertura ao quadro em vez de repetir a URL', async () => {
    currentRoute.value = {
      name: 'crm_kanban_index',
      params: { accountId: '16' },
    };
    const wrapper = mountModal(noticeFailed({ contact_name: 'Rodrigo' }));

    await wrapper.findAll('button')[1].trigger('click');
    await vi.waitFor(() => expect(dismissReminder).toHaveBeenCalledWith(7, 16));

    expect(emit).toHaveBeenCalledWith('CRM_OPEN_CARD', 42);
    expect(push).not.toHaveBeenCalled();
  });

  it('no quadro de outra conta, "Abrir o card" navega para a conta do alerta', async () => {
    currentRoute.value = {
      name: 'crm_kanban_index',
      params: { accountId: '3' },
    };
    const wrapper = mountModal(noticeFailed({ contact_name: 'Rodrigo' }));

    await wrapper.findAll('button')[1].trigger('click');
    await vi.waitFor(() => expect(dismissReminder).toHaveBeenCalledWith(7, 16));

    expect(push).toHaveBeenCalledWith({
      path: '/app/accounts/16/crm',
      query: { card_id: '42' },
    });
    expect(emit).not.toHaveBeenCalled();
  });
});
