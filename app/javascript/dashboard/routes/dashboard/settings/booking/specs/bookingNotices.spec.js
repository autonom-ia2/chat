import { mount, flushPromises } from '@vue/test-utils';
import BookingPagesAPI from 'dashboard/api/crmBookingPages';
import WhatsappApiMessageTemplatesAPI from 'dashboard/api/whatsappApiMessageTemplates';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import StepNotices from '../components/steps/StepNotices.vue';
import BookingNoticesSummary from '../components/BookingNoticesSummary.vue';
import BookingTestInvite from '../components/BookingTestInvite.vue';
import { pageToForm } from '../bookingPageForm';
import {
  kindsWithoutTemplate,
  templateKinds,
  templatePreview,
  testInviteProblem,
  usableTemplates,
} from '../bookingNotices';

// Avisos no WhatsApp da página de agendamento (#1192, F2-A): passo de avisos,
// resumo na prévia e "Testar no meu WhatsApp".
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values) =>
      values === undefined ? key : `${key} ${JSON.stringify(values)}`,
  }),
}));
vi.mock('dashboard/api/crmBookingPages', () => ({
  default: { testInvite: vi.fn() },
}));
vi.mock('dashboard/api/whatsappApiMessageTemplates', () => ({
  default: { get: vi.fn() },
}));

const body = text => ({ type: 'BODY', text });
const template = (name, extra = {}) => ({
  name,
  language: 'pt_BR',
  status: 'APPROVED',
  category: 'UTILITY',
  components: [body('Oi {{1}}, seu horário é {{2}}. Confirme: {{3}}')],
  ...extra,
});

const OFFICIAL = {
  id: 12,
  name: 'WhatsApp da loja',
  provider: 'whatsapp_cloud',
  needs_templates: true,
};
const WAHA = {
  id: 13,
  name: 'Celular',
  provider: 'waha',
  needs_templates: false,
};
const API = {
  id: 14,
  name: 'WhatsApp de campanhas',
  provider: 'api',
  needs_templates: false,
};

const templatesGetter = vi.fn(() => []);
const mountGlobal = {
  provide: {
    store: {
      getters: { 'inboxes/getFilteredWhatsAppTemplates': templatesGetter },
    },
  },
};

const form = (extra = {}) => ({
  ...pageToForm({ title: 'Conversa' }),
  ...extra,
});

const mountStep = (formExtra = {}, inboxOptions = [OFFICIAL, WAHA]) =>
  mount(StepNotices, {
    props: { form: form(formExtra), inboxOptions },
    global: mountGlobal,
  });

const lastChange = wrapper => wrapper.emitted('change').at(-1)[0];

