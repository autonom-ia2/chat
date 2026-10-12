import { config, mount, flushPromises } from '@vue/test-utils';
import BookingPagesAPI from 'dashboard/api/crmBookingPages';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import BookingWizard from '../components/BookingWizard.vue';

// Assistente de sete passos (#1187, J3; avisos no WhatsApp #1192): cada passo,
// voltar sem perder, Meet/Teams só com caixa conectada e publicação com
// pendências.
// `locale` e `mergeLocaleMessage`: a prévia monta as telas da página pública (#1289).
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    locale: { value: 'pt_BR' },
    mergeLocaleMessage: () => {},
    t: (key, values) =>
      values === undefined ? key : `${key} ${JSON.stringify(values)}`,
  }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/crmBookingPages', () => ({
  default: {
    show: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    people: vi.fn(),
    updatePeople: vi.fn(),
    publish: vi.fn(),
    uploadImage: vi.fn(),
    removeLogoDark: vi.fn(),
    applyIdentity: vi.fn(),
    saveIdentity: vi.fn(),
    testInvite: vi.fn(),
  },
}));

// Modelos aprovados da caixa vêm do store de caixas (inboxes/getFilteredWhatsAppTemplates).
const templatesGetter = vi.fn(() => []);
// O painel relê o usuário (validityCheck) quando a foto vira a do perfil (#1298).
const storeDispatch = vi.fn();
config.global.provide = {
  ...config.global.provide,
  store: {
    getters: { 'inboxes/getFilteredWhatsAppTemplates': templatesGetter },
    dispatch: storeDispatch,
  },
};
vi.mock('dashboard/api/crmKanban', () => ({
  default: { getPipelines: vi.fn(), getStages: vi.fn() },
}));

const fullPage = (extra = {}) => ({
  id: 7,
  title: 'Conversa de vendas',
  enabled: false,
  public_url: 'https://chat.exemplo.com/book/abc',
  duration_minutes: 30,
  slot_durations: [],
  locations: [{ type: 'whatsapp_video' }],
  calendar_inbox_id: null,
  working_hours: { start_hour: 9, end_hour: 17, weekdays: [1, 2, 3, 4, 5] },
  min_notice_minutes: 120,
  buffer_minutes: 10,
  brand: {},
  people: [{ id: 1, name: 'Maria' }],
  default_pipeline_id: 3,
  default_stage_id: 30,
  calendar_options: [],
  logo_url: null,
  photo_url: null,
  ...extra,
});

const reply = payload => Promise.resolve({ data: { payload } });

const currentStep = wrapper =>
  wrapper.find('[aria-current="step"]').attributes('data-step');

const primary = wrapper => wrapper.find('[data-primary]');

const continueStep = async wrapper => {
  await primary(wrapper).trigger('click');
  await flushPromises();
};

const mountWizard = async (pageId = 7, page = fullPage()) => {
  BookingPagesAPI.show.mockImplementation(() => reply(page));
  const wrapper = mount(BookingWizard, { props: { pageId } });
  await flushPromises();
  return wrapper;
};

// Abre uma página existente e avança até o passo pedido (2 a 7).
const openAtStep = async (step, page = fullPage()) => {
  // Como o backend: toda resposta traz a página inteira, com as caixas de agenda.
  BookingPagesAPI.update.mockImplementation((_id, body) =>
    reply({ ...page, title: body.title ?? page.title })
  );
  const wrapper = await mountWizard(7, page);
  for (let index = 2; index < step; index += 1) {
    // eslint-disable-next-line no-await-in-loop
    await continueStep(wrapper);
  }
  return wrapper;
};

const lastPayload = () => BookingPagesAPI.update.mock.calls.at(-1)[1];

