import { mount, flushPromises, enableAutoUnmount } from '@vue/test-utils';
import ConversationInboxApi from 'dashboard/api/inbox/conversation';
import CrmMeuAcessoAPI from 'dashboard/api/crmMeuAcesso';
import { useAlert } from 'dashboard/composables';
import MoreActions from 'dashboard/components/widgets/conversation/MoreActions.vue';
import ItensDoTopo from '../topo/ItensDoTopo.vue';
import { criarI18n, criarStore } from './apoio';

// #2138 — os itens novos do ⋯ do topo: só com a chave, "Mudar prioridade" sem
// time na conta, "Acompanhar" some com a trava de funil, e incluir ou tirar a
// própria pessoa preserva os outros.
vi.mock('dashboard/api/inbox/conversation', () => ({
  default: { fetchParticipants: vi.fn() },
}));
vi.mock('dashboard/api/crmMeuAcesso', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/composables', async importOriginal => ({
  ...(await importOriginal()),
  useAlert: vi.fn(),
}));

enableAutoUnmount(afterEach);

const EU = { id: 7, name: 'Bia' };
const CONVERSA = { id: 42, inbox_id: 1, muted: false, meta: {} };

const montar = (estado = {}) => {
  const apoio = criarStore({
    eu: EU,
    conversaSelecionada: CONVERSA,
    ...estado,
  });
  const wrapper = mount(ItensDoTopo, {
    props: { conversa: CONVERSA },
    global: {
      plugins: [apoio.store, criarI18n()],
      stubs: {
        TimeEPrioridadeDialog: { template: '<div />', methods: { abrir() {} } },
      },
    },
  });
  return { wrapper, ...apoio };
};
const rotulos = wrapper => wrapper.vm.itens.map(item => item.label);

beforeEach(() => {
  vi.clearAllMocks();
  window.globalConfig = { CRM_KANBAN_ENABLED: 'true' };
  CrmMeuAcessoAPI.get.mockResolvedValue({
    data: { payload: { restricted_inbox_ids: [] } },
  });
});