describe('bookingNotices', () => {
  it('cada jogo pede modelo para os avisos dele e para o de horário mudou', () => {
    expect(templateKinds('standard')).toEqual([
      'booked',
      'day_before',
      'hour_before',
      'rescheduled',
    ]);
    expect(templateKinds('minimal')).toEqual(['booked', 'rescheduled']);
    expect(templateKinds('desconhecido')).toEqual(templateKinds('standard'));
  });

  it('só serve modelo aprovado, sem mídia no topo e com o link {{3}}', () => {
    const list = usableTemplates([
      template('com_link'),
      template('sem_link', { components: [body('Oi {{1}}')] }),
      template('pendente', { status: 'PENDING' }),
      template('com_imagem', {
        components: [{ type: 'HEADER', format: 'IMAGE' }, body('Veja {{3}}')],
      }),
    ]);
    expect(list.map(item => item.name)).toEqual(['com_link']);
    expect(usableTemplates(undefined)).toEqual([]);
  });

  it('recusa o que o aviso não preenche: variável além do {{3}}, topo com variável, botão com link variável', () => {
    const list = usableTemplates([
      template('ok', {
        components: [
          { type: 'HEADER', format: 'TEXT', text: 'Seu horário' },
          body('Oi {{1}}, {{2}}: {{3}}'),
          { type: 'BUTTONS', buttons: [{ type: 'URL', url: 'https://x.co' }] },
        ],
      }),
      template('quatro', { components: [body('Oi {{1}}, {{3}} e {{4}}')] }),
      template('topo', {
        components: [
          { type: 'HEADER', format: 'TEXT', text: 'Oi {{1}}' },
          body('Veja {{3}}'),
        ],
      }),
      template('botao', {
        components: [
          body('Veja {{3}}'),
          {
            type: 'BUTTONS',
            buttons: [{ type: 'URL', url: 'https://x.co/{{1}}' }],
          },
        ],
      }),
    ]);
    expect(list.map(item => item.name)).toEqual(['ok']);
  });

  it('a opção mostra a mensagem como chega, sem o nome técnico', () => {
    const samples = { name: 'Ana', when: '14/10 às 15:00', link: '(link)' };
    expect(templatePreview(template('aviso_v2'), samples)).toBe(
      'Oi Ana, seu horário é 14/10 às 15:00. Confirme: (link)'
    );
    const long = template('longo', {
      components: [body(`${'palavra '.repeat(30)}{{3}}`)],
    });
    expect(templatePreview(long, samples).length).toBeLessThanOrEqual(90);
    expect(templatePreview(long, samples).endsWith('…')).toBe(true);
  });

  it('aponta os avisos sem mensagem pronta, só onde ela faz falta', () => {
    const chosen = form({
      noticePreset: 'light',
      noticeTemplates: { booked: { name: 'a', language: 'pt_BR' } },
    });
    expect(kindsWithoutTemplate(chosen, OFFICIAL)).toEqual([
      'hour_before',
      'rescheduled',
    ]);
    expect(kindsWithoutTemplate(chosen, API)).toEqual([
      'hour_before',
      'rescheduled',
    ]);
    expect(kindsWithoutTemplate(chosen, WAHA)).toEqual([]);
  });

  it('recusa do teste vira um aviso leigo', () => {
    expect(testInviteProblem({ error: 'invalid_phone' })).toBe('INVALID_PHONE');
    expect(testInviteProblem({ error: 'page_not_published' })).toBe(
      'NOT_PUBLISHED'
    );
    expect(testInviteProblem({ error: 'notice_inbox_missing' })).toBe(
      'NO_INBOX'
    );
    expect(
      testInviteProblem({ error: 'cannot_send', reason: 'template_required' })
    ).toBe('OUTSIDE_WINDOW');
    expect(
      testInviteProblem({ error: 'cannot_send', reason: 'waha_outside_window' })
    ).toBe('OUTSIDE_WINDOW');
    expect(
      testInviteProblem({ error: 'cannot_send', reason: 'number_cap' })
    ).toBe('NUMBER_CAP');
    expect(
      testInviteProblem({ error: 'cannot_send', reason: 'no_phone' })
    ).toBe('CANNOT_SEND');
    expect(testInviteProblem({ error: 'notice_inbox_forbidden' })).toBe(
      'FORBIDDEN'
    );
    expect(
      testInviteProblem({
        error: 'notice_inbox_forbidden',
        reason: 'conversation_forbidden',
      })
    ).toBe('CONVERSATION_FORBIDDEN');
    expect(testInviteProblem({ error: 'cannot_send', reason: 'stopped' })).toBe(
      'STOPPED'
    );
    expect(testInviteProblem(undefined)).toBe('FAILED');
  });
});

