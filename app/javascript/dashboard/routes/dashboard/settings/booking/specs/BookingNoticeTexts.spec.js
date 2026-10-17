import { mount, flushPromises } from '@vue/test-utils';
import BookingPagesAPI from 'dashboard/api/crmBookingPages';
import StepNotices from '../components/steps/StepNotices.vue';
import {
  noticeTextPreview,
  noticeTextProblem,
  noticeTextsPayload,
  toFriendly,
  toKeys,
} from '../bookingNoticeTexts';
import { formToPayload, pageToForm, stepProblem } from '../bookingPageForm';
import { STEP } from '../constants';

// Texto próprio dos avisos (#1354): o passo mostra o texto padrão como ponto
// de partida, a IA só preenche o campo (salvar é da página), "Voltar ao texto
// padrão", a prévia como o cliente vê e os erros de conferência.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values) =>
      values === undefined ? key : `${key} ${JSON.stringify(values)}`,
  }),
}));
vi.mock('dashboard/api/crmBookingPages', () => ({
  default: {
    noticeTextSuggestions: vi.fn(),
    noticeTemplateSuggestions: vi.fn(() => new Promise(() => {})),
    noticeTemplateRequests: vi.fn(),
    createNoticeTemplates: vi.fn(),
  },
}));
vi.mock('dashboard/api/whatsappApiMessageTemplates', () => ({
  default: { get: vi.fn(() => Promise.resolve({ data: { payload: [] } })) },
}));

const DEFAULT_BOOKED =
  'Oi, {{cliente.primeiro_nome}}! Seu horário está marcado para {{horario.data_hora}}.';
const SETUP = {
  defaults: {
    booked: DEFAULT_BOOKED,
    rescheduled:
      'Oi, {{cliente.primeiro_nome}}! Seu horário mudou para {{horario.data_hora}}.',
  },
  fields: [
    { key: 'cliente.primeiro_nome', label: 'Primeiro nome do cliente' },
    { key: 'horario.data_hora', label: 'Dia e hora do horário' },
    {
      key: 'horario.link_gestao',
      label: 'Link para confirmar, mudar ou cancelar',
    },
    { key: 'minha_empresa.nome', label: 'Nome da sua empresa' },
  ],
  samples: {
    'cliente.primeiro_nome': 'Ana',
    'horario.data_hora': '14/10 às 15:00',
    'horario.link_gestao': 'https://app.test/b/AB3K9QXZ',
    'minha_empresa.nome': 'Studio Bela',
  },
  stop_line:
    'Para parar estes avisos: https://app.test/b/AB3K9QXZ?stop_notices=1',
  manage_line: 'Para confirmar, mudar ou cancelar: https://app.test/b/AB3K9QXZ',
  notice_channel: 'whatsapp_cloud',
  max_length: 500,
};
const AI_TEXT =
  'Olá, {{cliente.primeiro_nome}}! A {{minha_empresa.nome}} te espera em {{horario.data_hora}}. Mude em {{horario.link_gestao}}. Até lá!';
const WAHA = { id: 3, name: 'WAHA', provider: 'waha', needs_templates: false };

const form = (extra = {}) => ({
  noticeInboxId: 3,
  noticePreset: 'minimal',
  noticeTemplates: {},
  noticeTexts: {},
  cancelUntilMinutes: 120,
  ...extra,
});

const mountStep = async (formValue = form(), textSetup = SETUP) => {
  const wrapper = mount(StepNotices, {
    props: {
      form: formValue,
      inboxOptions: [WAHA],
      pageId: 7,
      textSetup,
    },
    global: {
      provide: {
        store: {
          getters: { 'inboxes/getConversationWhatsAppTemplates': () => [] },
        },
      },
    },
  });
  await flushPromises();
  return wrapper;
};

const lastChange = wrapper => (wrapper.emitted('change') || []).at(-1)?.[0];
const card = (wrapper, kind) => wrapper.find(`[data-notice-text="${kind}"]`);

