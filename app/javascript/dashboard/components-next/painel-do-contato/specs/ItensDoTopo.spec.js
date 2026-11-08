import { mount, flushPromises, enableAutoUnmount } from '@vue/test-utils';
import AcompanharConversaAPI from 'dashboard/api/acompanharConversa';
import CrmMeuAcessoAPI from 'dashboard/api/crmMeuAcesso';
import { useAlert } from 'dashboard/composables';
import MoreActions from 'dashboard/components/widgets/conversation/MoreActions.vue';
import ItensDoTopo from '../topo/ItensDoTopo.vue';
import { criarI18n, criarStore } from './apoio';

// #2138 — os itens novos do ⋯ do topo: só com a chave, "Mudar prioridade" sem
// time na conta, "Acompanhar" some com a trava de funil, e incluir ou tirar a
// própria pessoa preserva os outros.
// #2202 (PR 3): "Etiquetas desta conversa" vale sem a chave, só para quem opera.
vi.mock('dashboard/api/acompanharConversa', () => ({
  default: { incluir: vi.fn(), tirar: vi.fn(), quemAcompanha: vi.fn() },
}));
vi.mock('dashboard/api/crmMeuAcesso', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/composables', async importOriginal => ({
  ...(await importOriginal()),
  useAlert: vi.fn(),
}));

enableAutoUnmount(afterEach);

const EU = { id: 7, name: 'Bia' };
const CONVERSA = { id: 42, inbox_id: 1, muted: false, meta: {} };

const abrirEtiquetas = vi.fn();
const EtiquetasStub = {
  template: '<div data-etiquetas />',
  methods: { abrir: abrirEtiquetas },
};

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
        EtiquetasDaConversaDialog: EtiquetasStub,
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
  it('sem a chave da conta, só "Etiquetas desta conversa"', async () => {
    const { wrapper } = montar({ features: {} });
    await flushPromises();
    expect(rotulos(wrapper)).toEqual(['Etiquetas desta conversa']);
    expect(wrapper.vm.agir('painel_novo_acompanhar')).toBe(false);
    expect(CrmMeuAcessoAPI.get).not.toHaveBeenCalled();
  });

  it('com a chave e time na conta: "Mudar time ou prioridade" e "Acompanhar esta conversa"', async () => {
    const { wrapper } = montar({ times: [{ id: 1, name: 'Suporte' }] });
    await flushPromises();
    expect(rotulos(wrapper)).toEqual([
      'Mudar time ou prioridade',
      'Acompanhar esta conversa',
      'Etiquetas desta conversa',
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
    expect(rotulos(restrito.wrapper)).toEqual([
      'Mudar prioridade',
      'Etiquetas desta conversa',
    ]);

    const jaAcompanha = montar({ acompanhantes: { 42: [{ id: 7 }] } });
    await flushPromises();
    expect(rotulos(jaAcompanha.wrapper)).toContain('Deixar de acompanhar');
  });

  it('acompanhar manda só a própria pessoa e avisa quando ela ficou na lista', async () => {
    AcompanharConversaAPI.incluir.mockResolvedValue({ data: [] });
    AcompanharConversaAPI.quemAcompanha.mockResolvedValue({
      data: [{ id: 3 }, { id: 11 }, { id: 7 }],
    });
    const { wrapper, acoes } = montar({ acompanhantes: { 42: [{ id: 3 }] } });
    await flushPromises();

    expect(wrapper.vm.agir('painel_novo_acompanhar')).toBe(true);
    await flushPromises();

    expect(AcompanharConversaAPI.incluir).toHaveBeenCalledWith(42, 7);
    expect(AcompanharConversaAPI.tirar).not.toHaveBeenCalled();
    // A lista inteira (PATCH) não é mais usada.
    expect(
      acoes.filter(([nome]) => nome === 'conversationWatchers/update')
    ).toEqual([]);
    expect(useAlert).toHaveBeenCalledWith(
      'Pronto. Você recebe aviso de cada mensagem nova.'
    );
  });

  it('deixar de acompanhar manda só a própria pessoa', async () => {
    AcompanharConversaAPI.tirar.mockResolvedValue({});
    AcompanharConversaAPI.quemAcompanha.mockResolvedValue({
      data: [{ id: 3 }, { id: 11 }],
    });
    const { wrapper } = montar({
      acompanhantes: { 42: [{ id: 3 }, { id: 7 }] },
    });
    await flushPromises();

    wrapper.vm.agir('painel_novo_acompanhar');
    await flushPromises();

    expect(AcompanharConversaAPI.tirar).toHaveBeenCalledWith(42, 7);
    expect(useAlert).toHaveBeenCalledWith(
      'Você deixou de acompanhar esta conversa.'
    );
  });

  it('o aviso segue o resultado real: gravou, mas a pessoa não ficou na lista', async () => {
    AcompanharConversaAPI.incluir.mockResolvedValue({ data: [] });
    AcompanharConversaAPI.quemAcompanha.mockResolvedValue({
      data: [{ id: 3 }],
    });
    const { wrapper } = montar();
    await flushPromises();

    wrapper.vm.agir('painel_novo_acompanhar');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'Não deu para mudar agora. Tente de novo.'
    );
    expect(useAlert).not.toHaveBeenCalledWith(
      'Pronto. Você recebe aviso de cada mensagem nova.'
    );
  });

  it('recusa do servidor: avisa e diz o motivo quando é a trava de funil', async () => {
    AcompanharConversaAPI.incluir.mockRejectedValue(
      Object.assign(new Error('403'), {
        response: { data: { code: 'participants.self_add_restricted' } },
      })
    );
    const { wrapper } = montar();
    await flushPromises();

    wrapper.vm.agir('painel_novo_acompanhar');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledTimes(1);
    expect(useAlert).toHaveBeenCalledWith('Você não pode se incluir aqui.');
  });

  it('erro de rede: avisa que não deu', async () => {
    AcompanharConversaAPI.tirar.mockRejectedValue(new Error('rede'));
    const { wrapper } = montar({ acompanhantes: { 42: [{ id: 7 }] } });
    await flushPromises();

    wrapper.vm.agir('painel_novo_acompanhar');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'Não deu para mudar agora. Tente de novo.'
    );
  });
});

