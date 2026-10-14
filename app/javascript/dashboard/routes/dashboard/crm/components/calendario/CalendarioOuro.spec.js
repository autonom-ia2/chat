import { flushPromises, mount } from '@vue/test-utils';
import { defineComponent, h, ref } from 'vue';
import CalendarioOuro from './CalendarioOuro.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => (params ? `${key}:${JSON.stringify(params)}` : key),
    locale: ref('pt_BR'),
  }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    currentAccount: ref({ timezone: 'America/Sao_Paulo' }),
  }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ getters: { getCurrentUser: { name: 'Ana Souza' } } }),
}));

const abriuEscolha = vi.fn();
const NovoStub = defineComponent({
  name: 'CalendarioNovo',
  props: { opcoes: { type: Array, default: () => [] } },
  setup(props, { expose }) {
    expose({ open: abriuEscolha });
    return () => h('div', { 'data-opcoes': props.opcoes.join(',') });
  },
});

const EVENTOS = [
  {
    id: 'follow_up_1',
    event_type: 'follow_up_reminder_only',
    title: 'Ligar para o Roberto',
    starts_at: '2026-10-13T13:00:00Z',
    status: 'pending',
    contact_id: 10,
    contact_name: 'Roberto Alves',
    contact_phone: '+5511944443333',
    assignee_id: 1,
  },
  {
    id: 'follow_up_2',
    event_type: 'follow_up_reminder_only',
    title: 'Da Paula',
    starts_at: '2026-10-14T19:30:00Z',
    status: 'pending',
    card_id: 3,
    assignee_id: 2,
    conversation_display_id: 7,
  },
  {
    id: 'expected_close_4',
    event_type: 'expected_close',
    title: 'Plano anual',
    starts_at: '2026-10-14T00:00:00Z',
    all_day: true,
    date: '2026-10-14',
    card_id: 4,
  },
];

const montar = (props = {}) =>
  mount(CalendarioOuro, {
    props: {
      events: EVENTOS,
      currentUserId: 1,
      owners: [{ id: 2, name: 'Paula Nunes' }],
      ehAdmin: true,
      ...props,
    },
    global: {
      stubs: { CalendarioNovo: NovoStub, ChoiceSelect: true },
    },
  });

describe('CalendarioOuro', () => {
  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date('2026-10-14T18:00:00Z'));
    abriuEscolha.mockClear();
  });
  afterEach(() => vi.useRealTimers());

  it('abre no Meu dia: atrasado, hoje com o dia todo, e pede a janela no fuso da conta', async () => {
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.find('[data-secao="atrasados"]').text()).toContain(
      'Ligar para o Roberto'
    );
    const hoje = wrapper.find('[data-secao="dia"]');
    expect(hoje.text()).toContain('Plano anual');
    expect(hoje.find('[data-item="expected_close_4"]').text()).toContain(
      'CRM_CALENDARIO.ITEM.DIA_TODO'
    );
    const [janela] = wrapper.emitted('rangeChange').at(-1);
    // 30 dias para trás (o que atrasou) até o fim do mês pequeno ao lado.
    expect(janela.from).toBe('2026-09-14T03:00:00.000Z');
    expect(janela.to).toBe('2026-11-01T02:59:00.000Z');
  });

  it('o agente vê só os seus; o administrador vê a equipe', async () => {
    const agente = montar({ ehAdmin: false });
    await flushPromises();
    expect(agente.text()).not.toContain('Da Paula');

    const admin = montar();
    await flushPromises();
    expect(admin.text()).toContain('Da Paula');
    expect(admin.text()).toContain('CRM_CALENDARIO.ITEM.PARA');
  });

  it('concluir pergunta o próximo passo e marca às 09:00 no fuso da conta', async () => {
    const wrapper = montar();
    await flushPromises();

    await wrapper
      .find('[data-secao="atrasados"] [data-concluir]')
      .trigger('click');
    expect(wrapper.emitted('concluir')[0][0].id).toBe('follow_up_1');
    expect(wrapper.find('[data-recem-feito]').exists()).toBe(true);

    await wrapper.find('[data-proximo="AMANHA"]').trigger('click');
    expect(wrapper.emitted('proximoPasso')[0][0]).toMatchObject({
      titulo: 'Ligar para o Roberto',
      quando: '2026-10-15T12:00:00.000Z',
      fuso: 'America/Sao_Paulo',
    });
    expect(wrapper.find('[data-recem-feito]').exists()).toBe(false);
  });

  it('"Passar tudo para amanhã" leva os atrasados para amanhã, 09:00', async () => {
    const wrapper = montar();
    await flushPromises();
    await wrapper.find('[data-adiar-todos]').trigger('click');

    const [carga] = wrapper.emitted('adiarAtrasados')[0];
    expect(carga.eventos.map(e => e.id)).toEqual(['follow_up_1']);
    expect(carga.quando).toBe('2026-10-15T12:00:00.000Z');
  });

  it('a ação da linha abre a conversa pelo número dela', async () => {
    const wrapper = montar();
    await flushPromises();
    await wrapper
      .find('[data-item="follow_up_2"] [data-acao]')
      .trigger('click');

    expect(wrapper.emitted('abrirConversa')[0]).toEqual([7]);
  });

  it('Novo só com lembrete vai direto; com reunião e WhatsApp, oferece a escolha', async () => {
    const so = montar();
    await flushPromises();
    await so.find('[data-calendario-novo]').trigger('click');
    expect(so.emitted('novo')[0][0].type).toBe('reminder');
    expect(abriuEscolha).not.toHaveBeenCalled();

    const sem = montar({ reunioesLigadas: true });
    await flushPromises();
    expect(sem.findComponent(NovoStub).props('opcoes')).toEqual([
      'lembrete',
      'reuniao',
    ]);
    await sem.find('[data-calendario-novo]').trigger('click');
    expect(abriuEscolha).toHaveBeenCalled();

    const com = montar({ reunioesLigadas: true, temWhatsapp: true });
    await flushPromises();
    expect(com.findComponent(NovoStub).props('opcoes')).toEqual([
      'lembrete',
      'reuniao',
      'mensagem',
    ]);
    com.findComponent(NovoStub).vm.$emit('escolher', 'reuniao');
    expect(com.emitted('novo')[0][0].type).toBe('meeting');
  });

  it('sem WhatsApp conectado, "Mensagens marcadas" não aparece no Mostrar', async () => {
    const wrapper = montar();
    await flushPromises();
    await wrapper.find('[data-mostrar-abrir]').trigger('click');

    expect(wrapper.find('[data-mostrar-tipo="mensagem"]').exists()).toBe(false);
    expect(wrapper.find('[data-mostrar-tipo="lembrete"]').exists()).toBe(true);
  });
});