describe('BookingWizard', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    BookingPagesAPI.people.mockImplementation(() =>
      reply([
        { id: 1, name: 'Maria' },
        { id: 2, name: 'João' },
      ])
    );
    BookingPagesAPI.update.mockImplementation((_id, body) =>
      reply(fullPage({ title: body.title ?? 'Conversa de vendas' }))
    );
    CrmKanbanAPI.getPipelines.mockImplementation(() =>
      reply([{ id: 3, name: 'Vendas' }])
    );
    CrmKanbanAPI.getStages.mockImplementation(() =>
      reply([
        { id: 30, name: 'Conversa agendada' },
        { id: 31, name: 'Proposta' },
      ])
    );
  });

  describe('passo 1, modelo', () => {
    it('mostra os quatro modelos e o passo atual para o leitor de tela', async () => {
      const wrapper = mount(BookingWizard, { props: { pageId: null } });
      await flushPromises();
      expect(currentStep(wrapper)).toBe('MODELO');
      const keys = wrapper
        .findAll('[data-template]')
        .map(item => item.attributes('data-template'));
      expect(keys).toEqual(['sales_30', 'consult_45', 'visit_60', 'blank']);
      expect(wrapper.find('[data-primary]').exists()).toBe(false);
    });

    it('escolher o modelo cria a página e abre o passo 2 já preenchido', async () => {
      BookingPagesAPI.create.mockImplementation(() => reply(fullPage()));
      const wrapper = mount(BookingWizard, { props: { pageId: null } });
      await wrapper.find('[data-template="sales_30"]').trigger('click');
      await flushPromises();
      expect(BookingPagesAPI.create).toHaveBeenCalledWith({
        templateKey: 'sales_30',
      });
      expect(currentStep(wrapper)).toBe('CONTE');
      expect(wrapper.find('[data-title] input').element.value).toBe(
        'Conversa de vendas'
      );
      expect(BookingPagesAPI.people).toHaveBeenCalledWith(7);
    });

    it('falha ao criar avisa e continua no passo 1', async () => {
      BookingPagesAPI.create.mockRejectedValue(new Error('rede'));
      const wrapper = mount(BookingWizard, { props: { pageId: null } });
      await wrapper.find('[data-template="blank"]').trigger('click');
      await flushPromises();
      expect(currentStep(wrapper)).toBe('MODELO');
      expect(wrapper.find('[data-save-error]').text()).toBe(
        'BOOKING.TEMPLATE.CREATE_ERROR'
      );
    });
  });

  describe('passo 2, conte', () => {
    it('sem nome não salva e diz o que falta', async () => {
      const wrapper = await mountWizard();
      await wrapper.find('[data-title] input').setValue('   ');
      await continueStep(wrapper);
      expect(BookingPagesAPI.update).not.toHaveBeenCalled();
      expect(wrapper.text()).toContain('BOOKING.WIZARD.ERRORS.TITLE');
      expect(currentStep(wrapper)).toBe('CONTE');
    });

    it('pessoas são botões de alternância e vão para PUT people', async () => {
      const wrapper = await mountWizard();
      const joao = wrapper.find('[data-person="2"]');
      expect(joao.attributes('aria-pressed')).toBe('false');
      expect(joao.classes()).toContain('min-h-11');
      await joao.trigger('click');
      expect(joao.attributes('aria-pressed')).toBe('true');
      await joao.trigger('click');
      await wrapper
        .findComponent(ChoiceSelect)
        .vm.$emit('update:modelValue', 45);
      await continueStep(wrapper);
      expect(lastPayload().duration_minutes).toBe(45);
      expect(BookingPagesAPI.updatePeople).not.toHaveBeenCalled();
    });

    it('trocar quem atende chama PUT people com os ids escolhidos', async () => {
      BookingPagesAPI.updatePeople.mockImplementation(() =>
        reply(fullPage({ people: [{ id: 1 }, { id: 2 }] }))
      );
      const wrapper = await mountWizard();
      await wrapper.find('[data-person="2"]').trigger('click');
      await continueStep(wrapper);
      expect(BookingPagesAPI.updatePeople).toHaveBeenCalledWith(7, [1, 2]);
      expect(currentStep(wrapper)).toBe('ONDE');
    });

    it('sem ninguém escolhido não avança', async () => {
      const wrapper = await mountWizard();
      await wrapper.find('[data-person="1"]').trigger('click');
      await continueStep(wrapper);
      expect(wrapper.text()).toContain('BOOKING.WIZARD.ERRORS.PEOPLE');
      expect(currentStep(wrapper)).toBe('CONTE');
    });

    it('voltar não perde o que foi digitado', async () => {
      const wrapper = await mountWizard();
      await wrapper.find('[data-title] input').setValue('Conversa rápida');
      await continueStep(wrapper);
      expect(currentStep(wrapper)).toBe('ONDE');
      await wrapper.find('[data-back]').trigger('click');
      expect(currentStep(wrapper)).toBe('CONTE');
      expect(wrapper.find('[data-title] input').element.value).toBe(
        'Conversa rápida'
      );
    });

    it('voltar do passo 2 fecha o assistente', async () => {
      const wrapper = await mountWizard();
      await wrapper.find('[data-back]').trigger('click');
      expect(wrapper.emitted('close')).toHaveLength(1);
    });

    // #1370: com `?voltar=` válido, sair leva para outra tela (o agente).
    it('sair diz Voltar para a lista; voltando para outra tela, só Voltar', async () => {
      const wrapper = await mountWizard();
      expect(wrapper.find('[data-back]').text()).toBe(
        'BOOKING.WIZARD.BACK_TO_LIST'
      );
      await wrapper.setProps({ returnsElsewhere: true });
      expect(wrapper.find('[data-back]').text()).toBe('BOOKING.WIZARD.BACK');
    });

    it('erro ao salvar mostra o aviso e fica no passo', async () => {
      BookingPagesAPI.update.mockRejectedValue(new Error('rede'));
      const wrapper = await mountWizard();
      await continueStep(wrapper);
      expect(wrapper.find('[data-save-error]').text()).toBe(
        'BOOKING.WIZARD.SAVE_ERROR'
      );
      expect(currentStep(wrapper)).toBe('CONTE');
    });
  });

  describe('passo 3, onde acontece', () => {
    it('sem caixa conectada: só os locais do WhatsApp, link e local, e o aviso', async () => {
      const wrapper = await openAtStep(3);
      expect(currentStep(wrapper)).toBe('ONDE');
      const types = wrapper
        .findAll('[data-location]')
        .map(item => item.attributes('data-location'));
      expect(types).toEqual([
        'whatsapp_video',
        'whatsapp_voice',
        'custom_link',
        'in_person',
      ]);
      expect(wrapper.find('[data-calendar-hint]').text()).toBe(
        'BOOKING.WHERE.CALENDAR_HINT'
      );
    });

    it('com caixa Google conectada aparece o Meet (e não o Teams) e a escolha da caixa', async () => {
      const page = fullPage({
        calendar_options: [
          { id: 11, name: 'Comercial', provider: 'google' },
          { id: 12, name: 'Vendas', provider: 'google' },
        ],
      });
      const wrapper = await openAtStep(3, page);
      expect(wrapper.find('[data-location="google_meet"]').exists()).toBe(true);
      expect(wrapper.find('[data-location="teams"]').exists()).toBe(false);
      expect(wrapper.find('[data-calendar-hint]').exists()).toBe(false);
      await wrapper.find('[data-location="google_meet"]').trigger('click');
      const select = wrapper.findComponent(ChoiceSelect);
      expect(select.props('options')).toEqual([
        { value: 11, label: 'Comercial' },
        { value: 12, label: 'Vendas' },
      ]);
      await select.vm.$emit('update:modelValue', 12);
      await continueStep(wrapper);
      expect(lastPayload().calendar_inbox_id).toBe(12);
      expect(lastPayload().locations).toEqual([
        { type: 'whatsapp_video' },
        { type: 'google_meet' },
      ]);
    });

    it('com caixa Microsoft aparece só o Teams', async () => {
      const page = fullPage({
        calendar_options: [{ id: 13, name: 'Time', provider: 'microsoft' }],
      });
      const wrapper = await openAtStep(3, page);
      expect(wrapper.find('[data-location="teams"]').exists()).toBe(true);
      expect(wrapper.find('[data-location="google_meet"]').exists()).toBe(
        false
      );
    });

    it('Meu link pede o endereço completo antes de salvar', async () => {
      const wrapper = await openAtStep(3);
      await wrapper.find('[data-location="custom_link"]').trigger('click');
      await wrapper.find('[data-link] input').setValue('zoom.us/j/1');
      const before = BookingPagesAPI.update.mock.calls.length;
      await continueStep(wrapper);
      expect(BookingPagesAPI.update.mock.calls.length).toBe(before);
      expect(wrapper.text()).toContain('BOOKING.WIZARD.ERRORS.LINK');
      await wrapper.find('[data-link] input').setValue('https://zoom.us/j/1');
      await continueStep(wrapper);
      expect(lastPayload().locations).toContainEqual({
        type: 'custom_link',
        url: 'https://zoom.us/j/1',
      });
    });

    it('sem nenhum local escolhido não avança', async () => {
      const wrapper = await openAtStep(3);
      await wrapper.find('[data-location="whatsapp_video"]').trigger('click');
      await continueStep(wrapper);
      expect(wrapper.text()).toContain('BOOKING.WIZARD.ERRORS.LOCATION');
      expect(currentStep(wrapper)).toBe('ONDE');
    });
  });

  describe('passo 4, dias e horas', () => {
    it('dias são botões de alternância e o horário vem do modelo', async () => {
      const wrapper = await openAtStep(4);
      expect(currentStep(wrapper)).toBe('QUANDO');
      expect(wrapper.find('[data-day="1"]').attributes('aria-pressed')).toBe(
        'true'
      );
      expect(wrapper.find('[data-day="6"]').attributes('aria-pressed')).toBe(
        'false'
      );
      expect(wrapper.find('[data-day="1"]').attributes('aria-label')).toBe(
        'BOOKING.WEEKDAYS_LONG.MON'
      );
      await wrapper.find('[data-day="6"]').trigger('click');
      await continueStep(wrapper);
      expect(lastPayload().working_hours).toEqual({
        start_hour: 9,
        end_hour: 17,
        weekdays: [1, 2, 3, 4, 5, 6],
      });
      expect(lastPayload().min_notice_minutes).toBe(120);
      expect(lastPayload().buffer_minutes).toBe(10);
    });

    it('antecedência, intervalo e horários são escolhas prontas', async () => {
      const wrapper = await openAtStep(4);
      const selects = wrapper.findAllComponents(ChoiceSelect);
      expect(selects).toHaveLength(4);
      const notice = selects[2].props('options').map(item => item.value);
      expect(notice).toEqual([0, 30, 60, 120, 240, 1440, 2880]);
      await selects[3].vm.$emit('update:modelValue', 15);
      await wrapper.find('[data-extra="60"]').trigger('click');
      await continueStep(wrapper);
      expect(lastPayload().buffer_minutes).toBe(15);
      expect(lastPayload().slot_durations).toEqual([60]);
    });

    it('sem dia escolhido ou com fim antes do início não avança', async () => {
      const wrapper = await openAtStep(4);
      await wrapper
        .findAllComponents(ChoiceSelect)[1]
        .vm.$emit('update:modelValue', 8);
      await continueStep(wrapper);
      expect(wrapper.text()).toContain('BOOKING.WIZARD.ERRORS.HOURS');
      expect(currentStep(wrapper)).toBe('QUANDO');
    });
  });

  describe('passo 5, cara', () => {
    const file = (type, size = 10) =>
      new File(['x'.repeat(size)], 'imagem', { type });

    it('só cuida da marca: os avisos têm passo próprio', async () => {
      const wrapper = await openAtStep(5);
      expect(currentStep(wrapper)).toBe('CARA');
      expect(wrapper.text()).not.toContain('NOTICES');
      expect(wrapper.findAll('[data-color]')).toHaveLength(6);
      expect(primary(wrapper).attributes('data-action')).toBe('CONTINUE');
    });

    it('recusa arquivo que não é PNG, JPEG ou WebP sem chamar a API', async () => {
      const wrapper = await openAtStep(5);
      const input = wrapper.find('[data-logo] [data-file]');
      Object.defineProperty(input.element, 'files', {
        value: [file('image/svg+xml')],
        configurable: true,
      });
      await input.trigger('change');
      await flushPromises();
      expect(BookingPagesAPI.uploadImage).not.toHaveBeenCalled();
      expect(wrapper.find('[data-logo]').text()).toContain(
        'BOOKING.WIZARD.ERRORS.IMAGE_TYPE'
      );
    });

    it('envia a foto e mostra a prévia que voltou', async () => {
      BookingPagesAPI.uploadImage.mockImplementation(() =>
        reply(fullPage({ photo_url: 'https://cdn.exemplo.com/foto.png' }))
      );
      const wrapper = await openAtStep(5);
      const input = wrapper.find('[data-photo] [data-file]');
      const photo = file('image/png');
      Object.defineProperty(input.element, 'files', {
        value: [photo],
        configurable: true,
      });
      await input.trigger('change');
      await flushPromises();
      expect(BookingPagesAPI.uploadImage).toHaveBeenCalledWith(
        7,
        'photo',
        photo,
        { applyToProfile: false }
      );
      expect(wrapper.find('[data-photo] img').attributes('src')).toBe(
        'https://cdn.exemplo.com/foto.png'
      );
    });

    it('diz o que trocar quando o servidor recusa o conteúdo do arquivo', async () => {
      BookingPagesAPI.uploadImage.mockRejectedValue({
        response: { status: 422, data: { reason: 'image_content' } },
      });
      const wrapper = await openAtStep(5);
      const input = wrapper.find('[data-logo] [data-file]');
      Object.defineProperty(input.element, 'files', {
        value: [file('image/png')],
        configurable: true,
      });
      await input.trigger('change');
      await flushPromises();
      expect(wrapper.find('[data-logo]').text()).toContain(
        'BOOKING.WIZARD.ERRORS.IMAGE_CONTENT'
      );
    });

    it('cor escolhida e frase vão no PATCH', async () => {
      const wrapper = await openAtStep(5);
      await wrapper.find('[data-color="#0B7A5A"]').trigger('click');
      expect(
        wrapper.find('[data-color="#0B7A5A"]').attributes('aria-pressed')
      ).toBe('true');
      await wrapper.find('[data-headline] input').setValue('Vamos conversar');
      await continueStep(wrapper);
      expect(lastPayload().brand).toEqual({
        color: '#0B7A5A',
        headline: 'Vamos conversar',
        logo_align: 'left',
      });
      expect(currentStep(wrapper)).toBe('AVISOS');
    });
  });

  describe('passo 6, avisos no WhatsApp', () => {
    const WAHA = {
      id: 13,
      name: 'Celular',
      provider: 'waha',
      needs_templates: false,
    };

    it('escolhe número, jogo e prazo e salva no Continuar', async () => {
      const page = fullPage({ notice_inbox_options: [WAHA] });
      const wrapper = await openAtStep(6, page);
      expect(currentStep(wrapper)).toBe('AVISOS');
      expect(primary(wrapper).attributes('data-action')).toBe('SEE_PREVIEW');
      // O número não foi mexido: o PATCH dos passos anteriores não o leva.
      expect('notice_inbox_id' in lastPayload()).toBe(false);
      await wrapper
        .findAllComponents(ChoiceSelect)[0]
        .vm.$emit('update:modelValue', 13);
      await wrapper.find('[data-choice="light"] input').setValue(true);
      await wrapper.find('[data-choice="1440"] input').setValue(true);
      await continueStep(wrapper);
      expect(lastPayload()).toMatchObject({
        notice_inbox_id: 13,
        notice_preset: 'light',
        notice_templates: {},
        cancel_until_minutes: 1440,
      });
      expect(currentStep(wrapper)).toBe('PREVIA');
    });

    it('número de avisos recusado (422) tem aviso próprio', async () => {
      const wrapper = await openAtStep(6);
      BookingPagesAPI.update.mockRejectedValue({
        response: {
          status: 422,
          data: { error: 'crm.booking_v2.notice_inbox_invalid' },
        },
      });
      await continueStep(wrapper);
      expect(wrapper.find('[data-save-error]').text()).toBe(
        'BOOKING.WIZARD.SERVER_ERRORS.NOTICE_INBOX_GONE'
      );
      expect(currentStep(wrapper)).toBe('AVISOS');
    });

    it('prévia resume os avisos e Alterar volta ao passo deles', async () => {
      const wrapper = await openAtStep(7);
      expect(wrapper.find('[data-notices-summary]').text()).toContain(
        'BOOKING.PREVIEW.NOTICES_OFF'
      );
      await wrapper.find('[data-notices-alter]').trigger('click');
      expect(currentStep(wrapper)).toBe('AVISOS');
    });

    it('publicada com número de avisos oferece Testar no meu WhatsApp', async () => {
      const page = fullPage({
        enabled: true,
        notice_inbox_id: 13,
        notice_inbox_options: [WAHA],
      });
      const wrapper = await openAtStep(7, page);
      expect(wrapper.find('[data-published] [data-test-start]').text()).toBe(
        'BOOKING.NOTICES.TEST.BUTTON'
      );
    });

    it('número de avisos que a pessoa não enxerga: sem o botão de teste (o servidor recusaria)', async () => {
      const page = fullPage({
        enabled: true,
        notice_inbox_id: 99,
        notice_inbox_options: [WAHA],
      });
      const wrapper = await openAtStep(7, page);
      expect(wrapper.find('[data-published]').exists()).toBe(true);
      expect(wrapper.find('[data-test-start]').exists()).toBe(false);
    });

    it('publicada sem número de avisos não oferece o teste', async () => {
      const wrapper = await openAtStep(7, fullPage({ enabled: true }));
      expect(wrapper.find('[data-published]').exists()).toBe(true);
      expect(wrapper.find('[data-test-start]').exists()).toBe(false);
    });
  });

  describe('passo 5: cor própria, lado da logo e identidade salva (#1289)', () => {
    const LOGO = 'https://cdn.exemplo.com/logo.png';
    const IDENTITY = {
      saved: true,
      color: '#ffe066',
      logo_align: 'center',
      headline: 'Bem-vindo',
      logo_url: LOGO,
      photo_url: null,
    };

    it('mantém as cores prontas e oferece Outra cor, que vai no PATCH', async () => {
      const wrapper = await openAtStep(5);
      expect(wrapper.findAll('[data-color]')).toHaveLength(6);
      const custom = wrapper.find('[data-custom-color]');
      expect(custom.text()).toContain('BOOKING.LOOK.CUSTOM_COLOR');
      expect(custom.attributes('data-selected')).toBe('false');

      await custom.find('input[type="color"]').setValue('#ffe066');
      expect(
        wrapper.find('[data-custom-color]').attributes('data-selected')
      ).toBe('true');
      expect(wrapper.find('[data-custom-color-value]').text()).toBe('#ffe066');
      expect(
        wrapper
          .findAll('[data-color]')
          .filter(button => button.attributes('aria-pressed') === 'true')
      ).toHaveLength(0);

      await continueStep(wrapper);
      expect(lastPayload().brand.color).toBe('#ffe066');
    });

    it('a amostra mostra a cor escolhida com o texto do botão legível', async () => {
      const wrapper = await openAtStep(5);
      await wrapper
        .find('[data-custom-color] input[type="color"]')
        .setValue('#ffe066');
      await flushPromises();
      const sample = wrapper.find(
        '[data-brand-sample] [data-sample-page]'
      ).element;
      expect(sample.style.getPropertyValue('--brand-fill-light')).toBe(
        '#ffe066'
      );
      expect(sample.style.getPropertyValue('--brand-on-light')).toBe('#000000');

      await wrapper.find('[data-color="#0D2344"]').trigger('click');
      await flushPromises();
      expect(sample.style.getPropertyValue('--brand-fill-light')).toBe(
        '#0d2344'
      );
      expect(sample.style.getPropertyValue('--brand-on-light')).toBe('#ffffff');
    });

    it('sem logo não pergunta o lado; com logo, três cartões e o padrão é a esquerda', async () => {
      const without = await openAtStep(5);
      expect(without.find('[data-logo-aligns]').exists()).toBe(false);

      const wrapper = await openAtStep(5, fullPage({ logo_url: LOGO }));
      const cards = wrapper.findAll('button[data-logo-align]');
      expect(cards.map(card => card.attributes('data-logo-align'))).toEqual([
        'left',
        'center',
        'right',
      ]);
      expect(wrapper.find('select').exists()).toBe(false);
      expect(
        wrapper
          .find('button[data-logo-align="left"]')
          .attributes('aria-pressed')
      ).toBe('true');

      await wrapper.find('button[data-logo-align="center"]').trigger('click');
      expect(
        wrapper
          .find('[data-brand-sample] [data-logo-box]')
          .attributes('data-logo-align')
      ).toBe('center');
      await continueStep(wrapper);
      expect(lastPayload().brand.logo_align).toBe('center');
    });

    it('logo salva volta com o lado que foi escolhido', async () => {
      const wrapper = await openAtStep(
        5,
        fullPage({ logo_url: LOGO, brand: { logo_align: 'right' } })
      );
      expect(
        wrapper
          .find('button[data-logo-align="right"]')
          .attributes('aria-pressed')
      ).toBe('true');
    });

    it('a logo aparece inteira no envio (não cortada); a foto preenche o círculo', async () => {
      const wrapper = await openAtStep(
        5,
        fullPage({ logo_url: LOGO, photo_url: 'https://cdn.exemplo.com/f.png' })
      );
      expect(wrapper.find('[data-logo] img').classes()).toContain(
        'object-contain'
      );
      expect(wrapper.find('[data-logo] img').classes()).not.toContain(
        'object-cover'
      );
      expect(wrapper.find('[data-photo] img').classes()).toContain(
        'object-cover'
      );
    });

    it('sem identidade salva não oferece usar; o administrador pode salvar', async () => {
      const wrapper = await openAtStep(
        5,
        fullPage({ can_save_identity: true })
      );
      expect(wrapper.find('[data-use-identity]').exists()).toBe(false);
      expect(wrapper.find('[data-save-identity]').exists()).toBe(true);
    });

    it('quem não é administrador usa a identidade, mas não vê Salvar como identidade', async () => {
      const wrapper = await openAtStep(
        5,
        fullPage({ identity: IDENTITY, can_save_identity: false })
      );
      expect(wrapper.find('[data-use-identity]').exists()).toBe(true);
      expect(wrapper.find('[data-save-identity]').exists()).toBe(false);
    });

    it('Usar a identidade salva pede confirmação antes de trocar o que está na tela', async () => {
      const wrapper = await openAtStep(5, fullPage({ identity: IDENTITY }));
      await wrapper.find('[data-color="#0B7A5A"]').trigger('click');

      await wrapper.find('[data-use-identity]').trigger('click');
      const box = wrapper.find('[data-identity-confirm]');
      expect(box.attributes('role')).toBe('alertdialog');
      expect(box.text()).toContain('BOOKING.LOOK.IDENTITY.CONFIRM');
      expect(BookingPagesAPI.applyIdentity).not.toHaveBeenCalled();

      // Esc fecha a pergunta e devolve o foco ao botão; o "Não" também.
      await box.trigger('keydown', { key: 'Escape' });
      await flushPromises();
      expect(wrapper.find('[data-identity-confirm]').exists()).toBe(false);
      await wrapper.find('[data-use-identity]').trigger('click');
      await wrapper.find('[data-identity-confirm-no]').trigger('click');
      await flushPromises();
      expect(BookingPagesAPI.applyIdentity).not.toHaveBeenCalled();
      expect(wrapper.find('[data-identity-confirm]').exists()).toBe(false);
      expect(
        wrapper.find('[data-color="#0B7A5A"]').attributes('aria-pressed')
      ).toBe('true');
    });

    it('confirmado, traz logo, cor, lado e frase para a página', async () => {
      const applied = fullPage({
        identity: IDENTITY,
        logo_url: LOGO,
        brand: {
          color: '#ffe066',
          logo_align: 'center',
          headline: 'Bem-vindo',
        },
      });
      BookingPagesAPI.applyIdentity.mockImplementation(() => reply(applied));
      const wrapper = await openAtStep(5, fullPage({ identity: IDENTITY }));

      await wrapper.find('[data-use-identity]').trigger('click');
      await wrapper.find('[data-identity-confirm-yes]').trigger('click');
      await flushPromises();

      expect(BookingPagesAPI.applyIdentity).toHaveBeenCalledWith(7);
      expect(wrapper.find('[data-logo] img').attributes('src')).toBe(LOGO);
      expect(wrapper.find('[data-custom-color-value]').text()).toBe('#ffe066');
      expect(
        wrapper
          .find('button[data-logo-align="center"]')
          .attributes('aria-pressed')
      ).toBe('true');
      expect(wrapper.find('[data-headline] input').element.value).toBe(
        'Bem-vindo'
      );
      expect(wrapper.find('[data-identity-notice]').text()).toBe(
        'BOOKING.LOOK.IDENTITY.APPLIED'
      );
    });

    it('identidade sem frase limpa a frase da página', async () => {
      BookingPagesAPI.applyIdentity.mockImplementation(() =>
        reply(fullPage({ identity: IDENTITY, brand: { color: '#ffe066' } }))
      );
      const wrapper = await openAtStep(5, fullPage({ identity: IDENTITY }));
      await wrapper.find('[data-headline] input').setValue('Frase antiga');

      await wrapper.find('[data-use-identity]').trigger('click');
      await wrapper.find('[data-identity-confirm-yes]').trigger('click');
      await flushPromises();

      expect(wrapper.find('[data-headline] input').element.value).toBe('');
    });

    it('Salvar como identidade salva a página primeiro e diz o que foi guardado', async () => {
      BookingPagesAPI.saveIdentity.mockImplementation(() =>
        reply(fullPage({ identity: IDENTITY, can_save_identity: true }))
      );
      const wrapper = await openAtStep(
        5,
        fullPage({ can_save_identity: true })
      );
      await wrapper.find('[data-color="#0B7A5A"]').trigger('click');
      BookingPagesAPI.update.mockClear();

      await wrapper.find('[data-save-identity]').trigger('click');
      await flushPromises();

      expect(lastPayload().brand.color).toBe('#0B7A5A');
      expect(BookingPagesAPI.saveIdentity).toHaveBeenCalledWith(7);
      expect(BookingPagesAPI.update.mock.invocationCallOrder[0]).toBeLessThan(
        BookingPagesAPI.saveIdentity.mock.invocationCallOrder[0]
      );
      // A página não tem foto enviada: nada de foto foi guardado, e o aviso diz isso.
      expect(wrapper.find('[data-identity-notice]').text()).toBe(
        'BOOKING.LOOK.IDENTITY.SAVED_NO_PHOTO'
      );
      expect(wrapper.find('[data-use-identity]').exists()).toBe(true);
      expect(currentStep(wrapper)).toBe('CARA');
    });

    it('com a foto guardada, o aviso inclui a foto', async () => {
      BookingPagesAPI.saveIdentity.mockImplementation(() =>
        reply(
          fullPage({
            identity: {
              ...IDENTITY,
              photo_url: 'https://cdn.exemplo.com/f.png',
            },
            photo_url: 'https://cdn.exemplo.com/f.png',
            assignment_mode: 'fixed',
            host: { id: 1, name: 'Maria' },
            can_save_identity: true,
          })
        )
      );
      const wrapper = await openAtStep(
        5,
        fullPage({ can_save_identity: true })
      );
      await wrapper.find('[data-save-identity]').trigger('click');
      await flushPromises();
      expect(wrapper.find('[data-identity-notice]').text()).toBe(
        'BOOKING.LOOK.IDENTITY.SAVED'
      );
    });

    it('página com um link por pessoa não guarda foto, mesmo com foto e uma pessoa só', async () => {
      BookingPagesAPI.saveIdentity.mockImplementation(() =>
        reply(
          fullPage({
            identity: IDENTITY,
            photo_url: 'https://cdn.exemplo.com/f.png',
            assignment_mode: 'per_agent',
            host: null,
            can_save_identity: true,
          })
        )
      );
      const wrapper = await openAtStep(
        5,
        fullPage({ can_save_identity: true })
      );
      await wrapper.find('[data-save-identity]').trigger('click');
      await flushPromises();
      expect(wrapper.find('[data-identity-notice]').text()).toBe(
        'BOOKING.LOOK.IDENTITY.SAVED_NO_PHOTO'
      );
    });

    it('falha ao salvar a identidade mostra o motivo do servidor e não sai do passo', async () => {
      BookingPagesAPI.saveIdentity.mockRejectedValue({
        response: {
          status: 422,
          data: { errors: { brand: ['invalid color'] } },
        },
      });
      const wrapper = await openAtStep(
        5,
        fullPage({ can_save_identity: true })
      );
      await wrapper.find('[data-save-identity]').trigger('click');
      await flushPromises();
      expect(wrapper.find('[data-save-error]').text()).toBe(
        'BOOKING.WIZARD.SERVER_ERRORS.BRAND'
      );
      expect(wrapper.find('[data-identity-notice]').exists()).toBe(false);
      expect(currentStep(wrapper)).toBe('CARA');
    });
  });

  describe('passo 5: a foto de quem atende e a foto do perfil (#1298)', () => {
    const AVATAR = 'https://cdn.exemplo.com/perfil.png';
    const NEW_PHOTO = 'https://cdn.exemplo.com/nova.png';
    const png = () => new File(['x'], 'foto.png', { type: 'image/png' });
    const mine = (extra = {}) => ({
      name: 'Maria',
      mine: true,
      profile_url: AVATAR,
      profile_updated: false,
      ...extra,
    });

    const pick = async (wrapper, picked = png()) => {
      const input = wrapper.find('[data-photo] [data-file]');
      Object.defineProperty(input.element, 'files', {
        value: [picked],
        configurable: true,
      });
      await input.trigger('change');
      await flushPromises();
      return picked;
    };
    const uploadArgs = () => BookingPagesAPI.uploadImage.mock.calls.at(-1);

    beforeEach(() => {
      storeDispatch.mockClear();
      BookingPagesAPI.uploadImage.mockImplementation(() =>
        reply(fullPage({ photo_url: NEW_PHOTO, photo_owner: mine() }))
      );
    });

    it('quem tem foto no perfil já vê essa foto em uso, com Trocar', async () => {
      const wrapper = await openAtStep(5, fullPage({ photo_owner: mine() }));
      const card = wrapper.find('[data-photo]');
      expect(card.find('img').attributes('src')).toBe(AVATAR);
      expect(card.text()).toContain(
        'BOOKING.LOOK.PHOTO_CARD.USING_PROFILE_MINE'
      );
      expect(card.find('[data-upload]').text()).toBe('BOOKING.LOOK.CHANGE');
      expect(card.find('[data-photo-notice]').exists()).toBe(false);
    });

    it('a foto da página vem antes da guardada, e a guardada antes da do perfil', async () => {
      const saved = 'https://cdn.exemplo.com/guardada.png';
      const host = { id: 1, name: 'Maria', booking_photo_url: saved };
      const withSaved = await openAtStep(
        5,
        fullPage({ photo_owner: mine(), host })
      );
      expect(withSaved.find('[data-photo] img').attributes('src')).toBe(saved);
      expect(withSaved.find('[data-photo]').text()).toContain(
        'BOOKING.LOOK.PHOTO_CARD.USING_SAVED'
      );

      const own = await openAtStep(
        5,
        fullPage({ photo_owner: mine(), host, photo_url: NEW_PHOTO })
      );
      expect(own.find('[data-photo] img').attributes('src')).toBe(NEW_PHOTO);
      expect(own.find('[data-photo]').text()).not.toContain('USING_');
    });

    it('ao trocar, pergunta onde vale em dois cartões; o padrão é só nesta página', async () => {
      const wrapper = await openAtStep(5, fullPage({ photo_owner: mine() }));
      const photo = await pick(wrapper);

      expect(BookingPagesAPI.uploadImage).not.toHaveBeenCalled();
      const box = wrapper.find('[data-photo-choice]');
      expect(box.attributes('role')).toBe('alertdialog');
      expect(wrapper.find('select').exists()).toBe(false);
      const cards = box.findAll('[data-photo-target]');
      expect(cards.map(card => card.attributes('data-photo-target'))).toEqual([
        'page',
        'profile',
      ]);
      expect(cards.map(card => card.attributes('aria-checked'))).toEqual([
        'true',
        'false',
      ]);
      // Tab para só na marcada; a seta troca a opção e volta.
      expect(cards.map(card => card.attributes('tabindex'))).toEqual([
        '0',
        '-1',
      ]);
      await cards[0].trigger('keydown', { key: 'ArrowDown' });
      expect(
        wrapper.find('[data-photo-target="profile"]').attributes('aria-checked')
      ).toBe('true');
      await cards[1].trigger('keydown', { key: 'ArrowUp' });
      expect(
        wrapper.find('[data-photo-target="page"]').attributes('aria-checked')
      ).toBe('true');

      await box.find('[data-photo-choice-send]').trigger('click');
      await flushPromises();
      expect(uploadArgs()).toEqual([
        7,
        'photo',
        photo,
        { applyToProfile: false },
      ]);
      expect(storeDispatch).not.toHaveBeenCalled();
      expect(wrapper.find('[data-photo-choice]').exists()).toBe(false);
      expect(wrapper.find('[data-photo] img').attributes('src')).toBe(
        NEW_PHOTO
      );
    });

    it('"Também no meu perfil" manda o pedido e o painel relê o usuário', async () => {
      BookingPagesAPI.uploadImage.mockImplementation(() =>
        reply(
          fullPage({
            photo_url: NEW_PHOTO,
            photo_owner: mine({
              profile_url: NEW_PHOTO,
              profile_updated: true,
            }),
          })
        )
      );
      const wrapper = await openAtStep(5, fullPage({ photo_owner: mine() }));
      const photo = await pick(wrapper);

      await wrapper.find('[data-photo-target="profile"]').trigger('click');
      expect(
        wrapper.find('[data-photo-target="profile"]').attributes('aria-checked')
      ).toBe('true');
      await wrapper.find('[data-photo-choice-send]').trigger('click');
      await flushPromises();

      expect(uploadArgs()).toEqual([
        7,
        'photo',
        photo,
        { applyToProfile: true },
      ]);
      expect(storeDispatch).toHaveBeenCalledWith('validityCheck');
    });

    it('cancelar (ou Esc) não envia nada', async () => {
      const wrapper = await openAtStep(5, fullPage({ photo_owner: mine() }));
      await pick(wrapper);
      await wrapper.find('[data-photo-choice-cancel]').trigger('click');
      await flushPromises();
      expect(wrapper.find('[data-photo-choice]').exists()).toBe(false);

      await pick(wrapper);
      await wrapper
        .find('[data-photo-choice]')
        .trigger('keydown', { key: 'Escape' });
      await flushPromises();
      expect(wrapper.find('[data-photo-choice]').exists()).toBe(false);
      expect(BookingPagesAPI.uploadImage).not.toHaveBeenCalled();
    });

    it('sem foto no perfil: avisa antes e a foto vai para os dois, sem perguntar', async () => {
      const wrapper = await openAtStep(
        5,
        fullPage({ photo_owner: mine({ profile_url: null }) })
      );
      const card = wrapper.find('[data-photo]');
      expect(card.find('img').exists()).toBe(false);
      expect(card.find('[data-photo-notice]').text()).toContain(
        'BOOKING.LOOK.PHOTO_CARD.GOES_TO_PROFILE'
      );

      const photo = await pick(wrapper);
      expect(wrapper.find('[data-photo-choice]').exists()).toBe(false);
      expect(uploadArgs()).toEqual([
        7,
        'photo',
        photo,
        { applyToProfile: true },
      ]);
    });

    it('administrador na página de outra pessoa: troca só o agendamento e a tela diz isso', async () => {
      const other = mine({ name: 'Bia', mine: false });
      const wrapper = await openAtStep(5, fullPage({ photo_owner: other }));
      const card = wrapper.find('[data-photo]');
      expect(card.find('img').attributes('src')).toBe(AVATAR);
      expect(card.text()).toContain(
        'BOOKING.LOOK.PHOTO_CARD.USING_PROFILE_OTHER {"key":"USING_PROFILE_OTHER","name":"Bia"}'
      );
      expect(card.find('[data-photo-notice]').text()).toContain(
        'BOOKING.LOOK.PHOTO_CARD.OTHER_PERSON'
      );

      const photo = await pick(wrapper);
      expect(wrapper.find('[data-photo-choice]').exists()).toBe(false);
      expect(uploadArgs()).toEqual([
        7,
        'photo',
        photo,
        { applyToProfile: false },
      ]);
      expect(storeDispatch).not.toHaveBeenCalled();
    });

    it('página com um link por pessoa: a foto é da página e o perfil de ninguém muda', async () => {
      const wrapper = await openAtStep(5, fullPage({ photo_owner: null }));
      expect(wrapper.find('[data-photo-notice]').text()).toContain(
        'BOOKING.LOOK.PHOTO_CARD.SHARED_PAGE'
      );
      const photo = await pick(wrapper);
      expect(uploadArgs()).toEqual([
        7,
        'photo',
        photo,
        { applyToProfile: false },
      ]);
    });
  });

  describe('passo 5: logo para fundo claro e escuro, e tema da prévia (#1295)', () => {
    const LOGO = 'https://cdn.exemplo.com/logo.png';
    const LOGO_DARK = 'https://cdn.exemplo.com/logo-escura.png';
    const png = () => new File(['x'], 'logo.png', { type: 'image/png' });
    const withLogo = (source, extra = {}) =>
      fullPage({
        logo_url: LOGO,
        brand: source ? { logo_dark_source: source } : {},
        ...extra,
      });
    const pickFile = async (wrapper, selector, chosen) => {
      const input = wrapper.find(selector);
      Object.defineProperty(input.element, 'files', {
        value: [chosen],
        configurable: true,
      });
      await input.trigger('change');
      await flushPromises();
    };
    const origin = wrapper =>
      wrapper.find('[data-logo-dark-origin]').attributes('data-origin');
    const darkImage = wrapper => wrapper.find('[data-logo-dark] img');

    it('sem logo: um botão só, e a linha diz que a de fundo escuro é criada na hora', async () => {
      const wrapper = await openAtStep(5);

      expect(wrapper.find('[data-logo] img').exists()).toBe(false);
      expect(darkImage(wrapper).exists()).toBe(false);
      expect(wrapper.find('[data-upload-dark]').exists()).toBe(false);
      expect(origin(wrapper)).toBe('NONE');
      expect(wrapper.find('[data-logo-dark-origin]').text()).toBe(
        'BOOKING.LOOK.LOGO_DARK.ORIGIN.NONE'
      );
    });

    it('as duas versões aparecem lado a lado, cada uma sobre o fundo certo', async () => {
      const wrapper = await openAtStep(
        5,
        withLogo('generated', { logo_dark_url: LOGO_DARK })
      );
      const light = wrapper.find('[data-logo] [data-booking-theme]');
      const dark = wrapper.find('[data-logo-dark] [data-booking-theme]');

      expect(light.attributes('data-booking-theme')).toBe('light');
      expect(dark.attributes('data-booking-theme')).toBe('dark');
      [light, dark].forEach(frame =>
        expect(frame.classes()).toContain('bg-bk-card')
      );
      expect(light.find('img').attributes('src')).toBe(LOGO);
      expect(dark.find('img').attributes('src')).toBe(LOGO_DARK);
      expect(wrapper.find('[data-logo-card]').text()).toContain(
        'BOOKING.LOOK.LOGO_LIGHT.TITLE'
      );
      expect(wrapper.find('[data-logo-card]').text()).toContain(
        'BOOKING.LOOK.LOGO_DARK.TITLE'
      );
      expect(wrapper.find('[data-logo] [data-upload]').exists()).toBe(true);
      expect(wrapper.find('[data-upload-dark]').exists()).toBe(true);
    });

    it.each([
      ['generated', LOGO_DARK, 'GENERATED', LOGO_DARK, 'false'],
      ['uploaded', LOGO_DARK, 'UPLOADED', LOGO_DARK, 'false'],
      ['same', null, 'SAME', LOGO, 'false'],
      ['plate', null, 'PLATE', LOGO, 'true'],
      // Página de antes do tema escuro, ou origem que a tela não conhece: o caso seguro.
      [null, null, 'PLATE', LOGO, 'true'],
      ['qualquer', null, 'PLATE', LOGO, 'true'],
    ])(
      'origem %s: explica em uma linha e mostra como fica no escuro',
      async (source, darkUrl, expected, shown, onPlate) => {
        const wrapper = await openAtStep(
          5,
          withLogo(source, { logo_dark_url: darkUrl })
        );

        expect(origin(wrapper)).toBe(expected);
        expect(wrapper.find('[data-logo-dark-origin]').text()).toBe(
          `BOOKING.LOOK.LOGO_DARK.ORIGIN.${expected}`
        );
        expect(darkImage(wrapper).attributes('src')).toBe(shown);
        expect(darkImage(wrapper).attributes('data-on-plate')).toBe(onPlate);
        expect(
          darkImage(wrapper).classes().includes('bg-[var(--bk-plate)]')
        ).toBe(onPlate === 'true');
        expect(wrapper.find('[data-remove-dark]').exists()).toBe(
          expected === 'UPLOADED'
        );
      }
    );

    it('enviar a logo já traz a de fundo escuro criada: a pessoa não faz mais nada', async () => {
      let finish;
      BookingPagesAPI.uploadImage.mockImplementation(
        () =>
          new Promise(resolve => {
            finish = resolve;
          })
      );
      const wrapper = await openAtStep(5);
      const chosen = png();
      await pickFile(wrapper, '[data-logo] [data-file]', chosen);

      expect(BookingPagesAPI.uploadImage).toHaveBeenCalledWith(
        7,
        'logo',
        chosen,
        { applyToProfile: false }
      );
      expect(origin(wrapper)).toBe('CREATING');

      finish({
        data: {
          payload: withLogo('generated', { logo_dark_url: LOGO_DARK }),
        },
      });
      await flushPromises();
      expect(origin(wrapper)).toBe('GENERATED');
      expect(darkImage(wrapper).attributes('src')).toBe(LOGO_DARK);
    });

    it('trocar a de fundo escuro envia para a rota dela', async () => {
      BookingPagesAPI.uploadImage.mockImplementation(() =>
        reply(withLogo('uploaded', { logo_dark_url: LOGO_DARK }))
      );
      const wrapper = await openAtStep(5, withLogo('plate'));
      const chosen = png();
      await pickFile(wrapper, '[data-logo-dark] [data-file-dark]', chosen);

      expect(BookingPagesAPI.uploadImage).toHaveBeenCalledWith(
        7,
        'logo_dark',
        chosen,
        { applyToProfile: false }
      );
      expect(origin(wrapper)).toBe('UPLOADED');
      expect(wrapper.find('[data-remove-dark]').exists()).toBe(true);
    });

    it('arquivo errado na de fundo escuro: avisa nela, sem chamar a API', async () => {
      const wrapper = await openAtStep(5, withLogo('plate'));
      await pickFile(
        wrapper,
        '[data-logo-dark] [data-file-dark]',
        new File(['x'], 'logo.svg', { type: 'image/svg+xml' })
      );

      expect(BookingPagesAPI.uploadImage).not.toHaveBeenCalled();
      expect(wrapper.find('[data-logo-dark] [role="alert"]').text()).toBe(
        'BOOKING.WIZARD.ERRORS.IMAGE_TYPE'
      );
      expect(wrapper.find('[data-logo] [role="alert"]').exists()).toBe(false);
    });

    it('"Voltar para a criada por nós" tira a enviada e mostra a que o servidor devolveu', async () => {
      BookingPagesAPI.removeLogoDark.mockImplementation(() =>
        reply(withLogo('same'))
      );
      const wrapper = await openAtStep(
        5,
        withLogo('uploaded', { logo_dark_url: LOGO_DARK })
      );
      await wrapper.find('[data-remove-dark]').trigger('click');
      await flushPromises();

      expect(BookingPagesAPI.removeLogoDark).toHaveBeenCalledWith(7);
      expect(origin(wrapper)).toBe('SAME');
      expect(darkImage(wrapper).attributes('src')).toBe(LOGO);
      expect(wrapper.find('[data-remove-dark]').exists()).toBe(false);
    });

    it('se tirar falhar, avisa e deixa como estava', async () => {
      BookingPagesAPI.removeLogoDark.mockImplementation(() =>
        Promise.reject(new Error('fora do ar'))
      );
      const wrapper = await openAtStep(
        5,
        withLogo('uploaded', { logo_dark_url: LOGO_DARK })
      );
      await wrapper.find('[data-remove-dark]').trigger('click');
      await flushPromises();

      expect(wrapper.find('[data-logo-dark] [role="alert"]').text()).toBe(
        'BOOKING.WIZARD.ERRORS.IMAGE_REMOVE'
      );
      expect(origin(wrapper)).toBe('UPLOADED');
    });

    it('salvar o passo não manda a origem da logo: ela é do servidor', async () => {
      const wrapper = await openAtStep(
        5,
        withLogo('generated', { logo_dark_url: LOGO_DARK })
      );
      await continueStep(wrapper);

      expect(Object.keys(lastPayload().brand).sort()).toEqual([
        'color',
        'headline',
        'logo_align',
      ]);
    });

    it('a amostra troca de tema no seletor Claro / Escuro, sem lista nativa', async () => {
      const wrapper = await openAtStep(
        5,
        withLogo('generated', { logo_dark_url: LOGO_DARK })
      );
      const sample = wrapper.find('[data-brand-sample]');
      const shown = sample.find('[data-sample-page]');

      expect(wrapper.find('select').exists()).toBe(false);
      expect(shown.attributes('data-booking-theme')).toBe('light');
      await sample.find('[data-theme-option="dark"] input').setValue(true);
      expect(shown.attributes('data-booking-theme')).toBe('dark');
      expect(sample.find('[data-theme-toggle]').text()).toContain(
        'BOOKING.THEME.LABEL'
      );
      expect(
        shown.find('[data-logo-box] [data-logo-for-dark]').attributes('src')
      ).toBe(LOGO_DARK);
    });

    it('a prévia do passo 7 também tem Claro / Escuro', async () => {
      const wrapper = await openAtStep(
        7,
        withLogo('plate', { enabled: false })
      );
      const preview = wrapper.find('[data-preview]');

      expect(preview.attributes('data-booking-theme')).toBe('light');
      await wrapper.find('[data-theme-option="dark"] input').setValue(true);
      expect(preview.attributes('data-booking-theme')).toBe('dark');
      expect(preview.classes()).toContain('bg-bk-page');
      expect(preview.find('[data-logo-box]').attributes('data-logo-dark')).toBe(
        'plate'
      );
    });
  });

  describe('passo 7, prévia e publicar', () => {
    it('mostra a prévia e a frase do funil com Alterar', async () => {
      const wrapper = await openAtStep(7);
      await flushPromises();
      expect(
        wrapper.find('[data-preview] [data-brand-header]').text()
      ).toContain('Conversa de vendas');
      const sentence = wrapper.find('[data-destination]').text();
      expect(sentence).toContain('BOOKING.PREVIEW.DESTINATION');
      expect(sentence).toContain('"pipeline":"Vendas"');
      expect(sentence).toContain('"stage":"Conversa agendada"');
      expect(sentence).toContain('"people":"Maria"');
      expect(wrapper.find('[data-alter]').exists()).toBe(true);
      expect(primary(wrapper).attributes('data-action')).toBe('PUBLISH');
    });

    it('Alterar troca funil e etapa por ChoiceSelect e salva', async () => {
      const wrapper = await openAtStep(7);
      await flushPromises();
      await wrapper.find('[data-alter]').trigger('click');
      const form = wrapper.find('[data-destination-form]');
      const [pipeline, stage] = form.findAllComponents(ChoiceSelect);
      expect(pipeline.props('options')).toEqual([
        { value: 3, label: 'Vendas' },
      ]);
      await stage.vm.$emit('update:modelValue', 31);
      await form.find('[data-destination-save]').trigger('click');
      await flushPromises();
      expect(BookingPagesAPI.update).toHaveBeenLastCalledWith(7, {
        default_pipeline_id: 3,
        default_stage_id: 31,
      });
    });

    it('publicação com pendências mostra o que falta e leva ao passo certo', async () => {
      BookingPagesAPI.publish.mockRejectedValue({
        response: {
          status: 422,
          data: { missing: ['host', 'working_hours'] },
        },
      });
      const wrapper = await openAtStep(7);
      await continueStep(wrapper);
      const items = wrapper
        .findAll('[data-missing-item]')
        .map(item => item.attributes('data-missing-item'));
      expect(items).toEqual(['host', 'working_hours']);
      expect(wrapper.find('[data-missing]').text()).toContain(
        'BOOKING.PREVIEW.MISSING.HOST'
      );
      expect(primary(wrapper).attributes('disabled')).toBeDefined();
      await wrapper.find('[data-fix="working_hours"]').trigger('click');
      expect(currentStep(wrapper)).toBe('QUANDO');
    });

    it('publicada: mostra link, QR code e Copiar link', async () => {
      BookingPagesAPI.publish.mockImplementation(() =>
        reply(fullPage({ enabled: true }))
      );
      const wrapper = await openAtStep(7);
      await continueStep(wrapper);
      expect(BookingPagesAPI.publish).toHaveBeenCalledWith(7);
      const published = wrapper.find('[data-published]');
      expect(published.find('[data-link-url]').text()).toBe(
        'https://chat.exemplo.com/book/abc'
      );
      expect(published.find('[data-copy]').exists()).toBe(true);
      expect(published.find('[data-qr-toggle]').exists()).toBe(true);
      expect(primary(wrapper).attributes('data-action')).toBe('DONE');
      expect(primary(wrapper).text()).toBe('BOOKING.WIZARD.DONE');
      await wrapper.setProps({ returnsElsewhere: true });
      expect(primary(wrapper).text()).toBe('BOOKING.WIZARD.BACK');
      await primary(wrapper).trigger('click');
      expect(wrapper.emitted('close')).toHaveLength(1);
    });

    it('publicada com um link por pessoa: um link para cada pessoa, sem o da página', async () => {
      BookingPagesAPI.publish.mockImplementation(() =>
        reply(
          fullPage({
            enabled: true,
            assignment_mode: 'per_agent',
            public_url: null,
            links: [
              {
                agent_id: 11,
                agent_name: 'Bia',
                url: 'https://chat.exemplo.com/book/bia',
                enabled: true,
              },
            ],
          })
        )
      );
      const wrapper = await openAtStep(7);
      await continueStep(wrapper);
      const published = wrapper.find('[data-published]');
      expect(published.text()).not.toContain('/book/abc');
      expect(published.findAll('[data-person-link]')).toHaveLength(1);
      expect(published.find('[data-link-url]').text()).toBe(
        'https://chat.exemplo.com/book/bia'
      );
    });

    it('falta de funil: Resolver abre o Alterar e salvar libera o Publicar', async () => {
      BookingPagesAPI.publish.mockRejectedValue({
        response: { status: 422, data: { missing: ['pipeline'] } },
      });
      const wrapper = await openAtStep(7);
      await flushPromises();
      await continueStep(wrapper);
      expect(wrapper.find('[data-missing]').text()).toContain(
        'BOOKING.PREVIEW.MISSING.PIPELINE'
      );
      expect(primary(wrapper).attributes('disabled')).toBeDefined();
      await wrapper.find('[data-fix="pipeline"]').trigger('click');
      await flushPromises();
      expect(currentStep(wrapper)).toBe('PREVIA');
      const form = wrapper.find('[data-destination-form]');
      expect(form.exists()).toBe(true);
      await form.find('[data-destination-save]').trigger('click');
      await flushPromises();
      expect(wrapper.find('[data-missing]').exists()).toBe(false);
      expect(primary(wrapper).attributes('disabled')).toBeUndefined();
    });

    it('pendência desconhecida não ganha Resolver nem tira a pessoa da prévia', async () => {
      BookingPagesAPI.publish.mockRejectedValue({
        response: { status: 422, data: { missing: ['outra_coisa'] } },
      });
      const wrapper = await openAtStep(7);
      await continueStep(wrapper);
      expect(wrapper.find('[data-missing-item="outra_coisa"]').exists()).toBe(
        true
      );
      expect(wrapper.find('[data-fix="outra_coisa"]').exists()).toBe(false);
      expect(currentStep(wrapper)).toBe('PREVIA');
    });

    it('abre direto na prévia quando o cartão pede Publicar', async () => {
      BookingPagesAPI.show.mockImplementation(() => reply(fullPage()));
      const wrapper = mount(BookingWizard, {
        props: { pageId: 7, initialStep: 7 },
      });
      await flushPromises();
      expect(currentStep(wrapper)).toBe('PREVIA');
      expect(primary(wrapper).attributes('data-action')).toBe('PUBLISH');
      expect(wrapper.find('[data-live-notice]').exists()).toBe(false);
    });
  });

  describe('página no ar, recusas do servidor e locais', () => {
    it('página no ar avisa no topo que a mudança vale na hora', async () => {
      const wrapper = await mountWizard(7, fullPage({ enabled: true }));
      expect(wrapper.find('[data-live-notice]').text()).toBe(
        'BOOKING.WIZARD.LIVE_NOTICE'
      );
    });

    it('caixa de agenda recusada (422) tem aviso próprio', async () => {
      BookingPagesAPI.update.mockRejectedValue({
        response: {
          status: 422,
          data: { error: 'crm.booking_v2.calendar_inbox_invalid' },
        },
      });
      const wrapper = await mountWizard();
      await continueStep(wrapper);
      expect(wrapper.find('[data-save-error]').text()).toBe(
        'BOOKING.WIZARD.SERVER_ERRORS.CALENDAR_GONE'
      );
    });

    it('pessoa recusada (422) tem aviso próprio', async () => {
      BookingPagesAPI.updatePeople.mockRejectedValue({
        response: {
          status: 422,
          data: { error: 'crm.booking_v2.people_invalid' },
        },
      });
      const wrapper = await mountWizard();
      await wrapper.find('[data-person="2"]').trigger('click');
      await continueStep(wrapper);
      expect(wrapper.find('[data-save-error]').text()).toBe(
        'BOOKING.WIZARD.SERVER_ERRORS.PEOPLE_GONE'
      );
      expect(currentStep(wrapper)).toBe('CONTE');
    });

    it('validação do servidor num campo vira aviso daquele assunto', async () => {
      BookingPagesAPI.update.mockRejectedValue({
        response: {
          status: 422,
          data: {
            error: 'Working hours invalid',
            errors: { working_hours: ['invalid working hours'] },
          },
        },
      });
      const wrapper = await mountWizard();
      await continueStep(wrapper);
      expect(wrapper.find('[data-save-error]').text()).toBe(
        'BOOKING.WIZARD.SERVER_ERRORS.HOURS'
      );
    });

    it('Meet com a caixa desconectada continua visível, com aviso, e dá para tirar', async () => {
      const page = fullPage({
        locations: [{ type: 'whatsapp_video' }, { type: 'google_meet' }],
        calendar_inbox_id: 11,
        calendar_options: [],
      });
      const wrapper = await openAtStep(3, page);
      const meet = wrapper.find('[data-location="google_meet"]');
      expect(meet.attributes('aria-pressed')).toBe('true');
      expect(wrapper.find('[data-disconnected="google_meet"]').text()).toBe(
        'BOOKING.WHERE.CALENDAR_DISCONNECTED'
      );
      expect(wrapper.find('[data-calendar]').exists()).toBe(false);
      await meet.trigger('click');
      expect(wrapper.find('[data-location="google_meet"]').exists()).toBe(
        false
      );
      await continueStep(wrapper);
      expect(lastPayload().locations).toEqual([{ type: 'whatsapp_video' }]);
    });

    it('local com rótulo salvo volta igual no PATCH', async () => {
      const page = fullPage({
        locations: [{ type: 'whatsapp_video', label: 'Vídeo rápido' }],
      });
      const wrapper = await openAtStep(3, page);
      await continueStep(wrapper);
      expect(lastPayload().locations).toEqual([
        { type: 'whatsapp_video', label: 'Vídeo rápido' },
      ]);
    });
  });

  describe('foco e leitor de tela', () => {
    it('ao trocar de passo o foco vai para o título do passo', async () => {
      BookingPagesAPI.show.mockImplementation(() => reply(fullPage()));
      const wrapper = mount(BookingWizard, {
        props: { pageId: 7 },
        attachTo: document.body,
      });
      await flushPromises();
      await continueStep(wrapper);
      expect(currentStep(wrapper)).toBe('ONDE');
      expect(document.activeElement.tagName).toBe('H2');
      expect(document.activeElement.textContent).toContain(
        'BOOKING.WHERE.TITLE'
      );
      wrapper.unmount();
    });

    it('com algo faltando o foco vai para o primeiro campo com problema', async () => {
      BookingPagesAPI.show.mockImplementation(() => reply(fullPage()));
      const wrapper = mount(BookingWizard, {
        props: { pageId: 7 },
        attachTo: document.body,
      });
      await flushPromises();
      await wrapper.find('[data-title] input').setValue('');
      await continueStep(wrapper);
      expect(document.activeElement).toBe(
        wrapper.find('[data-title] input').element
      );
      await wrapper.find('[data-title] input').setValue('Conversa');
      await wrapper.find('[data-person="1"]').trigger('click');
      await continueStep(wrapper);
      expect(wrapper.find('[data-people] + p[role="alert"]').exists()).toBe(
        true
      );
      expect(document.activeElement).toBe(
        wrapper.find('[data-person="1"]').element
      );
      wrapper.unmount();
    });

    it('passo feito é anunciado como concluído', async () => {
      const wrapper = await openAtStep(3);
      const done = wrapper.find('[data-step="CONTE"] [data-step-done]');
      expect(done.text()).toBe('BOOKING.STEPS.DONE');
      expect(done.classes()).toContain('sr-only');
      expect(wrapper.find('[data-step="ONDE"] [data-step-done]').exists()).toBe(
        false
      );
    });
  });
});
