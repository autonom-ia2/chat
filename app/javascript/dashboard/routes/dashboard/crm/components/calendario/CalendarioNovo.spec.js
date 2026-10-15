import { flushPromises, mount } from '@vue/test-utils';
import { defineComponent, h } from 'vue';
import CalendarioNovo from './CalendarioNovo.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => (params?.nome ? `${key}:${params.nome}` : key),
  }),
}));
const getCards = vi.fn();
vi.mock('dashboard/api/crmKanban', () => ({
  default: { getCards: (...args) => getCards(...args) },
}));
const searchContacts = vi.fn();
vi.mock('dashboard/api/contacts', () => ({
  default: { search: (...args) => searchContacts(...args) },
}));

// O Dialog real usa <dialog>.showModal(), que o jsdom não tem.
const DialogStub = defineComponent({
  name: 'DialogStub',
  props: {
    title: { type: String, default: '' },
    description: { type: String, default: '' },
  },
  setup(props, { slots, expose }) {
    expose({ open: () => {}, close: () => {} });
    return () =>
      h('div', [
        h('h3', props.title),
        h('p', props.description),
        slots.default?.(),
        slots.footer?.(),
      ]);
  },
});

const montar = (opcoes, extra = {}) =>
  mount(CalendarioNovo, {
    props: { opcoes, jeitoReuniao: 'pagina', ...extra },
    global: { stubs: { Dialog: DialogStub } },
  });

describe('CalendarioNovo', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    getCards.mockReset();
    searchContacts.mockReset();
    searchContacts.mockResolvedValue({ data: { payload: [] } });
  });
  afterEach(() => vi.useRealTimers());

  it('lembrete vai direto para o fluxo do lembrete', async () => {
    const wrapper = montar(['lembrete', 'reuniao']);
    await wrapper.find('[data-escolha="lembrete"]').trigger('click');

    expect(wrapper.emitted('escolher')[0][0]).toBe('lembrete');
  });

  it('reunião pergunta "Com quem?" e devolve o negócio mais recente do cliente', async () => {
    getCards.mockResolvedValue({
      data: {
        payload: [
          {
            id: 4,
            title: 'Plano anual',
            contact: { id: 7, name: 'Mariana Costa' },
          },
          {
            id: 2,
            title: 'Plano antigo',
            contact: { id: 7, name: 'Mariana Costa' },
          },
        ],
      },
    });
    searchContacts.mockResolvedValue({
      data: { payload: [{ id: 7, name: 'Mariana Costa' }] },
    });
    const wrapper = montar(['lembrete', 'reuniao']);
    await wrapper.find('[data-escolha="reuniao"]').trigger('click');

    expect(wrapper.text()).toContain('CRM_CALENDARIO.NOVO.COM_QUEM');
    expect(wrapper.emitted('escolher')).toBeUndefined();

    await wrapper.find('[data-com-quem-busca]').setValue('Ma');
    vi.advanceTimersByTime(400);
    await flushPromises();

    expect(getCards).toHaveBeenCalledWith({ search: 'Ma', per_page: 8 });
    expect(searchContacts).toHaveBeenCalledWith('Ma');
    // Uma linha por cliente.
    expect(wrapper.findAll('[data-com-quem]')).toHaveLength(1);
    const achado = wrapper.find('[data-com-quem="c7"]');
    expect(achado.text()).toContain('Mariana Costa');
    expect(achado.text()).toContain('Plano anual');
    await achado.trigger('click');

    expect(wrapper.emitted('escolher')[0]).toEqual(['reuniao', { cardId: 4 }]);
  });

  it('com uma letra só, não busca; sem resultado, diz isso; Voltar volta à escolha', async () => {
    getCards.mockResolvedValue({ data: { payload: [] } });
    const wrapper = montar(['lembrete', 'reuniao']);
    await wrapper.find('[data-escolha="reuniao"]').trigger('click');

    await wrapper.find('[data-com-quem-busca]').setValue('M');
    vi.advanceTimersByTime(400);
    await flushPromises();
    expect(getCards).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain('CRM_CALENDARIO.NOVO.BUSCA_DICA');

    await wrapper.find('[data-com-quem-busca]').setValue('Zé Ninguém');
    vi.advanceTimersByTime(400);
    await flushPromises();
    expect(wrapper.text()).toContain('CRM_CALENDARIO.NOVO.BUSCA_VAZIA');

    await wrapper.find('[data-com-quem-voltar]').trigger('click');
    expect(wrapper.find('[data-calendario-escolha]').exists()).toBe(true);
  });

  it('cliente sem negócio: explica com uma frase e oferece o lembrete', async () => {
    getCards.mockResolvedValue({ data: { payload: [] } });
    searchContacts.mockResolvedValue({
      data: { payload: [{ id: 8, name: 'Roberto Alves' }] },
    });
    const wrapper = montar(['lembrete', 'reuniao']);
    await wrapper.find('[data-escolha="reuniao"]').trigger('click');
    await wrapper.find('[data-com-quem-busca]').setValue('Rob');
    vi.advanceTimersByTime(400);
    await flushPromises();

    await wrapper.find('[data-com-quem="c8"]').trigger('click');
    expect(wrapper.emitted('escolher')).toBeUndefined();
    expect(wrapper.text()).toContain(
      'CRM_CALENDARIO.NOVO.SEM_NEGOCIO_TEXTO:Roberto Alves'
    );
    await wrapper.find('[data-sem-negocio-lembrete]').trigger('click');
    expect(wrapper.emitted('escolher')[0][0]).toBe('lembrete');
  });

  it('sem página nem agenda, o cartão da reunião diz o que falta e leva a criar a página', async () => {
    const wrapper = montar(['lembrete', 'reuniao'], {
      jeitoReuniao: 'falta',
      podeCriarPagina: true,
    });
    const cartao = wrapper.find('[data-escolha="reuniao"]');
    expect(cartao.text()).toContain('CRM_CALENDARIO.NOVO.FALTA_PAGINA');

    await wrapper.find('[data-criar-pagina]').trigger('click');
    expect(wrapper.emitted('criarPagina')).toHaveLength(1);
    expect(wrapper.find('[data-calendario-com-quem]').exists()).toBe(false);
  });

  it('sem permissão para criar a página, diz quem precisa criar e não mostra o botão', () => {
    const wrapper = montar(['lembrete', 'reuniao'], {
      jeitoReuniao: 'falta',
      podeCriarPagina: false,
    });

    expect(wrapper.find('[data-escolha="reuniao"]').text()).toContain(
      'CRM_CALENDARIO.NOVO.FALTA_PAGINA_SEM_PERMISSAO'
    );
    expect(wrapper.find('[data-criar-pagina]').exists()).toBe(false);
  });
});
