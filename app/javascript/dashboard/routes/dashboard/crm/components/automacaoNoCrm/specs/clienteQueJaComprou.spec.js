import { ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from '../../../../../../../../../vitest.i18n';
import CardReuniaoDoCliente from '../CardReuniaoDoCliente.vue';
import SeloJaCliente from '../SeloJaCliente.vue';
import CrmKanbanCard from '../../CrmKanbanCard.vue';
import { useCardGanho } from '../useAutomacaoNoCrm';
import { useCardHistorico } from '../../card/useCardHistorico';
import { criarFonteFalsa } from '../fonteDasAutomacoes';

// #2710 — reunião do cliente que já comprou: a reunião dentro do card ganho, a
// linha do tempo em uma frase e o selo "Já é cliente" que abre o card ganho.
const { rota, alerta } = vi.hoisted(() => ({
  rota: { params: { accountId: '1' }, query: {} },
  alerta: vi.fn(),
}));
vi.mock('vue-router', () => ({
  useRoute: () => rota,
  useRouter: () => ({ push: vi.fn() }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: alerta }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: nome =>
    nome === 'inboxes/getInbox' ? { value: () => ({}) } : { value: [] },
}));
vi.mock('dashboard/api/crmKanban', () => ({ default: {} }));

const i18n = withFullI18n('pt_BR');
const { t, te } = i18n.global;

const ganho = { id: 7, status: 'won', contact: { id: 3, name: 'Maria Souza' } };

describe('reunião dentro do card ganho', () => {
  beforeEach(() => {
    rota.query = {};
  });

  it('diz quem marcou, quando e por onde; "Ver" abre a Agenda', async () => {
    const wrapper = mount(CardReuniaoDoCliente, { props: { card: ganho } });
    await flushPromises();
    expect(wrapper.text()).toContain('Reunião do cliente');
    expect(wrapper.find('[data-reuniao-frase]').text()).toBe(
      'Maria marcou para 15/11 às 10h pelo link do e-mail.'
    );
    await wrapper
      .find('[data-card-abrir="reuniao-do-cliente"]')
      .trigger('click');
    expect(wrapper.emitted('abrir')).toEqual([['agenda']]);
  });

  it('card que não é ganho, ou ?demo=vazio, não mostra nada', async () => {
    const aberto = mount(CardReuniaoDoCliente, {
      props: { card: { ...ganho, status: 'open' } },
    });
    await flushPromises();
    expect(aberto.find('[data-card-parte]').exists()).toBe(false);

    rota.query = { demo: 'vazio' };
    const vazio = mount(CardReuniaoDoCliente, { props: { card: ganho } });
    await flushPromises();
    expect(vazio.find('[data-card-parte]').exists()).toBe(false);
  });

  it('a linha do tempo diz a frase inteira, feita pelo cliente', () => {
    const atividades = criarFonteFalsa({ t }).atividadesDoCard(ganho);
    const { porDia } = useCardHistorico({
      t,
      te,
      locale: ref('pt_BR'),
      activities: ref(atividades),
      textos: 'CRM_CARD.HISTORICO.EVENTO',
    });
    const [item] = porDia.value.flatMap(dia => dia.itens);
    expect(item.title).toBe(
      'Maria marcou para 15/11 às 10h pelo link do e-mail'
    );
    expect(item.actor).toBe('Cliente');
  });
});

describe('selo "Já é cliente"', () => {
  it('diz desde quando e abre sem abrir o card de baixo', async () => {
    const wrapper = mount(SeloJaCliente, {
      props: { comprouEm: '2026-11-03T15:30:00' },
    });
    const botao = wrapper.find('[data-selo-ja-cliente]');
    expect(botao.text()).toBe('Já é cliente · comprou em 03/11');
    expect(botao.attributes('aria-label')).toBe(
      'Já é cliente, comprou em 03/11. Abrir a compra'
    );
    await botao.trigger('click');
    expect(wrapper.emitted('abrir')).toHaveLength(1);
  });

  it('no quadro, só aparece com o dado e avisa a página', async () => {
    const cliente = { comprouEm: '2026-11-03T15:30:00', contatoId: 3 };
    const card = { id: 8, title: 'Card novo', status: 'open' };
    const stubs = {
      ChannelIcon: true,
      CardPriorityIcon: true,
      CardLabels: true,
      SLACardLabel: true,
      CrmCardPill: true,
    };
    const sem = mount(CrmKanbanCard, { props: { card }, global: { stubs } });
    expect(sem.find('[data-selo-ja-cliente]').exists()).toBe(false);

    const com = mount(CrmKanbanCard, {
      props: { card, jaCliente: cliente },
      global: { stubs: { ...stubs, CustomerBadge: true } },
    });
    // O selo "Cliente" não se repete ao lado do "Já é cliente".
    expect(com.findComponent({ name: 'CustomerBadge' }).exists()).toBe(false);
    await com.find('[data-selo-ja-cliente]').trigger('click');
    expect(com.emitted('abrirJaCliente')).toEqual([[cliente]]);
    expect(com.emitted('open')).toBeUndefined();
  });

  it('sem compra achada, avisa numa frase', async () => {
    let ganhoAchado;
    mount({
      setup() {
        ganhoAchado = useCardGanho({ cardGanho: async () => null });
        return {};
      },
      template: '<div />',
    });
    expect(await ganhoAchado.achar({ contatoId: 3 })).toBeNull();
    expect(alerta).toHaveBeenCalledWith('Não achamos a compra deste cliente.');
  });
});
