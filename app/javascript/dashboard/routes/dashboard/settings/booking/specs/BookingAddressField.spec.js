import { mount, flushPromises } from '@vue/test-utils';
import BookingPagesAPI from 'dashboard/api/crmBookingPages';
import BookingAddressField from '../components/BookingAddressField.vue';
import BookingPageLinks from '../components/BookingPageLinks.vue';
import BookingWizard from '../components/BookingWizard.vue';
import { addressProblem, addressUrl, cleanAddress } from '../bookingAddress';
import { formToPayload, pageToForm, stepProblem } from '../bookingPageForm';
import { STEP } from '../constants';

// Endereço da página (#1282, #1299): o link curto `/a/<conta>/<página>` no
// assistente — link pronto e recolhido, "Mudar endereço" abre só a parte da
// página, o campo abre sozinho quando o endereço não serve, e endereço já
// salvo não muda com o nome do atendimento — e a lista de páginas usando o
// link curto que o servidor manda.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values) =>
      values === undefined ? key : `${key} ${JSON.stringify(values)}`,
  }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('shared/helpers/clipboard', () => ({ copyTextToClipboard: vi.fn() }));
vi.mock('dashboard/api/crmBookingPages', () => ({
  default: {
    shortName: vi.fn(),
    show: vi.fn(),
    update: vi.fn(),
    people: vi.fn(),
  },
}));

const HOST = window.location.host;
const reply = payload => Promise.resolve({ data: { payload } });

const mountField = (props = {}) =>
  mount(BookingAddressField, {
    props: {
      modelValue: '',
      title: '',
      pageId: 7,
      accountAddress: 'hub2you',
      savedName: '',
      ...props,
    },
    attachTo: document.body,
  });

// O componente é controlado: o que ele emite volta como `modelValue`.
const lastValue = wrapper => wrapper.emitted('update:modelValue')?.at(-1)?.[0];
const sync = wrapper => wrapper.setProps({ modelValue: lastValue(wrapper) });
const changeButton = wrapper => wrapper.find('[data-address-change]');
const field = wrapper => wrapper.find('[data-address-input]');
const preview = wrapper => wrapper.find('[data-address-preview]').text();
const openField = wrapper => changeButton(wrapper).trigger('click');
const type = async (wrapper, text) => {
  field(wrapper).element.value = text;
  await field(wrapper).trigger('input');
  await sync(wrapper);
};
const wait = async () => {
  vi.advanceTimersByTime(600);
  await flushPromises();
};
// Campo sem sugestão (o pedido fica pendurado), já aberto para digitar.
const mountOpen = async (props = {}) => {
  const wrapper = mountField({
    modelValue: 'rascunho',
    savedName: 'rascunho',
    ...props,
  });
  await openField(wrapper);
  return wrapper;
};

describe('bookingAddress', () => {
  it('limpa o que a pessoa digita: minúsculas, sem acento, espaço vira hífen', () => {
    expect(cleanAddress('Clínica Viva')).toBe('clinica-viva');
    expect(cleanAddress('Dr. João_Silva!')).toBe('dr-joao-silva');
    expect(cleanAddress('a/b?c=d')).toBe('abcd');
    expect(cleanAddress('x'.repeat(60))).toHaveLength(40);
    expect(cleanAddress(null)).toBe('');
  });

  it('diz o problema de formato, e vazio não é problema', () => {
    expect(addressProblem('')).toBeNull();
    expect(addressProblem('clinica-viva')).toBeNull();
    expect(addressProblem('ab')).toBe('too_short');
    expect(addressProblem('a'.repeat(41))).toBe('too_long');
    expect(addressProblem('Clinica')).toBe('invalid_chars');
    expect(addressProblem('-clinica')).toBe('hyphen_edge');
    expect(addressProblem('clinica-')).toBe('hyphen_edge');
  });

  it('monta o link curto com a conta antes da página', () => {
    expect(addressUrl('seguro-viagem', 'hub2you', 'chat.exemplo.com')).toBe(
      'chat.exemplo.com/a/hub2you/seguro-viagem'
    );
  });

  it('o formulário leva e traz o endereço, e trava o passo se ele estiver errado', () => {
    const form = pageToForm({ title: 'Consulta', short_name: 'consulta' });
    expect(form.shortName).toBe('consulta');
    expect(formToPayload(form).short_name).toBe('consulta');
    expect(pageToForm({ title: 'Consulta' }).shortName).toBe('');

    const people = { peopleIds: [1] };
    expect(stepProblem(STEP.CONTE, { ...form, ...people })).toBeNull();
    expect(
      stepProblem(STEP.CONTE, { ...form, ...people, shortName: 'ab' })
    ).toBe('SHORT_NAME');
    expect(
      stepProblem(STEP.CONTE, { ...form, ...people, shortName: '' })
    ).toBeNull();
  });
});