describe('ItensDoTopo — "Etiquetas desta conversa"', () => {
  it('quem opera vê o item e tocar abre a escolha', async () => {
    const { wrapper } = montar();
    await flushPromises();
    expect(rotulos(wrapper)).toContain('Etiquetas desta conversa');
    expect(wrapper.vm.agir('etiquetas_da_conversa')).toBe(true);
    expect(abrirEtiquetas).toHaveBeenCalledTimes(1);
  });

  it('quem só lê não vê o item nem abre a escolha', async () => {
    const { wrapper } = montar({ podeOperar: false });
    await flushPromises();
    expect(rotulos(wrapper)).not.toContain('Etiquetas desta conversa');
    expect(wrapper.vm.agir('etiquetas_da_conversa')).toBe(false);
    expect(abrirEtiquetas).not.toHaveBeenCalled();
    expect(wrapper.find('[data-etiquetas]').exists()).toBe(false);
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
      attachTo: document.body,
      global: {
        plugins: [apoio.store, criarI18n()],
        stubs: {
          ResolveAction: true,
          EmailTranscriptModal: true,
          TimeEPrioridadeDialog: {
            template: '<div />',
            methods: { abrir() {} },
          },
          EtiquetasDaConversaDialog: EtiquetasStub,
          DropdownMenu: {
            name: 'DropdownMenu',
            props: ['menuItems'],
            emits: ['action'],
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
    expect(await abrirMenu(wrapper)).toEqual([
      'mute',
      'send_transcript',
      'etiquetas_da_conversa',
    ]);
  });

  it('com a chave, os dois itens novos entram depois dos de sempre', async () => {
    const { wrapper } = montarMenu();
    await flushPromises();
    expect(await abrirMenu(wrapper)).toEqual([
      'mute',
      'send_transcript',
      'painel_novo_time_e_prioridade',
      'painel_novo_acompanhar',
      'etiquetas_da_conversa',
    ]);
  });

  it('tocar em "Etiquetas desta conversa" abre a escolha de etiquetas', async () => {
    const { wrapper } = montarMenu({ features: {} });
    await flushPromises();
    await abrirMenu(wrapper);
    wrapper.findComponent({ name: 'DropdownMenu' }).vm.$emit('action', {
      action: 'etiquetas_da_conversa',
    });
    await flushPromises();
    expect(abrirEtiquetas).toHaveBeenCalledTimes(1);
  });

  it('voltarFoco do ⋯: ao fechar a escolha, o foco volta ao botão ⋯ (não cai no <body>)', async () => {
    const { wrapper } = montarMenu({ features: {} });
    await flushPromises();
    await abrirMenu(wrapper);
    wrapper.findComponent({ name: 'DropdownMenu' }).vm.$emit('action', {
      action: 'etiquetas_da_conversa',
    });
    await flushPromises();
    const [voltarFoco] = abrirEtiquetas.mock.calls[0];
    expect(voltarFoco).toEqual(expect.any(Function));
    document.activeElement.blur();
    expect(document.activeElement).toBe(document.body);

    voltarFoco();

    const mais = wrapper.findAll('button')[0].element;
    expect(document.activeElement).toBe(mais);
    expect(mais.getAttribute('icon') || mais.innerHTML).toContain(
      'i-lucide-more-vertical'
    );
  });
});
