import { mount, flushPromises } from '@vue/test-utils';
import BookingPagesAPI from 'dashboard/api/crmBookingPages';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import BookingWizard from '../components/BookingWizard.vue';

// Assistente de seis passos (#1187, J3): cada passo, voltar sem perder,
// Meet/Teams só com caixa conectada e publicação com pendências.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
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
  },
}));
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

// Abre uma página existente e avança até o passo pedido (2 a 6).
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

    it('não mostra controles de aviso por WhatsApp (chegam na F2-A)', async () => {
      const wrapper = await openAtStep(5);
      expect(currentStep(wrapper)).toBe('CARA');
      expect(wrapper.text()).not.toContain('NOTICES');
      expect(wrapper.findAll('[data-color]')).toHaveLength(6);
      expect(primary(wrapper).attributes('data-action')).toBe('SEE_PREVIEW');
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
        photo
      );
      expect(wrapper.find('[data-photo] img').attributes('src')).toBe(
        'https://cdn.exemplo.com/foto.png'
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
      });
      expect(currentStep(wrapper)).toBe('PREVIA');
    });
  });

  describe('passo 6, prévia e publicar', () => {
    it('mostra a prévia e a frase do funil com Alterar', async () => {
      const wrapper = await openAtStep(6);
      await flushPromises();
      expect(wrapper.find('[data-preview-title]').text()).toBe(
        'Conversa de vendas'
      );
      const sentence = wrapper.find('[data-destination]').text();
      expect(sentence).toContain('BOOKING.PREVIEW.DESTINATION');
      expect(sentence).toContain('"pipeline":"Vendas"');
      expect(sentence).toContain('"stage":"Conversa agendada"');
      expect(sentence).toContain('"people":"Maria"');
      expect(wrapper.find('[data-alter]').exists()).toBe(true);
      expect(primary(wrapper).attributes('data-action')).toBe('PUBLISH');
    });

    it('Alterar troca funil e etapa por ChoiceSelect e salva', async () => {
      const wrapper = await openAtStep(6);
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
      const wrapper = await openAtStep(6);
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
      const wrapper = await openAtStep(6);
      await continueStep(wrapper);
      expect(BookingPagesAPI.publish).toHaveBeenCalledWith(7);
      const published = wrapper.find('[data-published]');
      expect(published.find('[data-link-url]').text()).toBe(
        'https://chat.exemplo.com/book/abc'
      );
      expect(published.find('[data-copy]').exists()).toBe(true);
      expect(published.find('[data-qr-toggle]').exists()).toBe(true);
      expect(primary(wrapper).attributes('data-action')).toBe('DONE');
      await primary(wrapper).trigger('click');
      expect(wrapper.emitted('close')).toHaveLength(1);
    });
  });
});
