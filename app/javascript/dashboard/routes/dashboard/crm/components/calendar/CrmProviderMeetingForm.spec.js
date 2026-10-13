import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from '../../../../../../../../vitest.i18n';
import CrmProviderMeetingForm from './CrmProviderMeetingForm.vue';
import crmMeetingsAPI from 'dashboard/api/crmMeetings';

// O formulário do Google/Microsoft saiu da janela do calendário (#1423) para o
// card do funil marcar na própria gaveta. Mesmo pedido de antes: convite com o
// e-mail do contato, caixa pessoal primeiro, lembrete de 15 min.
withFullI18n('pt_BR');

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 1 } }),
}));
vi.mock('dashboard/api/crmMeetings', () => ({
  default: {
    getAvailability: vi.fn(() => Promise.resolve({ data: { payload: {} } })),
    createMeeting: vi.fn(),
    reschedule: vi.fn(),
  },
}));

const PESSOAL = { id: 9, calendar_enabled: true, provider: 'google' };
const SETOR = {
  id: 10,
  calendar_enabled: true,
  provider: 'microsoft',
  shared: true,
};

const montar = (props = {}) =>
  mount(CrmProviderMeetingForm, {
    props: {
      active: true,
      accountId: 1,
      cardId: 7,
      date: '2099-10-20',
      availableInboxes: [SETOR, PESSOAL],
      cardContactEmail: 'Marcos@Exemplo.com ',
      cardContactName: 'Marcos',
      ...props,
    },
  });

describe('CrmProviderMeetingForm', () => {
  afterEach(() => vi.clearAllMocks());

  it('marca pela caixa pessoal, com o contato convidado e o lembrete', async () => {
    crmMeetingsAPI.createMeeting.mockResolvedValue({
      data: { payload: { id: 70 } },
    });
    const wrapper = montar();
    await wrapper.find('input').setValue('Apresentação do plano');

    await wrapper.vm.submit();
    await flushPromises();

    const [conta, pedido] = crmMeetingsAPI.createMeeting.mock.calls[0];
    expect(conta).toBe(1);
    expect(pedido).toMatchObject({
      card_id: 7,
      inbox_id: 9,
      meeting: {
        title: 'Apresentação do plano',
        provider: 'google',
        reminder_minutes_before: 15,
        extra_guests: ['marcos@exemplo.com'],
      },
    });
    expect(pedido.meeting.starts_at.startsWith('2099-10-20T09:00:00')).toBe(
      true
    );
    expect(wrapper.emitted('create')[0][0]).toEqual({ id: 70 });
    expect(wrapper.emitted('saving').map(([valor]) => valor)).toEqual([
      true,
      false,
    ]);
  });

  it('não envia sem nome e mostra o que falta', async () => {
    const wrapper = montar();

    await wrapper.vm.submit();
    await flushPromises();

    expect(crmMeetingsAPI.createMeeting).not.toHaveBeenCalled();
    expect(wrapper.emitted('create')).toBeUndefined();
    expect(wrapper.text()).toContain('Adicione um título para a reunião');
  });

  it('mostra o erro do provedor e não fecha', async () => {
    crmMeetingsAPI.createMeeting.mockRejectedValue({
      response: { data: { error: 'Agenda do Google recusou' } },
    });
    const wrapper = montar();
    await wrapper.find('input').setValue('Apresentação');

    await wrapper.vm.submit();
    await flushPromises();

    expect(wrapper.find('[role="alert"]').text()).toContain(
      'Agenda do Google recusou'
    );
    expect(wrapper.emitted('create')).toBeUndefined();
  });

  it('ao remarcar, manda só início, fim e fuso e avisa por `updated`', async () => {
    crmMeetingsAPI.reschedule.mockResolvedValue({
      data: { payload: { id: 12 } },
    });
    const wrapper = montar({
      meeting: {
        id: 12,
        title: 'Reunião antiga',
        inbox_id: 9,
        starts_at: '2099-10-21T14:00:00',
        ends_at: '2099-10-21T14:45:00',
        guests: [{ email: 'marcos@exemplo.com', guest_type: 'contact_guest' }],
      },
    });

    await wrapper.vm.submit();
    await flushPromises();

    const [, id, corpo] = crmMeetingsAPI.reschedule.mock.calls[0];
    expect(id).toBe(12);
    expect(Object.keys(corpo.meeting)).toEqual([
      'starts_at',
      'ends_at',
      'timezone',
    ]);
    expect(corpo.meeting.starts_at.startsWith('2099-10-21T14:00:00')).toBe(
      true
    );
    expect(corpo.meeting.ends_at.startsWith('2099-10-21T14:45:00')).toBe(true);
    expect(crmMeetingsAPI.createMeeting).not.toHaveBeenCalled();
    expect(wrapper.emitted('updated')[0][0]).toEqual({ id: 12 });
  });

  it('Enter confirma o convidado digitado; e-mail inválido segura o envio', async () => {
    const wrapper = montar({ cardContactEmail: '' });
    await wrapper.find('input').setValue('Apresentação');
    const campo = wrapper.find('input[type="email"]');

    await campo.setValue('ana@exemplo.com');
    await campo.trigger('keydown', { key: 'Enter' });
    expect(wrapper.text()).toContain('ana@exemplo.com');

    await campo.setValue('isso-nao-e-email');
    await wrapper.vm.submit();
    await flushPromises();
    expect(crmMeetingsAPI.createMeeting).not.toHaveBeenCalled();
  });

  it('horário ocupado na agenda fica bloqueado', async () => {
    crmMeetingsAPI.getAvailability.mockResolvedValue({
      data: {
        payload: {
          busy: [{ start: '2099-10-20T09:00:00', end: '2099-10-20T10:00:00' }],
        },
      },
    });
    const wrapper = montar();
    await flushPromises();

    const nove = wrapper
      .findAll('button')
      .find(botao => botao.text().startsWith('09:00'));
    expect(nove.attributes('disabled')).toBeDefined();
  });
});