describe('BookingAddressField', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    BookingPagesAPI.shortName.mockReset();
    BookingPagesAPI.shortName.mockImplementation(() => new Promise(() => {}));
  });
  afterEach(() => {
    vi.useRealTimers();
    document.body.innerHTML = '';
  });

  describe('recolhido por padrão', () => {
    it('mostra só o link pronto e o botão "Mudar endereço", sem campo de texto', async () => {
      BookingPagesAPI.shortName.mockImplementation(() =>
        reply({ suggestion: 'seguro-viagem' })
      );
      const wrapper = mountField({ title: 'Seguro Viagem' });
      expect(preview(wrapper)).toBe('BOOKING.ADDRESS.CHECKING');

      await flushPromises();
      await sync(wrapper);

      expect(BookingPagesAPI.shortName).toHaveBeenCalledWith({
        title: 'Seguro Viagem',
        pageId: 7,
      });
      expect(lastValue(wrapper)).toBe('seguro-viagem');
      expect(preview(wrapper)).toContain(`${HOST}/a/hub2you/seguro-viagem`);
      expect(field(wrapper).exists()).toBe(false);
      expect(wrapper.find('[data-address-status]').exists()).toBe(false);
      expect(changeButton(wrapper).text()).toBe('BOOKING.ADDRESS.CHANGE');
      expect(changeButton(wrapper).attributes('aria-expanded')).toBe('false');
      expect(changeButton(wrapper).attributes('aria-controls')).toBeUndefined();
    });

    it('o botão é um botão de verdade, com alvo de toque de 44 px', () => {
      const button = changeButton(mountField());

      expect(button.element.tagName).toBe('BUTTON');
      expect(button.attributes('type')).toBe('button');
      expect(button.classes()).toContain('min-h-11');
    });

    it('não confere de novo o endereço que o servidor acabou de sugerir', async () => {
      BookingPagesAPI.shortName.mockImplementation(({ title }) =>
        title === undefined
          ? reply({ available: false, problem: 'taken' })
          : reply({ suggestion: 'seguro-viagem' })
      );
      const wrapper = mountField({ title: 'Seguro Viagem' });
      await flushPromises();
      await sync(wrapper);
      await wait();

      expect(BookingPagesAPI.shortName).toHaveBeenCalledTimes(1);
      expect(field(wrapper).exists()).toBe(false);
    });

    it('página antiga sem endereço recebe a sugestão, recolhida, mesmo sem nome do atendimento', async () => {
      BookingPagesAPI.shortName.mockImplementation(() =>
        reply({ suggestion: 'agenda' })
      );
      const wrapper = mountField({ title: '', savedName: '' });
      await flushPromises();
      await sync(wrapper);

      expect(BookingPagesAPI.shortName).toHaveBeenCalledWith({
        title: '',
        pageId: 7,
      });
      expect(lastValue(wrapper)).toBe('agenda');
      expect(preview(wrapper)).toContain(`${HOST}/a/hub2you/agenda`);
      expect(field(wrapper).exists()).toBe(false);
    });
  });

  describe('"Mudar endereço"', () => {
    it('abre só a parte da página, com a parte da conta fixa antes do campo, e leva o foco para o campo', async () => {
      BookingPagesAPI.shortName.mockImplementation(() =>
        reply({ suggestion: 'seguro-viagem' })
      );
      const wrapper = mountField({ title: 'Seguro Viagem' });
      await flushPromises();
      await sync(wrapper);

      await openField(wrapper);
      await flushPromises();

      expect(changeButton(wrapper).attributes('aria-expanded')).toBe('true');
      expect(changeButton(wrapper).attributes('aria-controls')).toBe(
        wrapper.find('[data-address-panel]').attributes('id')
      );
      expect(field(wrapper).element.value).toBe('seguro-viagem');
      expect(wrapper.find('[data-address-prefix]').text()).toBe('…/a/hub2you/');
      expect(document.activeElement).toBe(field(wrapper).element);
      expect(field(wrapper).attributes('aria-describedby')).toContain(
        wrapper.find('[data-address-prefix]').attributes('id')
      );
      expect(wrapper.find('[data-address-status]').text()).toBe(
        'BOOKING.ADDRESS.FREE'
      );
    });

    it('abre e fecha pelo teclado como qualquer botão, e fica como a pessoa deixou', async () => {
      const wrapper = mountField({
        modelValue: 'clinica-viva',
        savedName: 'clinica-viva',
      });

      await openField(wrapper);
      expect(field(wrapper).exists()).toBe(true);
      await wrapper.setProps({ title: 'Outro nome' });
      await wait();
      expect(field(wrapper).exists()).toBe(true);

      await openField(wrapper);
      expect(field(wrapper).exists()).toBe(false);
      expect(changeButton(wrapper).attributes('aria-expanded')).toBe('false');
    });

    it('não recolhe enquanto o endereço tem problema', async () => {
      const wrapper = await mountOpen();

      await type(wrapper, 'ab');
      await openField(wrapper);

      expect(field(wrapper).exists()).toBe(true);
      expect(wrapper.find('[data-address-problem]').text()).toBe(
        'BOOKING.ADDRESS.PROBLEMS.TOO_SHORT'
      );
    });
  });

  describe('abre sozinho só quando precisa', () => {
    it('quando o servidor recusa o endereço ao salvar', async () => {
      const wrapper = mountField({
        modelValue: 'seguro-viagem',
        savedName: '',
      });
      expect(field(wrapper).exists()).toBe(false);

      await wrapper.setProps({ error: 'Este endereço não pode ser usado.' });

      expect(field(wrapper).exists()).toBe(true);
      expect(changeButton(wrapper).attributes('aria-expanded')).toBe('true');
      expect(wrapper.find('[data-address-problem]').text()).toBe(
        'Este endereço não pode ser usado.'
      );
      expect(field(wrapper).attributes('aria-invalid')).toBe('true');
    });

    it('o aviso de fora some quando a pessoa troca o endereço recusado, e o campo continua aberto', async () => {
      BookingPagesAPI.shortName.mockImplementation(() =>
        reply({ available: true, problem: null })
      );
      const wrapper = mountField({
        modelValue: 'seguro-viagem',
        error: 'Este endereço não pode ser usado.',
      });

      await type(wrapper, 'seguro-viagem-2');
      await wait();

      expect(wrapper.find('[data-address-problem]').exists()).toBe(false);
      expect(wrapper.find('[data-address-status]').text()).toBe(
        'BOOKING.ADDRESS.FREE'
      );
      expect(field(wrapper).exists()).toBe(true);
    });

    it('quando a conferência diz que o endereço não serve', async () => {
      BookingPagesAPI.shortName.mockImplementation(() =>
        reply({ available: false, problem: 'taken' })
      );
      const wrapper = mountField({ modelValue: 'seguro-viagem' });
      expect(field(wrapper).exists()).toBe(false);

      await wait();

      expect(field(wrapper).exists()).toBe(true);
      expect(wrapper.find('[data-address-problem]').text()).toBe(
        'BOOKING.ADDRESS.PROBLEMS.TAKEN'
      );
    });

    it('quando não vem sugestão nenhuma, para a pessoa escrever', async () => {
      BookingPagesAPI.shortName.mockRejectedValue(new Error('rede'));
      const wrapper = mountField({ title: 'Seguro Viagem' });

      await flushPromises();

      expect(field(wrapper).exists()).toBe(true);
      expect(preview(wrapper)).toBe('BOOKING.ADDRESS.EMPTY');
    });

    it('continua recolhido quando está tudo certo', async () => {
      BookingPagesAPI.shortName.mockImplementation(() =>
        reply({ available: true, problem: null })
      );
      const wrapper = mountField({ modelValue: 'seguro-viagem' });

      await wait();

      expect(field(wrapper).exists()).toBe(false);
    });
  });

  describe('endereço e nome do atendimento', () => {
    it('página nova: acompanha o nome enquanto a pessoa não mexe no endereço, e para quando ela mexe', async () => {
      BookingPagesAPI.shortName.mockImplementation(({ title }) => {
        if (title === undefined) return reply({ available: true });
        return reply({
          suggestion: title === 'Consulta' ? 'consulta' : 'avaliacao',
        });
      });
      const wrapper = mountField({ title: 'Avaliação' });
      await flushPromises();
      await sync(wrapper);
      expect(lastValue(wrapper)).toBe('avaliacao');

      await wrapper.setProps({ title: 'Consulta' });
      await wait();
      await sync(wrapper);
      expect(lastValue(wrapper)).toBe('consulta');
      expect(field(wrapper).exists()).toBe(false);

      await openField(wrapper);
      await type(wrapper, 'meu-endereco');
      await wait();
      const calls = BookingPagesAPI.shortName.mock.calls.length;
      await wrapper.setProps({ title: 'Outro nome' });
      await wait();
      expect(
        BookingPagesAPI.shortName.mock.calls
          .slice(calls)
          .some(([arg]) => arg.title !== undefined)
      ).toBe(false);
      expect(lastValue(wrapper)).toBe('meu-endereco');
    });

    it('espera a pessoa parar de digitar o nome e ignora a sugestão de um nome já trocado', async () => {
      const answers = [];
      BookingPagesAPI.shortName.mockImplementation(
        () =>
          new Promise(resolve => {
            answers.push(resolve);
          })
      );
      const wrapper = mountField({ title: 'A' });

      await wrapper.setProps({ title: 'Av' });
      await wrapper.setProps({ title: 'Avaliação' });
      await wait();
      expect(BookingPagesAPI.shortName).toHaveBeenCalledTimes(2);

      answers[1]({ data: { payload: { suggestion: 'avaliacao' } } });
      await flushPromises();
      answers[0]({ data: { payload: { suggestion: 'agenda-a' } } });
      await flushPromises();
      expect(lastValue(wrapper)).toBe('avaliacao');
    });

    it('página que já tem endereço: mostra o dela, recolhido, e trocar o nome do atendimento não troca o endereço', async () => {
      const wrapper = mountField({
        modelValue: 'clinica-viva',
        savedName: 'clinica-viva',
        title: 'Consulta',
      });
      await wait();

      await wrapper.setProps({ title: 'Outro nome de atendimento' });
      await wait();

      expect(BookingPagesAPI.shortName).not.toHaveBeenCalled();
      expect(wrapper.emitted('update:modelValue')).toBeUndefined();
      expect(preview(wrapper)).toContain(`${HOST}/a/hub2you/clinica-viva`);
      expect(field(wrapper).exists()).toBe(false);
      expect(wrapper.find('[data-address-warning]').exists()).toBe(false);

      await openField(wrapper);
      expect(wrapper.find('[data-address-status]').text()).toBe(
        'BOOKING.ADDRESS.OWN'
      );
    });
  });

  describe('com o campo aberto', () => {
    it('mostra o link ao vivo, já limpo, e diz que o endereço está livre', async () => {
      const wrapper = await mountOpen();
      BookingPagesAPI.shortName.mockImplementation(() =>
        reply({ name: 'clinica-viva', available: true, problem: null })
      );

      await type(wrapper, '');
      expect(preview(wrapper)).toBe('BOOKING.ADDRESS.EMPTY');
      await type(wrapper, 'Clínica Viva');
      expect(field(wrapper).element.value).toBe('clinica-viva');
      expect(preview(wrapper)).toContain(`${HOST}/a/hub2you/clinica-viva`);
      expect(wrapper.find('[data-address-status]').text()).toBe(
        'BOOKING.ADDRESS.CHECKING'
      );

      await wait();
      expect(BookingPagesAPI.shortName).toHaveBeenCalledWith({
        name: 'clinica-viva',
        pageId: 7,
      });
      expect(wrapper.find('[data-address-status]').text()).toBe(
        'BOOKING.ADDRESS.FREE'
      );
      expect(wrapper.find('[role="status"]').attributes('aria-live')).toBe(
        'polite'
      );
    });

    it('diz em texto simples quando outra página já usa o endereço ou ele é do sistema', async () => {
      const wrapper = await mountOpen();
      BookingPagesAPI.shortName.mockImplementation(({ name }) =>
        reply({
          name,
          available: false,
          problem: name === 'admin' ? 'reserved' : 'taken',
        })
      );

      await type(wrapper, 'clinica-viva');
      await wait();
      expect(wrapper.find('[data-address-problem]').text()).toBe(
        'BOOKING.ADDRESS.PROBLEMS.TAKEN'
      );
      expect(field(wrapper).attributes('aria-invalid')).toBe('true');

      await type(wrapper, 'admin');
      await wait();
      expect(wrapper.find('[data-address-problem]').text()).toBe(
        'BOOKING.ADDRESS.PROBLEMS.RESERVED'
      );
    });

    it('acusa o formato na hora, sem perguntar ao servidor', async () => {
      const wrapper = await mountOpen();

      await type(wrapper, 'ab');
      await wait();
      expect(wrapper.find('[data-address-problem]').text()).toBe(
        'BOOKING.ADDRESS.PROBLEMS.TOO_SHORT'
      );
      expect(BookingPagesAPI.shortName).not.toHaveBeenCalled();
    });

    it('pergunta uma vez só depois que a pessoa para de digitar, e ignora resposta de nome já trocado', async () => {
      const answers = [];
      const wrapper = await mountOpen();
      BookingPagesAPI.shortName.mockImplementation(
        () =>
          new Promise(resolve => {
            answers.push(resolve);
          })
      );

      await type(wrapper, 'clini');
      await type(wrapper, 'clinica');
      await wait();
      expect(BookingPagesAPI.shortName).toHaveBeenCalledTimes(1);

      await type(wrapper, 'clinica-viva');
      await wait();
      answers[0]({ data: { payload: { available: false, problem: 'taken' } } });
      await flushPromises();
      expect(wrapper.find('[data-address-problem]').exists()).toBe(false);

      answers[1]({ data: { payload: { available: true, problem: null } } });
      await flushPromises();
      expect(wrapper.find('[data-address-status]').text()).toBe(
        'BOOKING.ADDRESS.FREE'
      );
    });

    it('não afirma nada quando o servidor não responde', async () => {
      const wrapper = await mountOpen();
      BookingPagesAPI.shortName.mockRejectedValue(new Error('rede'));

      await type(wrapper, 'clinica-viva');
      await wait();
      expect(wrapper.find('[data-address-status]').exists()).toBe(false);
      expect(wrapper.find('[data-address-problem]').exists()).toBe(false);
    });

    it('avisa que o link antigo para de abrir quando a pessoa muda o endereço, mesmo depois de recolher', async () => {
      const wrapper = await mountOpen({
        modelValue: 'clinica-viva',
        savedName: 'clinica-viva',
      });
      BookingPagesAPI.shortName.mockImplementation(() =>
        reply({ available: true, problem: null })
      );

      await type(wrapper, 'clinica-nova');
      await wait();
      expect(wrapper.find('[data-address-warning]').text()).toBe(
        'BOOKING.ADDRESS.CHANGE_WARNING'
      );

      await openField(wrapper);
      expect(field(wrapper).exists()).toBe(false);
      expect(wrapper.find('[data-address-warning]').exists()).toBe(true);
    });
  });
});