describe('StepNotices', () => {
  beforeEach(() => {
    templatesGetter.mockReset();
    templatesGetter.mockReturnValue([]);
  });

  it('sem número escolhido mostra "Sem avisos" e só o prazo para mudar', () => {
    const wrapper = mountStep();
    const [inbox] = wrapper.findAllComponents(ChoiceSelect);
    expect(inbox.props('options')).toEqual([
      { value: '', label: 'BOOKING.NOTICES.INBOX_NONE' },
      { value: 12, label: 'WhatsApp da loja' },
      { value: 13, label: 'Celular' },
    ]);
    expect(inbox.props('modelValue')).toBe('');
    expect(wrapper.find('[data-notice-preset]').exists()).toBe(false);
    const deadlines = wrapper
      .findAll('[data-cancel-until] [data-choice]')
      .map(item => item.attributes('data-choice'));
    expect(deadlines).toEqual(['60', '120', '1440']);
    expect(wrapper.find('[data-choice="120"] input').element.checked).toBe(
      true
    );
  });

  it('nenhum WhatsApp conectado: diz isso em vez de lista vazia', () => {
    const wrapper = mountStep({}, []);
    expect(wrapper.find('[data-no-inboxes]').text()).toBe(
      'BOOKING.NOTICES.NO_INBOXES'
    );
  });

  it('escolher o número limpa os modelos do número anterior', async () => {
    const wrapper = mountStep({
      noticeInboxId: 13,
      noticeTemplates: { booked: { id: 5 } },
    });
    await wrapper
      .findAllComponents(ChoiceSelect)[0]
      .vm.$emit('update:modelValue', 12);
    expect(lastChange(wrapper)).toEqual({
      noticeInboxId: 12,
      noticeTemplates: {},
    });
    await wrapper
      .findAllComponents(ChoiceSelect)[0]
      .vm.$emit('update:modelValue', '');
    expect(lastChange(wrapper)).toEqual({
      noticeInboxId: null,
      noticeTemplates: {},
    });
  });

  it('três jogos prontos em cartões de rádio, o padrão marcado', async () => {
    const wrapper = mountStep({ noticeInboxId: 13 });
    const presets = wrapper.findAll('[data-notice-preset] [data-choice]');
    expect(presets.map(item => item.attributes('data-choice'))).toEqual([
      'standard',
      'light',
      'minimal',
    ]);
    expect(presets[0].text()).toContain('BOOKING.NOTICES.RECOMMENDED');
    const radios = wrapper.findAll('[data-notice-preset] input[type="radio"]');
    expect(radios[0].element.checked).toBe(true);
    // Mesmo grupo: setas do teclado trocam a escolha.
    expect(new Set(radios.map(radio => radio.attributes('name'))).size).toBe(1);
    await radios[1].setValue(true);
    expect(lastChange(wrapper)).toEqual({ noticePreset: 'light' });
    expect(wrapper.find('[data-channel-hint]').text()).toBe(
      'BOOKING.NOTICES.CHANNEL.WAHA'
    );
    expect(wrapper.find('[data-notice-templates]').exists()).toBe(false);
  });

  it('WhatsApp oficial: um modelo aprovado por aviso, da lista da caixa', async () => {
    templatesGetter.mockReturnValue([
      template('aviso_marcado'),
      template('sem_link', { components: [body('Oi')] }),
    ]);
    const wrapper = mountStep({ noticeInboxId: 12, noticePreset: 'light' });
    expect(templatesGetter).toHaveBeenCalledWith(12);
    const kinds = wrapper
      .findAll('[data-template-kind]')
      .map(item => item.attributes('data-template-kind'));
    expect(kinds).toEqual(['booked', 'hour_before', 'rescheduled']);
    const booked = wrapper
      .find('[data-template-kind="booked"]')
      .findComponent(ChoiceSelect);
    expect(booked.props('options').map(option => option.value)).toEqual([
      '',
      'aviso_marcado · pt_BR',
    ]);
    await booked.vm.$emit('update:modelValue', 'aviso_marcado · pt_BR');
    expect(lastChange(wrapper)).toEqual({
      noticeTemplates: {
        booked: { name: 'aviso_marcado', language: 'pt_BR' },
      },
    });
  });

  it('lista as mensagens pelo texto, e diz quais avisos ficam sem mensagem', () => {
    templatesGetter.mockReturnValue([template('aviso_marcado')]);
    const wrapper = mountStep({
      noticeInboxId: 12,
      noticePreset: 'minimal',
      noticeTemplates: { booked: { name: 'aviso_marcado', language: 'pt_BR' } },
    });
    const booked = wrapper
      .find('[data-template-kind="booked"]')
      .findComponent(ChoiceSelect);
    const label = booked.props('options')[1].label;
    expect(label).toContain('BOOKING.NOTICES.SAMPLE_NAME');
    expect(label).not.toContain('aviso_marcado');
    expect(wrapper.find('[data-missing-templates]').text()).toContain(
      'BOOKING.NOTICES.MISSING_TEMPLATES'
    );
    expect(wrapper.find('[data-missing-templates]').text()).toContain(
      'BOOKING.NOTICES.KINDS.RESCHEDULED'
    );
  });

  it('canal API de campanhas: escolhe a mensagem pronta do canal e grava o id', async () => {
    WhatsappApiMessageTemplatesAPI.get.mockResolvedValue({
      data: { payload: [{ id: 5, name: 'Lembrete', body: 'Oi!' }] },
    });
    const wrapper = mountStep({ noticeInboxId: 14 }, [OFFICIAL, API]);
    await flushPromises();
    expect(WhatsappApiMessageTemplatesAPI.get).toHaveBeenCalledWith(14);
    const booked = wrapper
      .find('[data-template-kind="booked"]')
      .findComponent(ChoiceSelect);
    expect(booked.props('options')).toEqual([
      { value: '', label: 'BOOKING.NOTICES.TEMPLATE_NONE' },
      { value: 'id:5', label: 'Lembrete' },
    ]);
    await booked.vm.$emit('update:modelValue', 'id:5');
    expect(lastChange(wrapper)).toEqual({
      noticeTemplates: { booked: { id: 5 } },
    });
  });

  it('canal API sem acesso às mensagens: diz que não deu para ver', async () => {
    WhatsappApiMessageTemplatesAPI.get.mockRejectedValue(new Error('403'));
    const wrapper = mountStep({ noticeInboxId: 14 }, [API]);
    await flushPromises();
    expect(wrapper.find('[data-no-templates]').text()).toBe(
      'BOOKING.NOTICES.API_TEMPLATES_FAILED'
    );
  });

  it('voltar ao número salvo devolve as mensagens que já estavam escolhidas', async () => {
    const saved = { booked: { name: 'aviso_marcado', language: 'pt_BR' } };
    const wrapper = mount(StepNotices, {
      props: {
        form: form({ noticeInboxId: null }),
        inboxOptions: [OFFICIAL, WAHA],
        savedInboxId: 12,
        savedTemplates: saved,
      },
      global: mountGlobal,
    });
    await wrapper
      .findAllComponents(ChoiceSelect)[0]
      .vm.$emit('update:modelValue', 12);
    expect(lastChange(wrapper)).toEqual({
      noticeInboxId: 12,
      noticeTemplates: saved,
    });
  });

  it('número salvo que a pessoa não enxerga: sem a frase de "nenhum WhatsApp"', () => {
    const wrapper = mountStep({ noticeInboxId: 99 }, []);
    expect(wrapper.find('[data-no-inboxes]').exists()).toBe(false);
  });

  it('sem modelo aprovado com link: explica o que fazer', () => {
    const wrapper = mountStep({ noticeInboxId: 12 });
    expect(wrapper.find('[data-no-templates]').text()).toBe(
      'BOOKING.NOTICES.TEMPLATES_EMPTY'
    );
  });

  it('número escolhido por outra pessoa continua na lista', () => {
    const wrapper = mountStep({ noticeInboxId: 99 });
    const options = wrapper.findAllComponents(ChoiceSelect)[0].props('options');
    expect(options.at(-1)).toEqual({
      value: 99,
      label: 'BOOKING.NOTICES.INBOX_CURRENT',
    });
  });

  it('prazo para mudar sai do cartão escolhido', async () => {
    const wrapper = mountStep();
    await wrapper.find('[data-choice="1440"] input').setValue(true);
    expect(lastChange(wrapper)).toEqual({ cancelUntilMinutes: 1440 });
  });
});