describe('ItensDoTopo', () => {
  it('sem a chave da conta, não acrescenta nada', async () => {
    const { wrapper } = montar({ features: {} });
    await flushPromises();
    expect(wrapper.vm.itens).toEqual([]);
    expect(wrapper.vm.agir('painel_novo_acompanhar')).toBe(false);
    expect(CrmMeuAcessoAPI.get).not.toHaveBeenCalled();
  });

  it('com a chave e time na conta: "Mudar time ou prioridade" e "Acompanhar esta conversa"', async () => {
    const { wrapper } = montar({ times: [{ id: 1, name: 'Suporte' }] });
    await flushPromises();
    expect(rotulos(wrapper)).toEqual([
      'Mudar time ou prioridade',
      'Acompanhar esta conversa',
    ]);
  });

  it('conta sem time: "Mudar prioridade"', async () => {
    const { wrapper } = montar({ times: [] });
    await flushPromises();
    expect(rotulos(wrapper)[0]).toBe('Mudar prioridade');
  });

  it('quem já acompanha vê "Deixar de acompanhar"', async () => {
    const { wrapper } = montar({
      acompanhantes: { 42: [{ id: 3 }, { id: 7 }] },
    });
    await flushPromises();
    expect(rotulos(wrapper)[1]).toBe('Deixar de acompanhar');
  });

  it('a trava de funil na caixa tira "Acompanhar" (sair continua livre)', async () => {
    CrmMeuAcessoAPI.get.mockResolvedValue({
      data: { payload: { restricted_inbox_ids: [1] } },
    });
    const restrito = montar();
    await flushPromises();
    expect(rotulos(restrito.wrapper)).toEqual(['Mudar prioridade']);

    const jaAcompanha = montar({ acompanhantes: { 42: [{ id: 7 }] } });
    await flushPromises();
    expect(rotulos(jaAcompanha.wrapper)).toContain('Deixar de acompanhar');
  });

  it('acompanhar lê a lista do servidor e inclui só a pessoa, preservando os outros', async () => {
    // A tela sabe da Ana; no servidor, uma colega já incluiu o Caio também.
    ConversationInboxApi.fetchParticipants.mockResolvedValue({
      data: [{ id: 3 }, { id: 11 }],
    });
    const { wrapper, acoes } = montar({ acompanhantes: { 42: [{ id: 3 }] } });
    await flushPromises();

    expect(wrapper.vm.agir('painel_novo_acompanhar')).toBe(true);
    await flushPromises();

    expect(acoes).toContainEqual([
      'conversationWatchers/update',
      { conversationId: 42, userIds: [3, 11, 7] },
    ]);
    expect(useAlert).toHaveBeenCalledWith(
      'Pronto. Você recebe aviso de cada mensagem nova.'
    );
  });

  it('deixar de acompanhar tira só a pessoa', async () => {
    ConversationInboxApi.fetchParticipants.mockResolvedValue({
      data: [{ id: 3 }, { id: 7 }, { id: 11 }],
    });
    const { wrapper, acoes } = montar({
      acompanhantes: { 42: [{ id: 3 }, { id: 7 }] },
    });
    await flushPromises();

    wrapper.vm.agir('painel_novo_acompanhar');
    await flushPromises();

    expect(acoes).toContainEqual([
      'conversationWatchers/update',
      { conversationId: 42, userIds: [3, 11] },
    ]);
    expect(useAlert).toHaveBeenCalledWith(
      'Você deixou de acompanhar esta conversa.'
    );
  });

  it('sem ler a lista, não grava e avisa', async () => {
    ConversationInboxApi.fetchParticipants.mockRejectedValue(new Error('rede'));
    const { wrapper, acoes } = montar({ acompanhantes: { 42: [{ id: 7 }] } });
    await flushPromises();

    wrapper.vm.agir('painel_novo_acompanhar');
    await flushPromises();

    expect(
      acoes.filter(([nome]) => nome === 'conversationWatchers/update')
    ).toEqual([]);
    expect(useAlert).toHaveBeenCalledWith(
      'Não deu para mudar agora. Tente de novo.'
    );
  });
});

describe('MoreActions (⋯ do topo) com os itens do fork', () => {
  const montarMenu = estado => {
    const apoio = criarStore({
      eu: EU,
      conversaSelecionada: CONVERSA,
      ...estado,
    });
    const wrapper = mount(MoreActions, {
      global: {
        plugins: [apoio.store, criarI18n()],
        stubs: {
          ResolveAction: true,
          EmailTranscriptModal: true,
          TimeEPrioridadeDialog: {
            template: '<div />',
            methods: { abrir() {} },
          },
          DropdownMenu: {
            props: ['menuItems'],
            template:
              '<ul><li v-for="i in menuItems" :key="i.action" :data-acao="i.action">{{ i.label }}</li></ul>',
          },
        },
        directives: { tooltip: {}, onClickaway: {} },
      },
    });
    return { wrapper, ...apoio };
  };
  const abrirMenu = async wrapper => {
    await wrapper.get('button').trigger('click');
    await flushPromises();
    return wrapper.findAll('[data-acao]').map(li => li.attributes('data-acao'));
  };

  it('sem a chave, o ⋯ fica como o de sempre', async () => {
    const { wrapper } = montarMenu({ features: {} });
    await flushPromises();
    expect(await abrirMenu(wrapper)).toEqual(['mute', 'send_transcript']);
  });

  it('com a chave, os dois itens novos entram depois dos de sempre', async () => {
    const { wrapper } = montarMenu();
    await flushPromises();
    expect(await abrirMenu(wrapper)).toEqual([
      'mute',
      'send_transcript',
      'painel_novo_time_e_prioridade',
      'painel_novo_acompanhar',
    ]);
  });
});