describe('endereço no assistente', () => {
  const page = (extra = {}) => ({
    id: 7,
    title: 'Seguro Viagem',
    enabled: true,
    account_address: 'hub2you',
    short_name: 'seguro-viagem',
    duration_minutes: 30,
    slot_durations: [],
    locations: [{ type: 'whatsapp_video' }],
    working_hours: { start_hour: 9, end_hour: 17, weekdays: [1, 2, 3, 4, 5] },
    brand: {},
    people: [{ id: 1, name: 'Maria' }],
    ...extra,
  });

  const mountWizard = async saved => {
    BookingPagesAPI.show.mockImplementation(() => reply(saved));
    BookingPagesAPI.people.mockImplementation(() =>
      reply([{ id: 1, name: 'Maria' }])
    );
    const wrapper = mount(BookingWizard, { props: { pageId: 7 } });
    await flushPromises();
    return wrapper;
  };
  const continueStep = async wrapper => {
    await wrapper.find('[data-primary]').trigger('click');
    await flushPromises();
  };

  beforeEach(() => {
    vi.clearAllMocks();
    BookingPagesAPI.shortName.mockImplementation(() =>
      reply({ suggestion: 'seguro-viagem' })
    );
  });

  it('trocar o nome do atendimento de uma página publicada salva o nome novo com o MESMO endereço', async () => {
    BookingPagesAPI.update.mockImplementation(() => reply(page()));
    const wrapper = await mountWizard(page());

    expect(wrapper.find('[data-address-preview]').text()).toContain(
      `${HOST}/a/hub2you/seguro-viagem`
    );
    expect(wrapper.find('[data-address-input]').exists()).toBe(false);

    await wrapper.find('[data-title] input').setValue('Seguro de Vida');
    await flushPromises();
    await continueStep(wrapper);

    expect(BookingPagesAPI.shortName).not.toHaveBeenCalled();
    expect(BookingPagesAPI.update.mock.calls.at(-1)[1]).toMatchObject({
      title: 'Seguro de Vida',
      short_name: 'seguro-viagem',
    });
  });

  it('página antiga sem endereço: recebe a sugestão, recolhida, e só grava ao salvar o passo', async () => {
    BookingPagesAPI.update.mockImplementation(() => reply(page()));
    const wrapper = await mountWizard(page({ short_name: null }));

    expect(wrapper.find('[data-address-preview]').text()).toContain(
      `${HOST}/a/hub2you/seguro-viagem`
    );
    expect(wrapper.find('[data-address-input]').exists()).toBe(false);
    expect(BookingPagesAPI.update).not.toHaveBeenCalled();

    await continueStep(wrapper);

    expect(BookingPagesAPI.update.mock.calls.at(-1)[1].short_name).toBe(
      'seguro-viagem'
    );
  });

  it('abre o campo quando o servidor recusa o endereço ao salvar, com o motivo junto do campo', async () => {
    BookingPagesAPI.update.mockRejectedValue({
      response: { data: { errors: { short_name: ['taken'] } } },
    });
    const wrapper = await mountWizard(page({ short_name: null }));
    expect(wrapper.find('[data-address-input]').exists()).toBe(false);

    await continueStep(wrapper);

    expect(wrapper.find('[data-address-input]').exists()).toBe(true);
    expect(wrapper.find('[data-address-prefix]').text()).toBe('…/a/hub2you/');
    expect(wrapper.find('[data-address-problem]').text()).toBe(
      'BOOKING.WIZARD.SERVER_ERRORS.SHORT_NAME'
    );
    expect(wrapper.find('[data-save-error]').text()).toBe(
      'BOOKING.WIZARD.SERVER_ERRORS.SHORT_NAME'
    );
  });

  it('não abre o campo quando o servidor recusa outra coisa', async () => {
    BookingPagesAPI.update.mockRejectedValue({
      response: { data: { errors: { working_hours: ['invalid'] } } },
    });
    const wrapper = await mountWizard(page());

    await continueStep(wrapper);

    expect(wrapper.find('[data-save-error]').exists()).toBe(true);
    expect(wrapper.find('[data-address-input]').exists()).toBe(false);
  });
});