describe('StepNotices — texto de cada aviso (#1354)', () => {
  // Corpo em bloco: se o beforeEach devolve a função (o mock), o vitest a chama
  // como limpeza depois do teste.
  beforeEach(() => {
    BookingPagesAPI.noticeTextSuggestions.mockReset();
  });

  // #1562: a prévia mostra o caso de texto, que sempre vale (o botão depende da
  // janela aberta, que a tela não sabe); a nota explica o caso com botão.
  it('mostra um cartão por aviso do jogo, com o texto padrão pelos rótulos e a prévia com a linha de parar', async () => {
    const wrapper = await mountStep();

    expect(
      wrapper
        .findAll('[data-notice-text]')
        .map(item => item.attributes('data-notice-text'))
    ).toEqual(['booked', 'rescheduled']);
    const booked = card(wrapper, 'booked');
    expect(booked.find('[data-text-input]').element.value).toBe(
      'Oi, [Primeiro nome do cliente]! Seu horário está marcado para [Dia e hora do horário].'
    );
    expect(booked.find('[data-text-preview]').text()).toBe(
      'Oi, Ana! Seu horário está marcado para 14/10 às 15:00.\n\nPara confirmar, mudar ou cancelar: https://app.test/b/AB3K9QXZ\n\nPara parar estes avisos: https://app.test/b/AB3K9QXZ?stop_notices=1'
    );
    // #1517: sem o link no texto, a prévia mostra a linha que o sistema põe e avisa do botão.
    expect(booked.find('[data-button-note]').text()).toBe(
      'BOOKING.NOTICES.TEXTS.BUTTON_NOTE'
    );
    expect(booked.find('[data-text-origin]').text()).toBe(
      'BOOKING.NOTICES.TEXTS.DEFAULT'
    );
    expect(
      booked.find('[data-reset-default]').attributes('disabled')
    ).toBeDefined();
  });

  it('"Escrever com IA" mostra as opções e escolher uma só preenche o campo (nada é salvo)', async () => {
    BookingPagesAPI.noticeTextSuggestions.mockResolvedValue({
      data: { payload: { options: [{ text: AI_TEXT, keys: [] }] } },
    });
    const wrapper = await mountStep();

    await card(wrapper, 'booked').find('[data-write-ai]').trigger('click');
    await flushPromises();

    expect(BookingPagesAPI.noticeTextSuggestions).toHaveBeenCalledWith(
      7,
      'booked',
      'simpatico'
    );
    const option = card(wrapper, 'booked').find('[data-ai-option]');
    expect(option.text()).toContain(
      'Olá, Ana! A Studio Bela te espera em 14/10 às 15:00.'
    );

    await option.find('[data-use-option]').trigger('click');
    expect(lastChange(wrapper)).toEqual({ noticeTexts: { booked: AI_TEXT } });
    expect(
      card(wrapper, 'booked').find('[data-text-input]').element.value
    ).toContain('A [Nome da sua empresa] te espera');
  });

  // #1517: a nota do botão só vale para o WhatsApp oficial e para texto sem o
  // link; outras caixas (e sem caixa) só levam a linha do link.
  // #1562: fora do oficial a prévia é a mesma, com a linha de parar no fim.
  it('a nota do botão some fora do WhatsApp oficial e com o link no texto', async () => {
    const stopLine = `\n\n${SETUP.stop_line}`;
    const waha = await mountStep(form(), { ...SETUP, notice_channel: 'waha' });
    expect(card(waha, 'booked').find('[data-button-note]').exists()).toBe(
      false
    );
    expect(card(waha, 'booked').find('[data-text-preview]').text()).toBe(
      `Oi, Ana! Seu horário está marcado para 14/10 às 15:00.\n\nPara confirmar, mudar ou cancelar: https://app.test/b/AB3K9QXZ${stopLine}`
    );
    const none = await mountStep(form(), { ...SETUP, notice_channel: null });
    expect(card(none, 'booked').find('[data-button-note]').exists()).toBe(
      false
    );
    const withLink = await mountStep(
      form({ noticeTexts: { booked: AI_TEXT } })
    );
    expect(card(withLink, 'booked').find('[data-button-note]').exists()).toBe(
      false
    );
    const withLinkPreview = card(withLink, 'booked')
      .find('[data-text-preview]')
      .text();
    expect(withLinkPreview.endsWith(SETUP.stop_line)).toBe(true);
  });

  // #1517: a opção da IA sem o link mostra a linha do link que o sistema põe.
  it('a prévia da opção da IA sem o link mostra a linha do link', async () => {
    BookingPagesAPI.noticeTextSuggestions.mockResolvedValue({
      data: {
        payload: {
          options: [{ text: 'Oi! Até {{horario.data_hora}}.', keys: [] }],
        },
      },
    });
    const wrapper = await mountStep();

    await card(wrapper, 'booked').find('[data-write-ai]').trigger('click');
    await flushPromises();

    expect(card(wrapper, 'booked').find('[data-ai-option] p').text()).toBe(
      'Oi! Até 14/10 às 15:00.\n\nPara confirmar, mudar ou cancelar: https://app.test/b/AB3K9QXZ'
    );
  });

  it('o tom escolhido nos cartões vai para a IA', async () => {
    BookingPagesAPI.noticeTextSuggestions.mockResolvedValue({
      data: { payload: { options: [] } },
    });
    const wrapper = await mountStep();

    await wrapper
      .find('[data-notice-tone] [data-choice="formal"] input')
      .setValue();
    await card(wrapper, 'booked').find('[data-write-ai]').trigger('click');
    await flushPromises();

    expect(BookingPagesAPI.noticeTextSuggestions).toHaveBeenCalledWith(
      7,
      'booked',
      'formal'
    );
  });

  it('erro da IA mostra a frase simples e não muda o texto', async () => {
    BookingPagesAPI.noticeTextSuggestions.mockImplementation(() =>
      Promise.reject(
        Object.assign(new Error('ai'), {
          response: { data: { message: 'Não conseguimos escrever agora.' } },
        })
      )
    );
    const wrapper = await mountStep();

    await card(wrapper, 'booked').find('[data-write-ai]').trigger('click');
    await flushPromises();

    expect(card(wrapper, 'booked').find('[data-ai-error]').text()).toBe(
      'Não conseguimos escrever agora.'
    );
    const textChanges = (wrapper.emitted('change') || []).filter(
      ([change]) => 'noticeTexts' in change
    );
    expect(textChanges).toEqual([]);
  });

  it('editar troca rótulos por chaves; texto sem dia e hora mostra o erro', async () => {
    const wrapper = await mountStep();

    await card(wrapper, 'booked')
      .find('[data-text-input]')
      .setValue('Oi! Mude em [Link para confirmar, mudar ou cancelar].');
    const change = lastChange(wrapper);
    expect(change).toEqual({
      noticeTexts: { booked: 'Oi! Mude em {{horario.link_gestao}}.' },
    });

    await wrapper.setProps({ form: form({ noticeTexts: change.noticeTexts }) });
    expect(card(wrapper, 'booked').find('[data-text-error]').text()).toContain(
      'BOOKING.NOTICES.TEXTS.ERRORS.MISSING_WHEN'
    );
    expect(
      card(wrapper, 'booked')
        .find('[data-text-input]')
        .attributes('aria-invalid')
    ).toBe('true');
  });

  it('"Voltar ao texto padrão" tira o texto próprio', async () => {
    const wrapper = await mountStep(form({ noticeTexts: { booked: AI_TEXT } }));

    expect(card(wrapper, 'booked').find('[data-text-origin]').text()).toBe(
      'BOOKING.NOTICES.TEXTS.CUSTOM'
    );
    await card(wrapper, 'booked').find('[data-reset-default]').trigger('click');

    expect(lastChange(wrapper)).toEqual({ noticeTexts: {} });
    expect(
      card(wrapper, 'booked').find('[data-text-input]').element.value
    ).toContain('Seu horário está marcado');
  });

  it('põe o campo do botão onde está o cursor', async () => {
    const wrapper = await mountStep(form({ noticeTexts: { booked: AI_TEXT } }));
    const input = card(wrapper, 'booked').find('[data-text-input]');
    input.element.setSelectionRange(0, 0);

    await card(wrapper, 'booked')
      .find('[data-insert-field="minha_empresa.nome"]')
      .trigger('click');

    expect(lastChange(wrapper).noticeTexts.booked).toBe(
      `{{minha_empresa.nome}}${AI_TEXT}`
    );
  });
});

