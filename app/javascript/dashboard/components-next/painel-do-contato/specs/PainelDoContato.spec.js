import { mount, flushPromises, enableAutoUnmount } from '@vue/test-utils';
import ContactAPI from 'dashboard/api/contacts';
import ConversationInboxApi from 'dashboard/api/inbox/conversation';
import CampaignJourneyAPI from 'dashboard/api/campaignJourney';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { refreshCrmConversationStage } from 'dashboard/routes/dashboard/crm/composables/useCrmConversationStages';
import PainelDoContato from '../PainelDoContato.vue';
import BlocoEtiquetas from '../etiquetas/BlocoEtiquetas.vue';
import { criarI18n, criarStore } from './apoio';

// #2138 — o painel inteiro: blocos que somem sem conteúdo (contato novo não mostra
// "Mais"), as travas de permissão (contact_view, contact_manage, crm_view, operar)
// e os estados de carregar e de erro das partes que pedem dados.
vi.mock('vue-router', () => ({ useRouter: () => ({ push: vi.fn() }) }));
vi.mock('dashboard/api/contacts', () => ({
  default: { getConversations: vi.fn() },
}));
vi.mock('dashboard/api/inbox/conversation', () => ({
  default: { fetchParticipants: vi.fn() },
}));
vi.mock('dashboard/api/campaignJourney', () => ({
  default: { getContactOrigins: vi.fn() },
}));
vi.mock('dashboard/api/crmKanban', () => ({
  default: { getFollowUps: vi.fn(), getConversationCardStages: vi.fn() },
}));

enableAutoUnmount(afterEach);

const CONTATO = {
  id: 9,
  name: 'Marcos Pereira',
  phone_number: '+5511900000001',
  custom_attributes: {},
};
const CONVERSA = {
  id: 42,
  inbox_id: 1,
  priority: null,
  meta: {
    sender: { id: 9, name: 'Marcos Pereira', phone_number: '+5511900000001' },
    assignee: null,
    assignee_type: null,
    team: null,
  },
};
const erroCom = status =>
  Object.assign(new Error('x'), { response: { status } });

// Contato novo: nada além desta conversa, ninguém acompanha, sem origem nem lembrete.
const servidorVazio = () => {
  ContactAPI.getConversations.mockResolvedValue({
    data: { payload: [{ id: 42, meta: {} }] },
  });
  ConversationInboxApi.fetchParticipants.mockResolvedValue({ data: [] });
  CampaignJourneyAPI.getContactOrigins.mockResolvedValue({
    data: { payload: { marks: [] } },
  });
  CrmKanbanAPI.getFollowUps.mockResolvedValue({
    data: { payload: [], meta: { count: 0 } },
  });
  CrmKanbanAPI.getConversationCardStages.mockResolvedValue({
    data: { payload: {} },
  });
};

const montar = ({ props = {}, estado = {}, attachTo } = {}) => {
  const apoio = criarStore({ conversaSelecionada: CONVERSA, ...estado });
  const wrapper = mount(PainelDoContato, {
    attachTo,
    props: {
      conversation: CONVERSA,
      contact: CONTATO,
      podeVerContatos: true,
      podeOperar: true,
      ...props,
    },
    global: {
      plugins: [apoio.store, criarI18n()],
      stubs: {
        ContatoBasico: { template: '<div data-contato-basico />' },
        EditContact: true,
        EtiquetasDaConversaDialog: { template: '<div />' },
        ContactLabels: {
          props: ['readOnly'],
          template:
            '<div data-etiquetas :data-so-leitura="String(readOnly)" />',
        },
      },
      directives: { tooltip: {} },
    },
  });
  return { wrapper, ...apoio };
};

const texto = wrapper => wrapper.text();
const linhasDeMais = wrapper =>
  wrapper.findAll('[data-test-id="bloco-mais"] button').map(b => b.text());

