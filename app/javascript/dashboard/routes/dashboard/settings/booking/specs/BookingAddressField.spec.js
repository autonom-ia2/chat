import { mount, flushPromises } from '@vue/test-utils';
import BookingPagesAPI from 'dashboard/api/crmBookingPages';
import BookingAddressField from '../components/BookingAddressField.vue';
import BookingPageLinks from '../components/BookingPageLinks.vue';
import { addressProblem, addressUrl, cleanAddress } from '../bookingAddress';
import { formToPayload, pageToForm, stepProblem } from '../bookingPageForm';
import { STEP } from '../constants';

// Endereço da página (#1282): o link curto `/a/<nome>` no assistente —
// sugestão a partir do nome, link ao vivo, endereço livre ou não em texto — e
// a lista de páginas usando o link curto que o servidor manda.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values) =>
      values === undefined ? key : `${key} ${JSON.stringify(values)}`,
  }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('shared/helpers/clipboard', () => ({ copyTextToClipboard: vi.fn() }));
vi.mock('dashboard/api/crmBookingPages', () => ({
  default: { shortName: vi.fn() },
}));

const reply = payload => Promise.resolve({ data: { payload } });

const mountField = (props = {}) =>
  mount(BookingAddressField, {
    props: { modelValue: '', title: '', pageId: 7, savedName: '', ...props },
  });

