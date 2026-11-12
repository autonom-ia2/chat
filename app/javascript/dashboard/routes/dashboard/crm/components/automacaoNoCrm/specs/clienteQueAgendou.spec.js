import { mount } from '@vue/test-utils';
import { withFullI18n } from '../../../../../../../../../vitest.i18n';
import SeloJaCliente from '../SeloJaCliente.vue';
import CrmKanbanCard from '../../CrmKanbanCard.vue';
import CardHeroi from '../../card/CardHeroi.vue';
import { useCardGanho } from '../useAutomacaoNoCrm';
import { clienteQueAgendou } from '../clienteQueAgendou';

// #2710, variante 2 — o card que a página de agendamento criou para quem já comprou: só dado real (source do card,
// contact_type e customer_since do contato); o selo do quadro abre o card ganho; no card aberto, o selo "Cliente
// desde…" do topo vira o botão (sem um terceiro selo).
const { alerta, oportunidades } = vi.hoisted(() => ({
  alerta: vi.fn(),
  oportunidades: vi.fn(),
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1' }, query: {} }),
  useRouter: () => ({ push: vi.fn() }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: alerta }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: nome =>
    nome === 'inboxes/getInbox' ? { value: () => ({}) } : { value: [] },
}));
vi.mock('dashboard/api/crmKanban', () => ({
  default: { getContactOpportunities: oportunidades },
}));

withFullI18n('pt_BR');

const cliente = { id: 3, contact_type: 'customer', customer_since: 1793719800 };
const doAgendamento = {
  id: 8,
  title: 'Ana Costa - Agenda',
  status: 'open',
  source: 'public_link',
  contact: cliente,
};

describe('clienteQueAgendou', () => {
  it('só o card aberto que a página criou para quem já é cliente', () => {
    expect(clienteQueAgendou(doAgendamento)).toEqual({
      contatoId: 3,
      desde: 1793719800,
    });
    expect(clienteQueAgendou({ ...doAgendamento, source: 'invite' })).toEqual({
      contatoId: 3,
      desde: 1793719800,
    });
  });

  it('card de outra origem, fechado ou de quem não é cliente fica de fora', () => {
    expect(
      clienteQueAgendou({ ...doAgendamento, source: 'manual' })
    ).toBeNull();
    expect(clienteQueAgendou({ ...doAgendamento, source: null })).toBeNull();
    expect(clienteQueAgendou({ ...doAgendamento, status: 'won' })).toBeNull();
    expect(
      clienteQueAgendou({
        ...doAgendamento,
        contact: { id: 3, contact_type: 'lead' },
      })
    ).toBeNull();
  });
});

describe('selo "Já é cliente" no quadro', () => {
  // "3 de novembro" sem o ano: o ano é o de hoje.
  beforeAll(() => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date('2026-11-12T15:00:00.000Z'));
  });
  afterAll(() => vi.useRealTimers());

  it('diz desde quando (customer_since) e abre sem abrir o card de baixo', async () => {
    const wrapper = mount(SeloJaCliente, { props: { desde: 1793719800 } });
    const botao = wrapper.find('[data-selo-ja-cliente]');
    expect(botao.text()).toBe('Já é cliente desde 3 de novembro');
    expect(botao.attributes('aria-label')).toContain('Abrir a compra');
    await botao.trigger('click');
    expect(wrapper.emitted('abrir')).toHaveLength(1);
  });

  it('sem a data, não inventa uma', () => {
    const wrapper = mount(SeloJaCliente);
    expect(wrapper.text()).toBe('Já é cliente');
  });

  it('no quadro, só no card do agendamento, no lugar do selo "Cliente"', async () => {
    const stubs = {
      ChannelIcon: true,
      CardPriorityIcon: true,
      CardLabels: true,
      SLACardLabel: true,
      CrmCardPill: true,
    };
    const dado = { contatoId: 3, desde: 1793719800 };
    const sem = mount(CrmKanbanCard, {
      props: { card: doAgendamento },
      global: { stubs },
    });
    expect(sem.find('[data-selo-ja-cliente]').exists()).toBe(false);

    const com = mount(CrmKanbanCard, {
      props: { card: doAgendamento, jaCliente: dado },
      global: { stubs: { ...stubs, CustomerBadge: true } },
    });
    expect(com.findComponent({ name: 'CustomerBadge' }).exists()).toBe(false);
    await com.find('[data-selo-ja-cliente]').trigger('click');
    expect(com.emitted('abrirJaCliente')).toEqual([[dado]]);
    expect(com.emitted('open')).toBeUndefined();
  });
});

describe('selo "Cliente desde…" no topo do card aberto', () => {
  const props = {
    tituloId: 't',
    textoId: 'x',
    rotulo: 'Novo contato',
    titulo: 'Ana Costa - Agenda',
    contato: cliente,
  };

  it('vira botão que abre a compra, sem um selo a mais', async () => {
    const wrapper = mount(CardHeroi, { props: { ...props, abreCompra: true } });
    expect(wrapper.findAll('[data-customer-badge]')).toHaveLength(1);
    const botao = wrapper.find('[data-heroi-compra]');
    expect(botao.text()).toContain('Abrir a compra');
    await botao.trigger('click');
    expect(wrapper.emitted('compra')).toHaveLength(1);
  });

  it('fora do caso, o selo segue como era', () => {
    const wrapper = mount(CardHeroi, { props });
    expect(wrapper.find('[data-heroi-compra]').exists()).toBe(false);
    expect(wrapper.findAll('[data-customer-badge]')).toHaveLength(1);
  });
});

describe('abrir a compra', () => {
  const montarGanho = () => {
    let ganho;
    mount({
      setup() {
        ganho = useCardGanho();
        return {};
      },
      template: '<div />',
    });
    return ganho;
  };

  it('acha o card ganho pela API do perfil do contato', async () => {
    oportunidades.mockResolvedValue({ data: { payload: [{ id: 77 }] } });
    expect(await montarGanho().achar({ contatoId: 3 })).toBe(77);
    expect(oportunidades).toHaveBeenCalledWith('3', { result: 'won' });
  });

  it('sem compra achada, avisa numa frase', async () => {
    oportunidades.mockResolvedValue({ data: { payload: [] } });
    expect(await montarGanho().achar({ contatoId: 3 })).toBeNull();
    expect(alerta).toHaveBeenCalledWith('Não achamos a compra deste cliente.');
  });
});