beforeEach(() => {
  vi.clearAllMocks();
  window.globalConfig = { CRM_KANBAN_ENABLED: 'true' };
  servidorVazio();
});

describe('PainelDoContato — o que aparece', () => {
  it('conversa com etiqueta (#2202): o bloco "Etiquetas" logo depois de "Quem cuida"', async () => {
    const { wrapper } = montar({
      estado: {
        etiquetasDaConta: [{ id: 1, title: 'vip', color: '#ff0000' }],
        etiquetasDaConversa: { 42: ['vip'] },
      },
    });
    await flushPromises();

    const blocos = wrapper.findAll('section');
    const indice = blocos.findIndex(
      bloco => bloco.attributes('data-test-id') === 'bloco-etiquetas'
    );
    expect(indice).toBeGreaterThan(0);
    expect(blocos[indice].text()).toContain('vip');
    expect(blocos[indice - 1].text()).toContain('Quem cuida');
  });

  it('tirou a última etiqueta com a escolha aberta: o foco vai ao título "Quem cuida", sem rolar a tela', async () => {
    const { wrapper, dados } = montar({
      attachTo: document.body,
      estado: {
        etiquetasDaConta: [{ id: 1, title: 'vip', color: '#ff0000' }],
        etiquetasDaConversa: { 42: ['vip'] },
      },
    });
    await flushPromises();
    const focar = vi.spyOn(HTMLElement.prototype, 'focus');
    dados.etiquetasDaConversa = { 42: [] };
    await flushPromises();
    expect(wrapper.find('[data-test-id="bloco-etiquetas"]').exists()).toBe(
      false
    );

    wrapper.findComponent(BlocoEtiquetas).props('focarAoSumir')();

    const titulo = document.activeElement;
    expect(titulo.tagName).toBe('H3');
    expect(titulo.textContent.trim()).toBe('Quem cuida');
    expect(titulo.getAttribute('tabindex')).toBe('-1');
    // Contorno visível no foco: não é uma div muda.
    expect(titulo.className).toContain('focus:outline-2');
    expect(focar).toHaveBeenCalledWith({ preventScroll: true });
    focar.mockRestore();
  });

  it('contato novo: nome, telefone, quem cuida e o pé; sem "Mais", combinado ou origem', async () => {
    const { wrapper } = montar();
    await flushPromises();

    expect(texto(wrapper)).toContain('Sobre este contato');
    expect(texto(wrapper)).toContain('Marcos Pereira');
    expect(texto(wrapper)).toContain('+5511900000001');
    expect(texto(wrapper)).toContain('Ninguém está cuidando desta conversa.');
    expect(texto(wrapper)).toContain('Ver página do contato');
    expect(wrapper.find('[data-test-id="bloco-mais"]').exists()).toBe(false);
    expect(wrapper.find('[data-test-id="bloco-combinado"]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-test-id="bloco-origem"]').exists()).toBe(false);
    expect(wrapper.find('[data-test-id="bloco-etiquetas"]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-test-id="esqueleto"]').exists()).toBe(false);
    // Nada de "Indisponível" nem de CAIXA ALTA.
    expect(texto(wrapper)).not.toContain('Indisponível');
  });

  it('"Mais" mostra só as linhas com conteúdo, sem os campos internos do WhatsApp', async () => {
    ContactAPI.getConversations.mockResolvedValue({
      data: { payload: [{ id: 42 }, { id: 41 }, { id: 40 }] },
    });
    ConversationInboxApi.fetchParticipants.mockResolvedValue({
      data: [{ id: 3, name: 'Ana' }],
    });
    const contato = {
      ...CONTATO,
      custom_attributes: {
        melhor_horario: 'Depois das 14h',
        waha_whatsapp_jid: '5511900000001@c.us',
        vazio: '',
      },
    };
    const definicoes = [
      [1, 'melhor_horario', 'Melhor horário'],
      [2, 'waha_whatsapp_jid', 'waha_whatsapp_jid'],
      [3, 'vazio', 'Vazio'],
    ].map(([id, chave, nome]) => ({
      id,
      attribute_key: chave,
      attribute_display_name: nome,
      attribute_model: 'contact_attribute',
    }));
    const { wrapper } = montar({
      props: { contact: contato },
      estado: { definicoes, anexos: [] },
    });
    await flushPromises();

    expect(linhasDeMais(wrapper)).toEqual([
      'Conversas anteriores (2)',
      'Outras informações (1)',
      'Quem acompanha esta conversa (1)',
    ]);
  });

  it('enquanto "Mais" carrega, mostra o esqueleto; depois some se não há nada', async () => {
    let soltar;
    ContactAPI.getConversations.mockReturnValue(
      new Promise(resolve => {
        soltar = resolve;
      })
    );
    const { wrapper } = montar();
    await flushPromises();
    expect(
      wrapper.find('[data-test-id="bloco-mais-carregando"]').exists()
    ).toBe(true);

    soltar({ data: { payload: [{ id: 42 }] } });
    await flushPromises();
    expect(
      wrapper.find('[data-test-id="bloco-mais-carregando"]').exists()
    ).toBe(false);
    expect(wrapper.find('[data-test-id="bloco-mais"]').exists()).toBe(false);
  });

  it('403 numa lista esconde só aquela linha, sem mensagem', async () => {
    ContactAPI.getConversations.mockRejectedValue(erroCom(403));
    ConversationInboxApi.fetchParticipants.mockResolvedValue({
      data: [{ id: 3, name: 'Ana' }],
    });
    const { wrapper } = montar();
    await flushPromises();

    expect(linhasDeMais(wrapper)).toEqual(['Quem acompanha esta conversa (1)']);
    expect(texto(wrapper)).not.toContain('Não deu para carregar');
  });

  it('erro numa lista: a frase e "Tentar de novo", que lê de novo só a que falhou', async () => {
    ContactAPI.getConversations.mockRejectedValueOnce(erroCom(500));
    const { wrapper } = montar();
    await flushPromises();

    const erro = wrapper.get(
      '[data-test-id="bloco-mais"] [data-test-id="erro-da-parte"]'
    );
    expect(erro.text()).toContain('Não deu para carregar esta parte agora.');
    ContactAPI.getConversations.mockResolvedValueOnce({
      data: { payload: [{ id: 42 }, { id: 41 }] },
    });
    await erro.get('button').trigger('click');
    await flushPromises();

    expect(ContactAPI.getConversations).toHaveBeenCalledTimes(2);
    expect(ConversationInboxApi.fetchParticipants).toHaveBeenCalledTimes(1);
    expect(linhasDeMais(wrapper)).toEqual(['Conversas anteriores (1)']);
  });

  it('o contato ainda não chegou: mostra nome e telefone da conversa e espera', async () => {
    const { wrapper } = montar({
      props: { contact: {} },
      estado: { uiContatos: { isFetchingItem: true } },
    });
    await flushPromises();
    expect(texto(wrapper)).toContain('Marcos Pereira');
    expect(wrapper.find('[data-etiquetas]').exists()).toBe(false);
    expect(texto(wrapper)).not.toContain('Editar dados');
    // Sem contato, as listas de "Mais" nem são pedidas.
    expect(ContactAPI.getConversations).not.toHaveBeenCalled();
    // E "Ver página do contato" só aparece com o contato (o id) carregado.
    expect(wrapper.find('[data-test-id="ver-pagina"]').exists()).toBe(false);
    expect(texto(wrapper)).not.toContain('Ver página do contato');
  });

  it('a leitura do contato terminou sem ele: erro e "Tentar de novo" pede de novo', async () => {
    const { wrapper, dados, acoes } = montar({
      props: { contact: {} },
      estado: { uiContatos: { isFetchingItem: true } },
    });
    await flushPromises();
    dados.uiContatos = { isFetchingItem: false };
    await flushPromises();

    const erro = wrapper.get('[data-test-id="erro-da-parte"]');
    expect(erro.text()).toContain('Não deu para carregar esta parte agora.');
    await erro.get('button').trigger('click');
    expect(acoes).toContainEqual(['contacts/show', { id: 9 }]);
  });
});

