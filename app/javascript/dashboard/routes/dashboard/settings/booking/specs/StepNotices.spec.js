import { config, mount, flushPromises } from '@vue/test-utils';
import BookingPagesAPI from 'dashboard/api/crmBookingPages';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import StepNotices from '../components/steps/StepNotices.vue';
import { POLL_MS } from '../useNoticeTemplateSuggestions';

// Modelos de aviso do WhatsApp oficial (#1272): a sugestão da IA entra só nos
// avisos vazios e mostra "Sugerido"; criar na Meta só no clique de quem pode,
// com o estado de cada aviso (enviando, em aprovação, aprovado, recusado).
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values) =>
      values === undefined ? key : `${key} ${JSON.stringify(values)}`,
  }),
}));
vi.mock('dashboard/api/crmBookingPages', () => ({
  default: {
    noticeTemplateSuggestions: vi.fn(),
    noticeTemplateRequests: vi.fn(),
    createNoticeTemplates: vi.fn(),
  },
}));
vi.mock('dashboard/api/whatsappApiMessageTemplates', () => ({
  default: { get: vi.fn(() => Promise.resolve({ data: { payload: [] } })) },
}));

const approved = (name, text) => ({
  name,
  language: 'pt_BR',
  status: 'APPROVED',
  category: 'UTILITY',
  components: [{ type: 'BODY', text }],
});
const lembrete = approved('lembrete', 'Oi {{1}}, seu horário é {{2}}: {{3}}');
const outro = approved('outro', 'Olá {{1}}, {{2}}. Link: {{3}}');

config.global.provide = {
  ...config.global.provide,
  store: {
    getters: {
      'inboxes/getConversationWhatsAppTemplates': vi.fn(() => [
        lembrete,
        outro,
      ]),
    },
  },
};

const PAGE_ID = 7;
const OFFICIAL = {
  id: 9,
  name: 'WhatsApp oficial',
  provider: 'whatsapp_cloud',
  needs_templates: true,
};

const form = (extra = {}) => ({
  noticeInboxId: 9,
  noticePreset: 'minimal',
  noticeTemplates: {},
  cancelUntilMinutes: 120,
  ...extra,
});

const reply = payload => Promise.resolve({ data: { payload } });
const suggestionsReply = payload =>
  reply({
    suggestions: {},
    requests: {},
    can_create: false,
    ai_failed: false,
    ...payload,
  });

const mountStep = async (formValue = form()) => {
  const wrapper = mount(StepNotices, {
    props: { form: formValue, inboxOptions: [OFFICIAL], pageId: PAGE_ID },
  });
  await flushPromises();
  return wrapper;
};

const changes = wrapper => wrapper.emitted('change') || [];
const stateText = (wrapper, kind) =>
  wrapper.find(`[data-template-kind="${kind}"] [data-request-state]`);