// O componente é controlado: o que ele emite volta como `modelValue`.
const lastValue = wrapper => wrapper.emitted('update:modelValue')?.at(-1)?.[0];
const type = async (wrapper, text) => {
  const input = wrapper.find('[data-address-input]');
  input.element.value = text;
  await input.trigger('input');
  await wrapper.setProps({ modelValue: lastValue(wrapper) });
};
const wait = async () => {
  vi.advanceTimersByTime(600);
  await flushPromises();
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

  it('monta o link curto', () => {
    expect(addressUrl('clinica-viva', 'chat.exemplo.com')).toBe(
      'chat.exemplo.com/a/clinica-viva'
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
  });
  afterEach(() => vi.useRealTimers());

  it('sugere o endereço a partir do nome do atendimento', async () => {
    BookingPagesAPI.shortName.mockImplementation(() =>
      reply({ suggestion: 'avaliacao-gratuita' })
    );
    const wrapper = mountField({ title: 'Avaliação gratuita' });
    await flushPromises();

    expect(BookingPagesAPI.shortName).toHaveBeenCalledWith({
      title: 'Avaliação gratuita',
      pageId: 7,
    });
    expect(lastValue(wrapper)).toBe('avaliacao-gratuita');
  });

  it('acompanha o nome enquanto a pessoa não mexe no endereço, e para quando ela mexe', async () => {
    BookingPagesAPI.shortName.mockImplementation(({ title }) =>
      title ? reply({ suggestion: 'consulta' }) : reply({ available: true })
    );
    const wrapper = mountField({ title: 'Avaliação' });
    await flushPromises();
    await wrapper.setProps({ modelValue: lastValue(wrapper) });

    await wrapper.setProps({ title: 'Consulta' });
    await wait();
    expect(lastValue(wrapper)).toBe('consulta');

    await type(wrapper, 'meu-endereco');
    await wait();
    const calls = BookingPagesAPI.shortName.mock.calls.length;
    await wrapper.setProps({ title: 'Outro nome' });
    await wait();
    expect(
      BookingPagesAPI.shortName.mock.calls
        .slice(calls)
        .some(([arg]) => arg.title)
    ).toBe(false);
    expect(lastValue(wrapper)).toBe('meu-endereco');
  });

  it('não sugere por cima do endereço que a página já tem', async () => {
    const wrapper = mountField({
      modelValue: 'clinica-viva',
      savedName: 'clinica-viva',
      title: 'Outro nome',
    });
    await wait();

    expect(BookingPagesAPI.shortName).not.toHaveBeenCalled();
    expect(wrapper.find('[data-address-status]').text()).toBe(
      'BOOKING.ADDRESS.OWN'
    );
    expect(wrapper.find('[data-address-warning]').exists()).toBe(false);
  });

  it('mostra o link ao vivo, já limpo, e diz que o endereço está livre', async () => {
    BookingPagesAPI.shortName.mockImplementation(() =>
      reply({ name: 'clinica-viva', available: true, problem: null })
    );
    const wrapper = mountField();

    expect(wrapper.find('[data-address-preview]').text()).toBe(
      'BOOKING.ADDRESS.EMPTY'
    );
    await type(wrapper, 'Clínica Viva');
    expect(wrapper.find('[data-address-input]').element.value).toBe(
      'clinica-viva'
    );
    expect(wrapper.find('[data-address-preview]').text()).toContain(
      `${window.location.host}/a/clinica-viva`
    );
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

  it('diz em texto simples quando o endereço já tem dono ou é do sistema', async () => {
    BookingPagesAPI.shortName.mockImplementation(({ name }) =>
      reply({
        name,
        available: false,
        problem: name === 'admin' ? 'reserved' : 'taken',
      })
    );
    const wrapper = mountField();

    await type(wrapper, 'clinica-viva');
    await wait();
    expect(wrapper.find('[data-address-problem]').text()).toBe(
      'BOOKING.ADDRESS.PROBLEMS.TAKEN'
    );
    expect(
      wrapper.find('[data-address-input]').attributes('aria-invalid')
    ).toBe('true');

    await type(wrapper, 'admin');
    await wait();
    expect(wrapper.find('[data-address-problem]').text()).toBe(
      'BOOKING.ADDRESS.PROBLEMS.RESERVED'
    );
  });

  it('acusa o formato na hora, sem perguntar ao servidor', async () => {
    const wrapper = mountField();

    await type(wrapper, 'ab');
    await wait();
    expect(wrapper.find('[data-address-problem]').text()).toBe(
      'BOOKING.ADDRESS.PROBLEMS.TOO_SHORT'
    );
    expect(BookingPagesAPI.shortName).not.toHaveBeenCalled();
  });

  it('pergunta uma vez só depois que a pessoa para de digitar, e ignora resposta de nome já trocado', async () => {
    const answers = [];
    BookingPagesAPI.shortName.mockImplementation(
      () =>
        new Promise(resolve => {
          answers.push(resolve);
        })
    );
    const wrapper = mountField();

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
    BookingPagesAPI.shortName.mockRejectedValue(new Error('rede'));
    const wrapper = mountField();

    await type(wrapper, 'clinica-viva');
    await wait();
    expect(wrapper.find('[data-address-status]').exists()).toBe(false);
    expect(wrapper.find('[data-address-problem]').exists()).toBe(false);
  });

  it('avisa que o link antigo para de abrir quando a pessoa muda o endereço', async () => {
    BookingPagesAPI.shortName.mockImplementation(() =>
      reply({ available: true, problem: null })
    );
    const wrapper = mountField({
      modelValue: 'clinica-viva',
      savedName: 'clinica-viva',
    });

    await type(wrapper, 'clinica-nova');
    expect(wrapper.find('[data-address-warning]').text()).toBe(
      'BOOKING.ADDRESS.CHANGE_WARNING'
    );
  });

  it('mostra o erro que veio de fora (o passo não deixou continuar)', () => {
    const wrapper = mountField({ error: 'Confira o endereço da página.' });

    expect(wrapper.find('[data-address-problem]').text()).toBe(
      'Confira o endereço da página.'
    );
  });
});

describe('lista de páginas com link curto', () => {
  it('mostra, abre e copia o link curto que o servidor manda', () => {
    const wrapper = mount(BookingPageLinks, {
      props: {
        page: { public_url: 'https://chat.exemplo.com/a/clinica-viva' },
      },
    });

    expect(wrapper.find('[data-link-url]').text()).toBe(
      'https://chat.exemplo.com/a/clinica-viva'
    );
    expect(wrapper.find('[data-open]').attributes('href')).toBe(
      'https://chat.exemplo.com/a/clinica-viva'
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
              url: 'https://chat.exemplo.com/a/clinica-viva/bia',
            },
            {
              agent_id: 12,
              agent_name: 'Caio',
              url: 'https://chat.exemplo.com/a/clinica-viva/caio',
            },
          ],
        },
      },
    });

    const urls = wrapper
      .findAll('[data-person-link] [data-link-url]')
      .map(node => node.text());
    expect(urls).toEqual([
      'https://chat.exemplo.com/a/clinica-viva/bia',
      'https://chat.exemplo.com/a/clinica-viva/caio',
    ]);
  });
});