describe('lista de páginas com link curto', () => {
  it('mostra, abre e copia o link curto que o servidor manda', () => {
    const wrapper = mount(BookingPageLinks, {
      props: {
        page: { public_url: 'https://chat.exemplo.com/a/hub2you/clinica-viva' },
      },
    });

    expect(wrapper.find('[data-link-url]').text()).toBe(
      'https://chat.exemplo.com/a/hub2you/clinica-viva'
    );
    expect(wrapper.find('[data-open]').attributes('href')).toBe(
      'https://chat.exemplo.com/a/hub2you/clinica-viva'
    );
  });

  it('página com um link por pessoa: um link curto por pessoa', () => {
    const wrapper = mount(BookingPageLinks, {
      props: {
        page: {
          public_url: null,
          links: [
            {
              agent_id: 11,
              agent_name: 'Bia',
              url: 'https://chat.exemplo.com/a/hub2you/clinica-viva/bia',
            },
            {
              agent_id: 12,
              agent_name: 'Caio',
              url: 'https://chat.exemplo.com/a/hub2you/clinica-viva/caio',
            },
          ],
        },
      },
    });

    const urls = wrapper
      .findAll('[data-person-link] [data-link-url]')
      .map(node => node.text());
    expect(urls).toEqual([
      'https://chat.exemplo.com/a/hub2you/clinica-viva/bia',
      'https://chat.exemplo.com/a/hub2you/clinica-viva/caio',
    ]);
  });
});