describe('bookingNoticeTexts (#1354)', () => {
  it('converte chaves em rótulos e de volta, sem perder colchete que não é campo', () => {
    const friendly = toFriendly(AI_TEXT, SETUP.fields);
    expect(toKeys(friendly, SETUP.fields)).toBe(AI_TEXT);
    expect(
      toKeys('Traga [documento] em [Dia e hora do horário]', SETUP.fields)
    ).toBe('Traga [documento] em {{horario.data_hora}}');
  });

  it('confere como o servidor: dia/hora obrigatório (o link não, #1517), só os campos do aviso, tamanho e chave malformada', () => {
    expect(noticeTextProblem(AI_TEXT)).toBeNull();
    expect(noticeTextProblem('')).toBe('BLANK');
    expect(noticeTextProblem('Dia {{horario.data_hora}}')).toBeNull();
    expect(noticeTextProblem('Link {{horario.link_gestao}}')).toBe(
      'MISSING_WHEN'
    );
    expect(noticeTextProblem(`${AI_TEXT} {{cliente.cpf}}`)).toBe(
      'UNKNOWN_FIELD'
    );
    expect(noticeTextProblem(`${AI_TEXT} {{horario`)).toBe('MALFORMED');
    expect(noticeTextProblem(`${AI_TEXT} {{ horario.data_hora }}`)).toBe(
      'MALFORMED'
    );
    expect(noticeTextProblem(`${AI_TEXT} {{horario.data_hora}}}`)).toBe(
      'MALFORMED'
    );
    expect(noticeTextProblem(`${AI_TEXT} [Dia e hora]`)).toBe('BRACKET');
    expect(noticeTextProblem(`${AI_TEXT}${'a'.repeat(500)}`)).toBe('TOO_LONG');
  });

  it('a prévia troca as chaves pelos exemplos e põe a linha de parar no fim', () => {
    expect(
      noticeTextPreview(
        'Oi, {{cliente.primeiro_nome}}!',
        SETUP.samples,
        'Parar: x'
      )
    ).toBe('Oi, Ana!\n\nParar: x');
  });

  it('sem o link no texto, a prévia põe a linha do link antes da de parar; com o link, fica como está (#1517)', () => {
    expect(noticeTextPreview('Oi!', SETUP.samples, 'Parar: x', 'Link: y')).toBe(
      'Oi!\n\nLink: y\n\nParar: x'
    );
    expect(
      noticeTextPreview(
        'Mude em {{horario.link_gestao}}',
        SETUP.samples,
        'Parar: x',
        'Link: y'
      )
    ).toBe('Mude em https://app.test/b/AB3K9QXZ\n\nParar: x');
  });

  it('o formulário lê e manda só os textos escritos, e o passo não avança com texto inválido', () => {
    const loaded = pageToForm({ notice_texts: { booked: AI_TEXT } });
    expect(loaded.noticeTexts).toEqual({ booked: AI_TEXT });
    expect(
      noticeTextsPayload(
        {
          noticeTexts: {
            booked: AI_TEXT,
            day_before: ' ',
            hour_before: AI_TEXT,
          },
        },
        ['booked', 'day_before']
      )
    ).toEqual({ booked: AI_TEXT });

    const ready = {
      ...pageToForm({ notice_texts: { booked: AI_TEXT } }),
      noticeInboxId: 3,
    };
    expect(formToPayload(ready).notice_texts).toEqual({ booked: AI_TEXT });
    expect(stepProblem(STEP.AVISOS, ready)).toBeNull();
    expect(
      stepProblem(STEP.AVISOS, {
        ...ready,
        noticeTexts: { booked: 'sem campos' },
      })
    ).toBe('NOTICE_TEXTS');
  });
});