describe('BookingNoticesSummary', () => {
  it('sem avisos diz isso numa frase', () => {
    const wrapper = mount(BookingNoticesSummary, {
      props: { form: form(), canManage: true },
    });
    expect(wrapper.text()).toContain('BOOKING.PREVIEW.NOTICES_OFF');
    expect(wrapper.text()).toContain('BOOKING.PREVIEW.CANCEL_UNTIL');
  });

  it('com avisos diz quando e por qual número; Alterar só para quem muda', async () => {
    const wrapper = mount(BookingNoticesSummary, {
      props: {
        form: form({ noticeInboxId: 12, noticePreset: 'minimal' }),
        inboxOptions: [OFFICIAL],
        canManage: true,
      },
    });
    expect(wrapper.text()).toContain('BOOKING.PREVIEW.NOTICES_ON');
    expect(wrapper.text()).toContain('"inbox":"WhatsApp da loja"');
    expect(wrapper.text()).toContain('BOOKING.NOTICES.PRESETS.MINIMAL.SUMMARY');
    await wrapper.find('[data-notices-alter]').trigger('click');
    expect(wrapper.emitted('alter')).toHaveLength(1);

    expect(wrapper.find('[data-notices-window]').text()).toContain(
      'BOOKING.NOTICES.MISSING_TEMPLATES'
    );

    const waha = mount(BookingNoticesSummary, {
      props: { form: form({ noticeInboxId: 13 }), inboxOptions: [WAHA] },
    });
    expect(waha.find('[data-notices-window]').text()).toBe(
      'BOOKING.PREVIEW.NOTICES_WINDOW_ONLY'
    );

    const readOnly = mount(BookingNoticesSummary, {
      props: { form: form({ noticeInboxId: 12 }), inboxOptions: [OFFICIAL] },
    });
    expect(readOnly.find('[data-notices-alter]').exists()).toBe(false);
  });
});

