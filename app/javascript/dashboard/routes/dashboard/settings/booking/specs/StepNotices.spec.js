import { config, mount, flushPromises } from '@vue/test-utils';
import BookingPagesAPI from 'dashboard/api/crmBookingPages';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import StepNotices from '../components/steps/StepNotices.vue';

// Modelos de aviso do WhatsApp oficial (#1272): a sugestão da IA entra só nos
// avisos vazios e mostra "Sugerido". O "Criar os modelos na Meta" (v1) saiu em
// #1612: no Cloud, a tela mostra o que vale agora (BookingNoticeAutorizacao).
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values) =>
      values === undefined ? key : `${key} ${JSON.stringify(values)}`,
  }),
}));
vi.mock('dashboard/api/crmBookingPages', () => ({
  default: {
    noticeTemplateSuggestions: vi.fn(),
  },
}));
vi.mock('dashboard/api/whatsappApiMessageTemplates', () => ({
  default: { get: vi.fn(() => Promise.resolve({ data: { payload: [] } })) },
}));
// O bloco da autorização tem spec própria (BookingNoticeAutorizacao.spec.js).
vi.mock('../components/BookingNoticeAutorizacao.vue', async () => {
  const { h } = await import('vue');
  return {
    default: { render: () => h('div', { 'data-notice-autorizacao': '' }) },
  };
});

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
  reply({ suggestions: {}, ai_failed: false, ...payload });

const mountStep = async (formValue = form(), inboxOptions = [OFFICIAL]) => {
  const wrapper = mount(StepNotices, {
    props: { form: formValue, inboxOptions, pageId: PAGE_ID },
  });
  await flushPromises();
  return wrapper;
};

const changes = wrapper => wrapper.emitted('change') || [];

describe('StepNotices — modelos sugeridos (#1272), sem criar na Meta (#1612)', () => {
  beforeEach(() => {
    BookingPagesAPI.noticeTemplateSuggestions.mockReset();
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

  it('não tem botão de criar na Meta nem estado de pedido, nem com resposta antiga do servidor', async () => {
    BookingPagesAPI.noticeTemplateSuggestions.mockImplementation(() =>
      suggestionsReply({
        can_create: true,
        requests: { booked: { state: 'failed', reason: 'Sem permissão.' } },
      })
    );
    const wrapper = await mountStep();

    expect(wrapper.find('[data-create-templates]').exists()).toBe(false);
    expect(wrapper.find('[data-create-templates-button]').exists()).toBe(false);
    expect(wrapper.find('[data-request-state]').exists()).toBe(false);
    expect(wrapper.find('[data-retry]').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('BOOKING.NOTICES.AUTO.CREATE');
    expect(changes(wrapper)).toEqual([]);
  });

  it('no WhatsApp oficial Cloud mostra o bloco da autorização; no 360dialog, não', async () => {
    BookingPagesAPI.noticeTemplateSuggestions.mockImplementation(() =>
      suggestionsReply()
    );
    const cloud = await mountStep();
    expect(cloud.find('[data-notice-autorizacao]').exists()).toBe(true);

    const dialog = { ...OFFICIAL, provider: '360dialog' };
    const other = await mountStep(form(), [dialog]);
    expect(other.find('[data-notice-templates]').exists()).toBe(true);
    expect(other.find('[data-notice-autorizacao]').exists()).toBe(false);
  });
});