describe('StepNotices — modelos sugeridos e criados na Meta (#1272)', () => {
  beforeEach(() => {
    BookingPagesAPI.noticeTemplateSuggestions.mockReset();
    BookingPagesAPI.noticeTemplateRequests.mockReset();
    BookingPagesAPI.createNoticeTemplates.mockReset();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('pede a sugestão dos avisos vazios e pré-seleciona sem sobrescrever a escolha da pessoa', async () => {
    BookingPagesAPI.noticeTemplateSuggestions.mockImplementation(() =>
      suggestionsReply({
        suggestions: {
          booked: { name: 'lembrete', language: 'pt_BR', reason: 'Serve.' },
          rescheduled: { name: 'lembrete', language: 'pt_BR', reason: 'x' },
        },
      })
    );
    const wrapper = await mountStep(
      form({
        noticeTemplates: { rescheduled: { name: 'outro', language: 'pt_BR' } },
      })
    );

    expect(BookingPagesAPI.noticeTemplateSuggestions).toHaveBeenCalledWith(
      PAGE_ID,
      9,
      ['booked', 'day_before', 'hour_before']
    );
    const [last] = changes(wrapper).at(-1);
    expect(last.noticeTemplates).toEqual({
      rescheduled: { name: 'outro', language: 'pt_BR' },
      booked: { name: 'lembrete', language: 'pt_BR' },
    });
  });

  it('mostra "Sugerido" e o motivo quando o aviso está com a sugestão', async () => {
    BookingPagesAPI.noticeTemplateSuggestions.mockImplementation(() =>
      suggestionsReply({
        suggestions: {
          booked: { name: 'lembrete', language: 'pt_BR', reason: 'Serve.' },
        },
      })
    );
    const wrapper = await mountStep(
      form({
        noticeTemplates: { booked: { name: 'lembrete', language: 'pt_BR' } },
      })
    );

    const booked = wrapper.find('[data-template-kind="booked"]');
    expect(booked.find('[data-suggested]').exists()).toBe(true);
    expect(booked.find('[data-suggested-reason]').text()).toBe('Serve.');
    expect(
      wrapper
        .find('[data-template-kind="rescheduled"] [data-suggested]')
        .exists()
    ).toBe(false);
  });

  it('"nenhuma" escolhida à mão não é preenchida de novo pela sugestão', async () => {
    BookingPagesAPI.noticeTemplateSuggestions.mockImplementation(() =>
      suggestionsReply({
        suggestions: {
          booked: { name: 'lembrete', language: 'pt_BR', reason: 'Serve.' },
          hour_before: { name: 'outro', language: 'pt_BR', reason: 'Serve.' },
        },
      })
    );
    const wrapper = await mountStep(
      form({
        noticeTemplates: { booked: { name: 'outro', language: 'pt_BR' } },
      })
    );
    const before = changes(wrapper).length;

    wrapper
      .find('[data-template-kind="booked"]')
      .findComponent(ChoiceSelect)
      .vm.$emit('update:modelValue', '');
    await wrapper.setProps({ form: form({ noticePreset: 'light' }) });
    await flushPromises();

    const later = changes(wrapper).slice(before);
    expect(later.at(-1)[0].noticeTemplates).toEqual({
      hour_before: { name: 'outro', language: 'pt_BR' },
    });
  });

  it('se a IA falhar, a tela segue sem mudar nada', async () => {
    BookingPagesAPI.noticeTemplateSuggestions.mockImplementation(() =>
      Promise.reject(new Error('boom'))
    );
    const wrapper = await mountStep();

    expect(changes(wrapper)).toEqual([]);
    expect(wrapper.find('[data-suggested]').exists()).toBe(false);
    expect(wrapper.find('[data-create-templates]').exists()).toBe(false);
  });

  it('não pede sugestão para caixa que não é oficial', async () => {
    const waha = {
      id: 3,
      name: 'WAHA',
      provider: 'waha',
      needs_templates: false,
    };
    mount(StepNotices, {
      props: {
        form: form({ noticeInboxId: 3 }),
        inboxOptions: [waha],
        pageId: PAGE_ID,
      },
    });
    await flushPromises();

    expect(BookingPagesAPI.noticeTemplateSuggestions).not.toHaveBeenCalled();
  });

  it('botão de criar só para quem pode e só com aviso sem mensagem que sirva', async () => {
    BookingPagesAPI.noticeTemplateSuggestions.mockImplementation(() =>
      suggestionsReply({ can_create: false })
    );
    const manager = await mountStep();
    expect(manager.find('[data-create-templates]').exists()).toBe(false);

    BookingPagesAPI.noticeTemplateSuggestions.mockImplementation(() =>
      suggestionsReply({ can_create: true })
    );
    const admin = await mountStep();
    expect(admin.find('[data-create-templates-button]').exists()).toBe(true);
  });

  it('cria só no clique e acompanha: enviando → em aprovação, sem recarregar', async () => {
    vi.useFakeTimers();
    BookingPagesAPI.noticeTemplateSuggestions.mockImplementation(() =>
      suggestionsReply({ can_create: true })
    );
    BookingPagesAPI.createNoticeTemplates.mockImplementation(() =>
      reply({
        queued: true,
        requests: {
          booked: { state: 'sending' },
          rescheduled: { state: 'sending' },
        },
      })
    );
    BookingPagesAPI.noticeTemplateRequests.mockImplementation(() =>
      reply({
        requests: {
          booked: { state: 'pending' },
          rescheduled: { state: 'failed', reason: 'Reconecte a caixa.' },
        },
      })
    );
    const wrapper = await mountStep();
    expect(BookingPagesAPI.createNoticeTemplates).not.toHaveBeenCalled();

    await wrapper.find('[data-create-templates-button]').trigger('click');
    await flushPromises();

    expect(BookingPagesAPI.createNoticeTemplates).toHaveBeenCalledWith(
      PAGE_ID,
      9,
      ['booked', 'rescheduled']
    );
    expect(stateText(wrapper, 'booked').text()).toContain(
      'BOOKING.NOTICES.AUTO.SENDING'
    );
    expect(wrapper.find('[data-create-templates]').exists()).toBe(false);
    expect(wrapper.find('[data-retry]').exists()).toBe(false);

    await vi.advanceTimersByTimeAsync(POLL_MS);
    await flushPromises();

    expect(BookingPagesAPI.noticeTemplateRequests).toHaveBeenCalledWith(
      PAGE_ID,
      9
    );
    expect(stateText(wrapper, 'booked').text()).toContain(
      'BOOKING.NOTICES.AUTO.PENDING'
    );
    expect(stateText(wrapper, 'rescheduled').text()).toBe(
      'BOOKING.NOTICES.AUTO.FAILED {"reason":"Reconecte a caixa."}'
    );

    // Sem nada "enviando", a consulta para.
    await vi.advanceTimersByTimeAsync(POLL_MS * 3);
    expect(BookingPagesAPI.noticeTemplateRequests).toHaveBeenCalledTimes(1);
    wrapper.unmount();
  });

  it('"Tentar de novo" só no aviso recusado na criação, e reenvia só ele', async () => {
    BookingPagesAPI.noticeTemplateSuggestions.mockImplementation(() =>
      suggestionsReply({
        can_create: true,
        requests: {
          booked: { state: 'failed', reason: 'Sem permissão.' },
          rescheduled: { state: 'pending' },
        },
      })
    );
    BookingPagesAPI.createNoticeTemplates.mockImplementation(() =>
      reply({ queued: true, requests: { rescheduled: { state: 'pending' } } })
    );
    const wrapper = await mountStep();

    expect(
      wrapper.find('[data-template-kind="rescheduled"] [data-retry]').exists()
    ).toBe(false);
    await wrapper
      .find('[data-template-kind="booked"] [data-retry]')
      .trigger('click');
    await flushPromises();

    expect(BookingPagesAPI.createNoticeTemplates).toHaveBeenCalledWith(
      PAGE_ID,
      9,
      ['booked']
    );
  });

  it('quem não pode criar vê o recusado, sem "Tentar de novo"', async () => {
    BookingPagesAPI.noticeTemplateSuggestions.mockImplementation(() =>
      suggestionsReply({
        can_create: false,
        requests: { booked: { state: 'failed', reason: 'Sem permissão.' } },
      })
    );
    const wrapper = await mountStep();

    expect(stateText(wrapper, 'booked').exists()).toBe(true);
    expect(wrapper.find('[data-retry]').exists()).toBe(false);
  });

  it('aprovado: o modelo fica escolhido no aviso vazio e a linha de estado some', async () => {
    const ready = {
      state: 'approved',
      name: 'agendamento_ao_marcar_v1',
      language: 'pt_BR',
    };
    BookingPagesAPI.noticeTemplateSuggestions.mockImplementation(() =>
      suggestionsReply({ can_create: true, requests: { booked: ready } })
    );
    const wrapper = await mountStep();

    const [last] = changes(wrapper).at(-1);
    expect(last.noticeTemplates.booked).toEqual({
      name: 'agendamento_ao_marcar_v1',
      language: 'pt_BR',
    });

    await wrapper.setProps({
      form: form({ noticeTemplates: last.noticeTemplates }),
    });
    expect(stateText(wrapper, 'booked').exists()).toBe(false);
  });

  it('se o pedido de criar falhar, avisa em texto simples', async () => {
    BookingPagesAPI.noticeTemplateSuggestions.mockImplementation(() =>
      suggestionsReply({ can_create: true })
    );
    BookingPagesAPI.createNoticeTemplates.mockImplementation(() =>
      Promise.reject(new Error('500'))
    );
    const wrapper = await mountStep();

    await wrapper.find('[data-create-templates-button]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-create-error]').text()).toBe(
      'BOOKING.NOTICES.AUTO.CREATE_FAILED'
    );
  });
});