describe('PainelDoContato — travas de permissão', () => {
  it('quem opera não vê a faixa de só leitura; quem não opera vê', async () => {
    const opera = montar();
    await flushPromises();
    expect(
      opera.wrapper.find('[data-test-id="faixa-so-leitura"]').exists()
    ).toBe(false);

    const soLe = montar({ props: { podeOperar: false } });
    await flushPromises();
    expect(soLe.wrapper.get('[data-test-id="faixa-so-leitura"]').text()).toBe(
      'Você pode ver esta conversa, mas não mudar.'
    );
  });

  it('agente sem função: "Editar dados", etiquetas editáveis e o pé', async () => {
    const { wrapper } = montar();
    await flushPromises();
    expect(texto(wrapper)).toContain('Editar dados');
    expect(wrapper.get('[data-etiquetas]').attributes('data-so-leitura')).toBe(
      'false'
    );
    expect(texto(wrapper)).toContain('Ver página do contato');
  });

  it('função com contact_view e sem contact_manage: vê, sem "Editar dados"; etiquetas só leitura', async () => {
    const { wrapper } = montar({
      estado: {
        funcao: 5,
        permissoes: ['contact_view', 'conversation_manage'],
      },
    });
    await flushPromises();
    expect(texto(wrapper)).not.toContain('Editar dados');
    expect(texto(wrapper)).toContain('Ver página do contato');
  });

  it('sem contact_view: o contato básico de hoje, sem o pé e sem pedir as listas do contato', async () => {
    const { wrapper } = montar({
      props: { podeVerContatos: false },
      estado: { funcao: 5, permissoes: ['conversation_manage'] },
    });
    await flushPromises();
    expect(wrapper.find('[data-contato-basico]').exists()).toBe(true);
    expect(texto(wrapper)).not.toContain('Ver página do contato');
    expect(texto(wrapper)).not.toContain('Editar dados');
    expect(ContactAPI.getConversations).not.toHaveBeenCalled();
  });

  it('sem crm_view: o "Combinado" nem é pedido', async () => {
    montar({ estado: { funcao: 5, permissoes: ['contact_view'] } });
    await flushPromises();
    expect(CrmKanbanAPI.getFollowUps).not.toHaveBeenCalled();
  });

  it('com crm_view: o "Combinado" é pedido para o contato', async () => {
    montar({ estado: { funcao: 5, permissoes: ['contact_view', 'crm_view'] } });
    await flushPromises();
    expect(CrmKanbanAPI.getFollowUps).toHaveBeenCalledWith(
      expect.objectContaining({ contact_id: 9 })
    );
  });

  it('o assunto aparece só para quem não opera', async () => {
    CrmKanbanAPI.getConversationCardStages.mockResolvedValue({
      data: {
        payload: {
          42: { title: 'Pedido de orçamento', stage_name: 'Proposta' },
        },
      },
    });
    // O selo vem de um cache em lote do módulo, com espera de 50 ms
    // (useCrmConversationStages). Outros testes deste arquivo já guardaram "sem
    // assunto" para a conversa 42: pede de novo, como faz a tela ao mudar o assunto.
    refreshCrmConversationStage(42);
    const soLe = montar({ props: { podeOperar: false } });
    await vi.waitFor(() =>
      expect(texto(soLe.wrapper)).toContain(
        'Pedido de orçamento está em Proposta.'
      )
    );

    // Com o selo já no cache, quem opera continua sem o bloco (o topo já mostra).
    const opera = montar();
    await flushPromises();
    expect(texto(opera.wrapper)).not.toContain('está em Proposta');
  });
});