describe('BookingTestInvite', () => {
  beforeEach(() => {
    BookingPagesAPI.testInvite.mockReset();
  });

  const openForm = async () => {
    const wrapper = mount(BookingTestInvite, {
      props: { pageId: 7 },
      attachTo: document.body,
    });
    await wrapper.find('[data-test-start]').trigger('click');
    return wrapper;
  };

  it('pede o número, foca o campo e manda o teste', async () => {
    BookingPagesAPI.testInvite.mockResolvedValue({ data: { sent: true } });
    const wrapper = await openForm();
    expect(document.activeElement).toBe(
      wrapper.find('[data-test-phone]').element
    );
    await wrapper.find('[data-test-phone]').setValue(' +55 11 98888-0000 ');
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(BookingPagesAPI.testInvite).toHaveBeenCalledWith(
      7,
      '+55 11 98888-0000'
    );
    const result = wrapper.find('[data-test-result="SENT"]');
    expect(result.attributes('role')).toBe('status');
    wrapper.unmount();
  });

  it('número vazio não chama o servidor', async () => {
    const wrapper = await openForm();
    await wrapper.find('form').trigger('submit');
    expect(BookingPagesAPI.testInvite).not.toHaveBeenCalled();
    expect(wrapper.find('[data-test-phone]').attributes('aria-invalid')).toBe(
      'true'
    );
    wrapper.unmount();
  });

  it('fora da janela de 24 h diz para mandar um "oi" antes', async () => {
    BookingPagesAPI.testInvite.mockRejectedValue({
      response: {
        status: 422,
        data: { error: 'cannot_send', reason: 'waha_outside_window' },
      },
    });
    const wrapper = await openForm();
    await wrapper.find('[data-test-phone]').setValue('11988880000');
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    const alert = wrapper.find('[data-test-result="OUTSIDE_WINDOW"]');
    expect(alert.attributes('role')).toBe('alert');
    expect(alert.text()).toBe('BOOKING.NOTICES.TEST.ERRORS.OUTSIDE_WINDOW');
    wrapper.unmount();
  });
});
