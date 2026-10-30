import { flushPromises, mount } from '@vue/test-utils';
import CardGaveta from '../CardGaveta.vue';

const { keyboard, alertSpy, dialogos, link, marcar, conta, despachar } =
  vi.hoisted(() => ({
    keyboard: { handlers: null },
    alertSpy: vi.fn(),
    dialogos: { abertos: [] },
    link: { ligado: true },
    // Como a conta marca reunião (useJeitoDeMarcar) e se pode criar página.
    marcar: {
      jeito: 'pagina',
      podeCriar: true,
      abrirPaginas: null,
      caixa: false,
    },
    despachar: { fn: null },
    conta: { empresas: true, mensagemMarcada: false },
  }));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    isCloudFeatureEnabled: chave =>
      (chave === 'companies' && conta.empresas) ||
      (chave === 'crm_mensagem_marcada' && conta.mensagemMarcada),
    currentAccount: { value: { timezone: 'America/Sao_Paulo' } },
  }),
}));
vi.mock('../useJeitoDeMarcar', async () => {
  const { computed } = await import('vue');
  return {
    useJeitoDeMarcar: () => ({
      jeito: computed(() => marcar.jeito),
      paginas: computed(() =>
        marcar.jeito === 'pagina' ? [{ id: 1, title: 'Minha agenda' }] : []
      ),
      temPagina: computed(() => marcar.jeito === 'pagina'),
      temCaixa: computed(() => marcar.jeito === 'externa' || marcar.caixa),
      podeCriarPagina: computed(() => marcar.podeCriar),
      abrirPaginas: () => marcar.abrirPaginas?.(),
      recarregar: () => {},
    }),
  };
});

vi.mock(
  'dashboard/components-next/Booking/useBookingInviteAvailable',
  async () => {
    const { computed } = await import('vue');
    return { useBookingInviteAvailable: () => computed(() => link.ligado) };
  }
);

vi.mock('dashboard/composables/useRelationshipPermissions', async () => {
  const { ref } = await import('vue');
  return {
    useRelationshipPermissions: () => ({
      canManageRelationshipRecords: ref(true),
    }),
  };
});
vi.mock('vuex', async importOriginal => ({
  ...(await importOriginal()),
  useStore: () => ({
    getters: {},
    dispatch: (...args) => despachar.fn?.(...args),
  }),
}));
const navigate = vi.fn();
const enviarReuniao = vi.fn();
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1' }, query: {} }),
  useRouter: () => ({ push: navigate }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: alertSpy }));
vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: handlers => {
    keyboard.handlers = handlers;
  },
}));
vi.mock('dashboard/api/crmKanban', () => ({
  default: {
    getFollowUpMessagingWindow: vi.fn().mockResolvedValue({ data: {} }),
    getCurrentAiSuggestion: vi.fn().mockResolvedValue({ data: {} }),
    evaluateCardAi: vi.fn().mockResolvedValue({ data: {} }),
    acceptAiSuggestion: vi.fn().mockResolvedValue({}),
    dismissAiSuggestion: vi.fn().mockResolvedValue({}),
    summarizeCardConversation: vi.fn().mockResolvedValue({ data: {} }),
    getOwnerOptions: vi.fn(),
    upcomingMeetings: vi
      .fn()
      .mockResolvedValue({ data: { payload: { cards: [] } } }),
  },
}));
vi.mock('dashboard/api/metaConversions', () => ({
  default: {
    getForCards: vi.fn().mockResolvedValue({ data: { payload: [] } }),
  },
}));
vi.mock('dashboard/api/crmMeetings', () => ({
  default: {
    index: vi.fn().mockResolvedValue({ data: { payload: [] } }),
    show: vi.fn(),
  },
}));
vi.mock('dashboard/api/crmBookingInvites', () => ({
  default: {
    index: vi.fn().mockResolvedValue({ data: { pages: [], payload: [] } }),
    create: vi.fn(),
    deliver: vi.fn(),
    copied: vi.fn(),
    cancel: vi.fn(),
  },
}));
vi.mock('dashboard/api/whatsappApiMessageTemplates', () => ({
  default: { get: vi.fn().mockResolvedValue({ data: { payload: [] } }) },
}));

const etapas = [
  { id: 10, name: 'Novo contato', color: '#2563eb' },
  { id: 11, name: 'Em conversa', color: '#0891b2' },
];
const cardBase = {
  id: 5,
  title: 'Plano anual',
  stage_id: 10,
  pipeline_id: 1,
  status: 'open',
  can_edit: true,
  contact: { id: 7, name: 'Mariana Costa', phone_number: '+5511987654321' },
  owner: { id: 2, name: 'Ana Souza' },
};

const DialogStub = {
  name: 'Dialog',
  props: ['title', 'description'],
  emits: ['confirm', 'close'],
  template:
    '<div data-dialog-stub :data-title="title"><slot /><slot name="footer" /></div>',
  methods: {
    open() {
      dialogos.abertos.push(this.title);
    },
    close() {},
  },
};

const montar = (props = {}) =>
  mount(CardGaveta, {
    props: {
      show: true,
      mode: 'edit',
      card: cardBase,
      stages: etapas,
      pipelines: [{ id: 1, name: 'Comercial', counts_as_sale: true }],
      pipelineId: 1,
      agents: [
        { id: 2, name: 'Ana Souza' },
        { id: 3, name: 'Bruno Sem Funil' },
        { id: 4, name: 'Diego Lima' },
      ],
      canManageCards: true,
      canMoveCards: true,
      canManageAi: true,
      ...props,
    },
    global: {
      stubs: {
        Dialog: DialogStub,
        CrmCardRelationshipPanel: {
          name: 'CrmCardRelationshipPanel',
          props: ['parte'],
          template: '<div data-painel-stub :data-parte="parte" />',
          methods: { reset() {}, reload() {} },
        },
        CrmBookingAgendaForm: {
          name: 'CrmBookingAgendaForm',
          template: '<div data-agenda-form-stub />',
          methods: { submit() {} },
        },
        CrmProviderMeetingForm: {
          name: 'CrmProviderMeetingForm',
          props: ['cardId', 'availableInboxes', 'cardContactName'],
          emits: ['create', 'saving'],
          template: '<div data-provider-form-stub />',
          methods: {
            submit() {
              enviarReuniao();
            },
          },
        },
        CrmCardAutoFollowupStatus: true,
        CrmCardCustomFields: true,
        CrmOpportunityForm: {
          name: 'CrmOpportunityForm',
          props: ['passo'],
          template: '<div data-criacao-stub :data-passo="passo" />',
          data: () => ({ relacaoPronta: false, canSave: false, dirty: false }),
        },
        CrmMeetingDayActions: true,
        TeleportWithDirection: { template: '<div><slot /></div>' },
      },
    },
  });

const clicar = async (wrapper, seletor) => {
  await wrapper.find(seletor).trigger('click');
  await flushPromises();
};
const escolhaDoDono = wrapper =>
  wrapper
    .findAllComponents({ name: 'ChoiceSelect' })
    .find(escolha => escolha.props('ariaLabel') === 'CRM_CARD.DONO.CUIDA');
const botaoComTexto = (wrapper, texto) =>
  wrapper.findAll('button').find(botao => botao.text().includes(texto));

describe('CardGaveta (#1423)', () => {
  beforeEach(() => {
    dialogos.abertos = [];
    navigate.mockClear();
    link.ligado = true;
    marcar.jeito = 'pagina';
    marcar.podeCriar = true;
    marcar.abrirPaginas = vi.fn();
    marcar.caixa = false;
    enviarReuniao.mockClear();
    alertSpy.mockClear();
    conta.empresas = true;
    conta.mensagemMarcada = false;
    despachar.fn = vi.fn().mockResolvedValue({});
  });

  it('abre no resumo com o próximo passo, quatro cartões e Mais detalhes', async () => {
    const wrapper = montar();
    await flushPromises();
    expect(wrapper.find('[data-card-gaveta]').attributes('data-tela')).toBe(
      'resumo'
    );
    expect(wrapper.find('[data-card-proximo]').attributes('data-passo')).toBe(
      'em_dia'
    );
    expect(
      wrapper
        .findAll('[data-card-parte]')
        .map(cartao => cartao.attributes('data-card-parte'))
    ).toEqual(['contato', 'negocio', 'agenda', 'conversa']);
    expect(wrapper.find('[data-card-mais]').attributes('open')).toBeUndefined();
    expect(wrapper.find('[data-card-faixa]').exists()).toBe(true);
  });

  // #1590: com a flag, "Mensagem" da Agenda abre a gaveta da Mensagem marcada,
  // já com o cliente, quando a conversa do card está na caixa oficial.
  it('com a flag, Mensagem da Agenda abre a Mensagem marcada no Quando', async () => {
    conta.mensagemMarcada = true;
    const wrapper = montar({
      initialTab: 'followups',
      card: { ...cardBase, conversation_id: 30, inbox_id: 9 },
      inboxes: [
        { id: 9, name: 'WhatsApp da loja', channel_type: 'Channel::Whatsapp' },
      ],
    });
    await flushPromises();
    await clicar(wrapper, '[data-agenda-opcao="mensagem"]');

    expect(
      wrapper.find('[data-mensagem-marcada]').attributes('data-passo-atual')
    ).toBe('quando');
    expect(wrapper.find('[data-card-gaveta]').attributes('data-tela')).toBe(
      'agenda'
    );
  });

  it('sem a flag, ou fora da caixa oficial, Mensagem segue no retorno do card', async () => {
    conta.mensagemMarcada = true;
    const wrapper = montar({
      initialTab: 'followups',
      card: { ...cardBase, conversation_id: 30, inbox_id: 8 },
      inboxes: [{ id: 8, name: 'Campanhas', channel_type: 'Channel::Api' }],
    });
    await flushPromises();
    await clicar(wrapper, '[data-agenda-opcao="mensagem"]');

    expect(wrapper.find('[data-mensagem-marcada]').exists()).toBe(false);
    expect(wrapper.find('[data-card-gaveta]').attributes('data-tela')).toBe(
      'retorno-novo'
    );
  });

  it('não tem abas nem rodapé no resumo: fechar fica no X do topo', async () => {
    const wrapper = montar();
    await flushPromises();
    expect(wrapper.find('[role="tablist"]').exists()).toBe(false);
    expect(wrapper.find('[data-card-rodape]').exists()).toBe(false);
    expect(wrapper.find('[data-card-fechar]').exists()).toBe(true);
  });

  it('abre direto na Agenda quando vem do calendário e volta ao resumo', async () => {
    const wrapper = montar({ initialTab: 'followups' });
    await flushPromises();
    expect(wrapper.find('[data-card-gaveta]').attributes('data-tela')).toBe(
      'agenda'
    );
    await clicar(wrapper, '[data-card-voltar]');
    expect(wrapper.find('[data-card-gaveta]').attributes('data-tela')).toBe(
      'resumo'
    );
  });

  it('muda de etapa na hora ao tocar numa etapa (RS-02)', async () => {
    const wrapper = montar();
    await flushPromises();
    await clicar(wrapper, '[data-resumo-etapa]');
    await clicar(wrapper, '[data-etapa="Em conversa"]');
    expect(wrapper.emitted('move')).toEqual([[11]]);
  });

  it('salva o negócio e volta ao resumo; cancelar com mudança pergunta antes', async () => {
    const wrapper = montar();
    await flushPromises();
    await clicar(wrapper, '[data-card-abrir="negocio"]');
    const titulo = wrapper.find('[data-negocio-titulo] input');
    await titulo.setValue('Plano anual com 2 lojas');
    await clicar(wrapper, '[data-urgencia="high"]');

    await clicar(wrapper, '[data-card-voltar]');
    expect(dialogos.abertos.at(-1)).toBe('CRM_CARD.SAIR.TITULO');
    expect(wrapper.find('[data-card-gaveta]').attributes('data-tela')).toBe(
      'negocio'
    );

    await clicar(wrapper, '[data-card-principal]');
    const [payload, , salvou] = wrapper.emitted('save')[0];
    expect(payload).toMatchObject({
      title: 'Plano anual com 2 lojas',
      priority: 'high',
      currency: 'BRL',
    });
    salvou();
    await flushPromises();
    expect(wrapper.find('[data-card-gaveta]').attributes('data-tela')).toBe(
      'resumo'
    );
  });

  it('Ganhou abre o diálogo no funil de venda e fecha direto fora de venda', async () => {
    const venda = montar();
    await flushPromises();
    await clicar(venda, '[data-card-ganhou]');
    expect(dialogos.abertos.at(-1)).toBe(
      'CRM_CARD.DESFECHO.GANHOU_TITULO_PADRAO'
    );
    expect(venda.emitted('closeDeal')).toBeUndefined();

    const semVenda = montar({
      pipelines: [{ id: 1, name: 'Suporte', counts_as_sale: false }],
    });
    await flushPromises();
    await clicar(semVenda, '[data-card-ganhou]');
    expect(semVenda.emitted('closeDeal')).toEqual([[{ result: 'won' }]]);
  });

  it('fora de venda o card fala em Assunto, não em Negócio', async () => {
    const semVenda = montar({
      pipelines: [{ id: 1, name: 'Suporte', counts_as_sale: false }],
    });
    await flushPromises();
    expect(semVenda.html()).toContain('CRM_CARD.RESUMO.ASSUNTO');
    expect(semVenda.html()).not.toContain('CRM_CARD.RESUMO.NEGOCIO"');

    const venda = montar();
    await flushPromises();
    expect(venda.html()).toContain('CRM_CARD.RESUMO.NEGOCIO');
  });

  // #1498 — achados do teste em produção (conta 16, funil trocado para Atender).
  it('em Atender, Cancelado tem motivos e exemplo de atendimento', async () => {
    const wrapper = montar({
      pipelines: [{ id: 1, name: 'Suporte', counts_as_sale: false }],
    });
    await flushPromises();
    const html = wrapper.html();
    expect(html).toContain('CRM_CARD.DESFECHO.MOTIVO_ATENDER.NAO_PRECISA');
    expect(html).toContain('CRM_CARD.DESFECHO.CANCELAR_EXEMPLO');
    expect(html).not.toContain('CRM_CARD.DESFECHO.MOTIVO.PRECO');
    expect(html).not.toContain('CRM_KANBAN.DRAWER.LOSE_REASON_PLACEHOLDER');
  });

  it('em Atender, editar o card fala de Assunto e não pede valor', async () => {
    const wrapper = montar({
      pipelines: [{ id: 1, name: 'Suporte', counts_as_sale: false }],
    });
    await flushPromises();
    await wrapper.get('[data-card-abrir="negocio"]').trigger('click');
    await flushPromises();
    const html = wrapper.html();
    expect(html).toContain('CRM_CARD.ASSUNTO.NOME');
    expect(html).toContain('CRM_CARD.ASSUNTO.TITULO');
    expect(html).not.toContain('CRM_CARD.NEGOCIO.NOME');
    expect(wrapper.find('[data-campo-valor]').exists()).toBe(false);
    expect(
      wrapper.findComponent({ name: 'CrmCardCustomFields' }).props('atender')
    ).toBe(true);
  });

  it('na Cobrança, editar o card pede valor a receber, vencimento e promessa', async () => {
    const wrapper = montar({
      pipelines: [
        {
          id: 1,
          name: 'Cobrança',
          counts_as_sale: false,
          metadata: { template: 'COBRANCA' },
        },
      ],
    });
    await flushPromises();
    await wrapper.get('[data-card-abrir="negocio"]').trigger('click');
    await flushPromises();
    const html = wrapper.html();
    expect(html).toContain('CRM_CARD.COBRANCA.VALOR');
    expect(html).toContain('CRM_CARD.COBRANCA.FECHAR_ATE');
    expect(wrapper.find('[data-campo-promessa]').exists()).toBe(true);
  });

  it('Arquivar pede confirmação antes de arquivar (OB-03)', async () => {
    const wrapper = montar({ canDeleteCards: true });
    await flushPromises();
    await botaoComTexto(
      wrapper.find('[data-card-arquivar]'),
      'CRM_CARD.ARQUIVAR.BOTAO'
    ).trigger('click');
    await flushPromises();
    expect(dialogos.abertos.at(-1)).toBe('CRM_CARD.ARQUIVAR.TITULO');
    expect(wrapper.emitted('archive')).toBeUndefined();
    wrapper
      .findAllComponents(DialogStub)
      .find(dialogo => dialogo.props('title') === 'CRM_CARD.ARQUIVAR.TITULO')
      .vm.$emit('confirm');
    expect(wrapper.emitted('archive')).toHaveLength(1);
  });

  it('Arquivar avisa a reunião marcada, que continua marcada (#2091)', async () => {
    const api = (await import('dashboard/api/crmKanban')).default;
    api.upcomingMeetings.mockResolvedValueOnce({
      data: {
        payload: {
          timezone: 'America/Sao_Paulo',
          cards: [{ card_id: 5, starts_at: '2026-10-24T10:00:00-03:00' }],
        },
      },
    });
    const wrapper = montar({ canDeleteCards: true });
    await flushPromises();
    await botaoComTexto(
      wrapper.find('[data-card-arquivar]'),
      'CRM_CARD.ARQUIVAR.BOTAO'
    ).trigger('click');
    await flushPromises();

    expect(api.upcomingMeetings).toHaveBeenCalledWith([5]);
    expect(wrapper.find('[data-aviso-reuniao]').text()).toContain(
      'CRM_CARD.ARQUIVAR.REUNIAO'
    );
    expect(wrapper.emitted('archive')).toBeUndefined();
  });

  // #1874 — arquivar tem chave própria: quem mexe no card sem ela não vê o Arquivar.
  it('sem Arquivar cards, a gaveta não oferece arquivar', async () => {
    const wrapper = montar({ canManageCards: true, canDeleteCards: false });
    await flushPromises();
    expect(wrapper.find('[data-card-arquivar]').exists()).toBe(false);
  });

  it('retorno atrasado vira o próximo passo com "Marcar como feito"', async () => {
    const atrasado = {
      id: 3,
      title: 'Ligar para confirmar',
      status: 'overdue',
      due_at: '2026-01-01T10:00:00Z',
    };
    const wrapper = montar({ followUps: [atrasado] });
    await flushPromises();
    expect(wrapper.find('[data-card-proximo]').attributes('data-passo')).toBe(
      'retorno_atrasado'
    );
    await clicar(wrapper, '[data-passo-principal]');
    expect(wrapper.emitted('completeFollowUp')).toEqual([[atrasado]]);
  });

  it('cliente esperando resposta abre a conversa pelo botão azul', async () => {
    const wrapper = montar({
      card: {
        ...cardBase,
        conversation: { id: 9, display_id: 42, waiting_since: 1792000000 },
      },
    });
    await flushPromises();
    expect(wrapper.find('[data-card-proximo]').attributes('data-passo')).toBe(
      'espera'
    );
    await clicar(wrapper, '[data-passo-principal]');
    expect(navigate).toHaveBeenCalledWith({
      name: 'inbox_conversation',
      params: { accountId: '1', conversation_id: 42 },
    });
  });

  it('sem o funil do card, não mostra os botões da sugestão (PM-08)', async () => {
    const sugestao = { id: 4, to_stage_id: 11, to_stage_name: 'Em conversa' };
    window.globalConfig = { CRM_AI_ENABLED: 'true' };
    const wrapper = montar({
      card: { ...cardBase, can_edit: false, ai_suggestion: sugestao },
    });
    await flushPromises();
    expect(wrapper.find('[data-card-proximo]').attributes('data-passo')).toBe(
      'sugestao'
    );
    expect(wrapper.find('[data-passo-principal]').text()).toContain(
      'CRM_CARD.PASSO.VER_ETAPA'
    );
    expect(wrapper.find('[data-passo-outro]').exists()).toBe(false);
    delete window.globalConfig;
  });

  // #2150 — a sugestão de etapa é de quem tem crm_manage_ai: sem a chave, nada
  // dela aparece e a gaveta nem pede ao servidor.
  it('sem crm_manage_ai, não mostra nem pede a sugestão de etapa', async () => {
    const api = (await import('dashboard/api/crmKanban')).default;
    api.getCurrentAiSuggestion.mockClear();
    const sugestao = { id: 4, to_stage_id: 11, to_stage_name: 'Em conversa' };
    window.globalConfig = { CRM_AI_ENABLED: 'true' };
    const comSugestao = montar({
      card: { ...cardBase, ai_suggestion: sugestao },
    });
    await flushPromises();
    expect(
      comSugestao.find('[data-card-proximo]').attributes('data-passo')
    ).toBe('sugestao');

    const wrapper = montar({
      canManageAi: false,
      card: { ...cardBase, ai_suggestion: sugestao },
    });
    await flushPromises();
    expect(
      wrapper.find('[data-card-proximo]').attributes('data-passo')
    ).not.toBe('sugestao');
    expect(wrapper.find('[data-resumo-sugestao]').exists()).toBe(false);

    const semInicial = montar({ canManageAi: false });
    await flushPromises();
    expect(semInicial.find('[data-card-proximo]').exists()).toBe(true);
    expect(api.getCurrentAiSuggestion).not.toHaveBeenCalled();
    delete window.globalConfig;
  });

  // IA entende a conversa F3: a sugestão de fechar usa o mesmo cartão, com o
  // texto dela (o que acabou e por quê) e o botão Encerrar, em vez de "Mover".
  it('sugestão de fechar: frase do fim, aviso do retorno e Encerrar', async () => {
    const api = (await import('dashboard/api/crmKanban')).default;
    const sugestao = {
      id: 7,
      to_stage_id: 10,
      to_stage_name: 'Novo',
      reasoning: 'Disse que vai pensar.',
      fechar: { resultado: 'perdido', motivo: 'adiou' },
    };
    window.globalConfig = { CRM_AI_ENABLED: 'true' };
    const wrapper = montar({ card: { ...cardBase, ai_suggestion: sugestao } });
    await flushPromises();
    const cartao = wrapper.find('[data-card-proximo]');
    expect(cartao.attributes('data-passo')).toBe('sugestao');
    expect(cartao.text()).toContain('CRM_CARD.FECHAR_SUGESTAO.FRASE.PERDIDO');
    expect(cartao.text()).toContain('CRM_CARD.FECHAR_SUGESTAO.RETORNO');
    expect(cartao.text()).not.toContain('CRM_CARD.PASSO.SUGESTAO');
    expect(wrapper.find('[data-passo-principal]').text()).toContain(
      'CRM_CARD.FECHAR_SUGESTAO.ENCERRAR'
    );
    await clicar(wrapper, '[data-passo-principal]');
    expect(api.acceptAiSuggestion).toHaveBeenCalledWith(7);
    expect(alertSpy).toHaveBeenCalledWith('CRM_CARD.FECHAR_SUGESTAO.FECHOU');
    delete window.globalConfig;
  });

  it('guardNavigation roda a ação na hora quando não há rascunho', async () => {
    const wrapper = montar();
    await flushPromises();
    const acao = vi.fn();
    wrapper.vm.guardNavigation(acao, { leaving: true });
    expect(acao).toHaveBeenCalled();
  });

  it('Esc numa tela interna volta; no resumo fecha a gaveta', async () => {
    const wrapper = montar({ initialTab: 'timeline' });
    await flushPromises();
    keyboard.handlers.Escape.action();
    await flushPromises();
    expect(wrapper.find('[data-card-gaveta]').attributes('data-tela')).toBe(
      'resumo'
    );
    keyboard.handlers.Escape.action();
    expect(wrapper.emitted('close')).toHaveLength(1);
  });

  it('criar cliente em dois passos: Continuar só com o cliente resolvido', async () => {
    const wrapper = montar({ mode: 'create', card: null });
    await flushPromises();
    expect(wrapper.find('[data-card-gaveta]').attributes('data-tela')).toBe(
      'criar-1'
    );
    expect(
      wrapper.find('[data-card-principal]').attributes('disabled')
    ).toBeDefined();
    expect(wrapper.find('[data-criacao-stub]').attributes('data-passo')).toBe(
      '1'
    );
  });
  it('nada se repete: o que está no Próximo passo não volta no cartão Agenda', async () => {
    const wrapper = montar({
      followUps: [
        {
          id: 1,
          title: 'Mandar a proposta',
          status: 'pending',
          due_at: '2999-01-02T10:00:00Z',
        },
        {
          id: 2,
          title: 'Ligar para confirmar',
          status: 'overdue',
          due_at: '2026-01-01T10:00:00Z',
        },
        {
          id: 3,
          title: 'Mandar o contrato',
          status: 'pending',
          due_at: '2999-01-05T10:00:00Z',
        },
      ],
    });
    await flushPromises();
    const passo = wrapper.find('[data-card-proximo]');
    expect(passo.attributes('data-passo')).toBe('retorno_atrasado');
    const agenda = wrapper.find('[data-card-parte="agenda"]');
    expect(agenda.text()).not.toContain('Ligar para confirmar');
    expect(agenda.text()).not.toContain('Mandar a proposta');
    expect(agenda.findAll('[data-agenda-item]')).toHaveLength(1);
  });

  it('com tudo no Próximo passo, a Agenda diz "nada mais"', async () => {
    const wrapper = montar({
      followUps: [
        {
          id: 2,
          title: 'Ligar para confirmar',
          status: 'overdue',
          due_at: '2026-01-01T10:00:00Z',
        },
      ],
    });
    await flushPromises();
    const agenda = wrapper.find('[data-card-parte="agenda"]');
    expect(agenda.text()).toContain('CRM_CARD.RESUMO.AGENDA_NADA_MAIS');
    expect(agenda.find('[data-card-abrir="agenda"]').text()).toContain(
      'CRM_CARD.ALTERAR'
    );
  });

  it('negócio encerrado: Reabrir no Próximo passo, sem Ganhou e Perdeu na faixa', async () => {
    const wrapper = montar({ card: { ...cardBase, status: 'won' } });
    await flushPromises();
    expect(wrapper.find('[data-card-proximo]').attributes('data-passo')).toBe(
      'fechado'
    );
    expect(wrapper.find('[data-card-ganhou]').exists()).toBe(false);
    expect(wrapper.find('[data-card-parte="desfecho"]').exists()).toBe(false);
    await clicar(wrapper, '[data-passo-principal]');
    expect(wrapper.emitted('closeDeal')).toEqual([[{ result: 'reopen' }]]);
  });

  it('Ganhou e Perdeu ficam na faixa em qualquer largura (sem esconder no celular)', async () => {
    const wrapper = montar();
    await flushPromises();
    const desfecho = wrapper.find('[data-card-desfecho]');
    expect(desfecho.exists()).toBe(true);
    expect(desfecho.classes()).not.toContain('hidden');
  });

  it('De onde veio fala em palavras simples e a origem única vira um passo só (VC-04)', async () => {
    const wrapper = montar({
      card: {
        ...cardBase,
        campaigns: [
          {
            source: 'meta_ctwa',
            source_id: '1',
            headline: 'Plano anual com 20% off',
          },
        ],
      },
    });
    await flushPromises();
    const linha = wrapper.find('[data-card-mais] [data-mais="origem"]');
    expect(linha.text()).toContain('CRM_CARD.RESUMO.ORIGEM_FRASE');
    expect(linha.text()).not.toContain('CRM_KANBAN.ORIGIN.META_CTWA');
    await clicar(wrapper, '[data-mais="origem"]');
    expect(
      wrapper.find('[data-origem-caminho]').attributes('data-toques')
    ).toBe('1');
    expect(wrapper.find('[data-origem-caminho]').text()).toContain(
      'CRM_CARD.ORIGEM.FONTE.ANUNCIO_WHATSAPP'
    );
    expect(wrapper.text()).not.toContain('CRM_KANBAN.META_SYNC_STATUS');
  });

  it('De onde veio, sem ver os anúncios: só que veio de anúncio, sem nome nem imagem (#2271)', async () => {
    const wrapper = montar({
      card: {
        ...cardBase,
        campaigns: [
          {
            source: 'meta_ctwa',
            source_type: 'ad',
            touched_at: '2026-10-01T12:00:00Z',
            ad_hidden: true,
            headline: 'Plano anual com 20% off',
            ad_thumbnail_url: 'https://thumb.example/ad.jpg',
            ad_preview_url: 'https://preview.example/ad',
          },
        ],
      },
    });
    await flushPromises();
    await clicar(wrapper, '[data-mais="origem"]');
    const caminho = wrapper.find('[data-origem-caminho]');
    expect(caminho.text()).toContain('CRM_CARD.ORIGEM.FONTE.ANUNCIO_WHATSAPP');
    expect(caminho.text()).toContain('CRM_CARD.ORIGEM.ANUNCIO_OCULTO');
    expect(caminho.text()).not.toContain('Plano anual com 20% off');
    expect(caminho.find('[data-crm-origin-ad-preview]').exists()).toBe(false);
    expect(caminho.find('img').exists()).toBe(false);
  });

  it('Novo retorno não mostra erro antes de a pessoa escrever', async () => {
    const wrapper = montar({
      card: {
        ...cardBase,
        conversation_id: 9,
        conversation: { id: 9, display_id: 42 },
      },
    });
    await flushPromises();
    await clicar(wrapper, '[data-card-abrir="agenda"]');
    await clicar(wrapper, '[data-card-principal]');
    await clicar(wrapper, '[data-modo="auto_send_message"]');
    expect(wrapper.text()).not.toContain('CRM_CARD.RETORNO.SEU_TEXTO_FALTA');
    const texto = wrapper.find('[data-retorno-mensagem] textarea');
    await texto.setValue('Oi!');
    await texto.setValue('');
    expect(wrapper.text()).toContain('CRM_CARD.RETORNO.SEU_TEXTO_FALTA');
  });

  // AG-01 e AG-02: a gaveta antiga tinha "Agendar reunião" e o link no rodapé
  // em qualquer estado. Aqui o cartão Agenda, sempre visível, leva aos dois.
  it.each([
    [
      'retorno atrasado',
      {
        followUps: [
          {
            id: 3,
            title: 'Ligar',
            status: 'overdue',
            due_at: '2026-01-01T10:00:00Z',
          },
        ],
      },
    ],
    [
      'cliente esperando',
      {
        card: {
          ...cardBase,
          conversation: { id: 9, display_id: 42, waiting_since: 1792000000 },
        },
      },
    ],
    ['negócio fechado', { card: { ...cardBase, status: 'won' } }],
  ])(
    'sem reunião e com %s, a Agenda abre os dois jeitos de marcar',
    async (_nome, extra) => {
      const wrapper = montar({ meetingsEnabled: true, ...extra });
      await flushPromises();
      await clicar(wrapper, '[data-card-abrir="agenda"]');
      expect(wrapper.find('[data-card-gaveta]').attributes('data-tela')).toBe(
        'agenda'
      );
      expect(wrapper.find('[data-agenda-eu]').exists()).toBe(true);
      expect(wrapper.find('[data-agenda-opcao="link"]').exists()).toBe(true);
      await clicar(wrapper, '[data-agenda-eu]');
      expect(wrapper.find('[data-card-gaveta]').attributes('data-tela')).toBe(
        'reuniao-nova'
      );
      expect(wrapper.emitted('scheduleMeeting')).toBeUndefined();
    }
  );

  it('com a agenda do Google ou da Microsoft e sem página, Marcar reunião abre a tela do Google/Microsoft na gaveta', async () => {
    marcar.jeito = 'externa';
    const wrapper = montar({ meetingsEnabled: true });
    await flushPromises();
    await clicar(wrapper, '[data-card-abrir="agenda"]');
    expect(wrapper.find('[data-agenda-opcao="link"]').exists()).toBe(false);
    await clicar(wrapper, '[data-agenda-eu]');
    expect(wrapper.find('[data-card-gaveta]').attributes('data-tela')).toBe(
      'reuniao-nova'
    );
    expect(wrapper.find('[data-provider-form-stub]').exists()).toBe(true);
    expect(wrapper.find('[data-reuniao-jeito]').exists()).toBe(false);
    // Enviando, a tela não volta nem fecha (a resposta precisa dela aberta).
    wrapper
      .findComponent({ name: 'CrmProviderMeetingForm' })
      .vm.$emit('saving', true);
    await flushPromises();
    await clicar(wrapper, '[data-card-voltar]');
    expect(wrapper.find('[data-card-gaveta]').attributes('data-tela')).toBe(
      'reuniao-nova'
    );
    wrapper
      .findComponent({ name: 'CrmProviderMeetingForm' })
      .vm.$emit('saving', false);
    await flushPromises();
    expect(wrapper.find('[data-reuniao-frase]').exists()).toBe(true);
    expect(wrapper.emitted('scheduleMeeting')).toBeUndefined();

    await clicar(wrapper, '[data-card-principal]');
    expect(enviarReuniao).toHaveBeenCalledTimes(1);

    wrapper
      .findComponent({ name: 'CrmProviderMeetingForm' })
      .vm.$emit('create', { id: 70 });
    await flushPromises();
    expect(alertSpy).toHaveBeenCalledWith(
      'CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.SUCCESS'
    );
    expect(wrapper.emitted('refreshCard')).toBeTruthy();
    expect(wrapper.find('[data-card-gaveta]').attributes('data-tela')).toBe(
      'agenda'
    );
  });

  it('com página e Google/Microsoft, a tela de reunião deixa escolher o jeito', async () => {
    marcar.caixa = true;
    const wrapper = montar({ meetingsEnabled: true });
    await flushPromises();
    await clicar(wrapper, '[data-card-abrir="agenda"]');
    await clicar(wrapper, '[data-agenda-eu]');
    expect(wrapper.find('[data-reuniao-jeito]').exists()).toBe(true);
    expect(wrapper.find('[data-agenda-form-stub]').exists()).toBe(true);
    const escondido = seletor =>
      (wrapper.find(seletor).attributes('style') || '').includes('none');
    expect(escondido('[data-agenda-form-stub]')).toBe(false);
    expect(escondido('[data-provider-form-stub]')).toBe(true);
    await clicar(wrapper, '[data-reuniao-jeito-opcao="externa"]');
    // Os dois ficam montados: o que foi digitado num não se perde ao trocar.
    expect(escondido('[data-agenda-form-stub]')).toBe(true);
    expect(escondido('[data-provider-form-stub]')).toBe(false);
  });

  it('Mandar o link abre uma tela da gaveta e envia na conversa pelo botão azul', async () => {
    const api = (await import('dashboard/api/crmBookingInvites')).default;
    const convite = {
      id: 5,
      url: 'https://x.test/b/abc',
      text: 'Oi, Mariana! https://x.test/b/abc',
      state: 'created',
      expires_at: '2099-10-16T12:00:00Z',
      booking_page: { id: 3, title: 'Conversa de 30 min' },
    };
    api.index.mockResolvedValue({
      data: { pages: [{ id: 3, title: 'Conversa de 30 min' }], payload: [] },
    });
    api.create.mockResolvedValue({ data: { payload: convite } });
    api.deliver.mockResolvedValue({
      data: { payload: { ...convite, state: 'sent' } },
    });
    const wrapper = montar({
      meetingsEnabled: true,
      card: { ...cardBase, conversation: { id: 9, display_id: 42 } },
    });
    await flushPromises();
    await clicar(wrapper, '[data-card-abrir="agenda"]');
    await clicar(wrapper, '[data-agenda-opcao="link"]');
    await flushPromises();
    expect(wrapper.find('[data-card-gaveta]').attributes('data-tela')).toBe(
      'link-agenda'
    );
    expect(api.create).toHaveBeenCalledWith({
      bookingPageId: 3,
      cardId: 5,
      conversationId: 42,
    });
    expect(wrapper.find('[data-link-frase]').exists()).toBe(true);
    expect(wrapper.find('[data-card-principal]').text()).toContain(
      'CRM_CARD.LINK.ENVIAR'
    );

    await clicar(wrapper, '[data-card-principal]');
    await flushPromises();
    expect(api.deliver).toHaveBeenCalledWith(5, {
      conversationId: 42,
      text: 'Oi, Mariana! https://x.test/b/abc',
    });
    expect(wrapper.find('[data-card-gaveta]').attributes('data-tela')).toBe(
      'agenda'
    );
  });

  it('Mandar o link sem conversa: o botão azul copia o link', async () => {
    const api = (await import('dashboard/api/crmBookingInvites')).default;
    api.index.mockResolvedValue({
      data: {
        pages: [{ id: 3, title: 'Conversa de 30 min' }],
        payload: [
          {
            id: 6,
            url: 'https://x.test/b/def',
            text: 'Oi! https://x.test/b/def',
            state: 'created',
            expires_at: '2099-10-16T12:00:00Z',
            booking_page: { id: 3, title: 'Conversa de 30 min' },
          },
        ],
      },
    });
    const wrapper = montar({ meetingsEnabled: true });
    await flushPromises();
    await clicar(wrapper, '[data-card-abrir="agenda"]');
    await clicar(wrapper, '[data-agenda-opcao="link"]');
    await flushPromises();
    expect(wrapper.find('[data-card-principal]').text()).toContain(
      'CRM_CARD.LINK.COPIAR'
    );
    expect(wrapper.find('[data-link-copiar]').exists()).toBe(false);
    expect(wrapper.find('[data-link-cancelar]').exists()).toBe(true);
  });

  it('sem página de agendamento, a Agenda avisa antes e oferece criar a página ou só um lembrete', async () => {
    marcar.jeito = 'falta';
    const wrapper = montar({ meetingsEnabled: true });
    await flushPromises();
    await clicar(wrapper, '[data-card-abrir="agenda"]');
    expect(wrapper.find('[data-agenda-eu]').exists()).toBe(false);
    expect(wrapper.find('[data-agenda-falta-pagina]').exists()).toBe(true);
    await clicar(wrapper, '[data-agenda-criar-pagina]');
    expect(marcar.abrirPaginas).toHaveBeenCalled();
    await clicar(wrapper, '[data-agenda-so-lembrete]');
    expect(wrapper.find('[data-card-gaveta]').attributes('data-tela')).toBe(
      'retorno-novo'
    );
    expect(
      wrapper.find('[data-modo="reminder_only"]').attributes('aria-pressed')
    ).toBe('true');
  });

  it('sem permissão de criar página, o aviso não oferece criar', async () => {
    marcar.jeito = 'falta';
    marcar.podeCriar = false;
    const wrapper = montar({ meetingsEnabled: true });
    await flushPromises();
    await clicar(wrapper, '[data-card-abrir="agenda"]');
    expect(wrapper.find('[data-agenda-criar-pagina]').exists()).toBe(false);
    expect(wrapper.find('[data-agenda-so-lembrete]').exists()).toBe(true);
  });

  it('sem a flag do link, a Agenda não mostra um cartão de link sem botão', async () => {
    link.ligado = false;
    const wrapper = montar({ meetingsEnabled: true });
    await flushPromises();
    await clicar(wrapper, '[data-card-abrir="agenda"]');
    expect(wrapper.find('[data-agenda-eu]').exists()).toBe(true);
    expect(wrapper.find('[data-agenda-opcao="link"]').exists()).toBe(false);
  });

  it('só com o link ligado, a Agenda mostra só o link', async () => {
    const wrapper = montar({ meetingsEnabled: false });
    await flushPromises();
    await clicar(wrapper, '[data-card-abrir="agenda"]');
    expect(wrapper.find('[data-agenda-eu]').exists()).toBe(false);
    expect(wrapper.find('[data-agenda-opcao="link"]').exists()).toBe(true);
  });

  it('sem permissão, a Agenda é só para ver: sem jeitos de marcar nem botão azul', async () => {
    const wrapper = montar({ meetingsEnabled: true, canManageCards: false });
    await flushPromises();
    expect(wrapper.find('[data-card-abrir="agenda"]').text()).toContain(
      'CRM_CARD.VER'
    );
    await clicar(wrapper, '[data-card-abrir="agenda"]');
    expect(wrapper.find('[data-agenda-eu]').exists()).toBe(false);
    expect(wrapper.find('[data-agenda-opcao="link"]').exists()).toBe(false);
    expect(wrapper.find('[data-card-principal]').text()).toContain(
      'CRM_CARD.VOLTAR'
    );
  });

  it('outra caixa fora das 24 horas: idioma por nome e a prévia não mostra o nome como mensagem', async () => {
    const api = (await import('dashboard/api/crmKanban')).default;
    api.getFollowUpMessagingWindow.mockResolvedValue({
      data: {
        requires_template: true,
        whatsapp_api_inbox: false,
        whatsapp_native_inbox: false,
      },
    });
    const wrapper = montar({
      card: {
        ...cardBase,
        conversation_id: 9,
        conversation: { id: 9, display_id: 42 },
      },
    });
    await flushPromises();
    await clicar(wrapper, '[data-card-abrir="agenda"]');
    await clicar(wrapper, '[data-card-principal]');
    await clicar(wrapper, '[data-modo="auto_send_message"]');
    await clicar(wrapper, '[data-retorno-quando] button');
    await flushPromises();
    expect(wrapper.find('[data-janela]').attributes('data-janela')).toBe(
      'JANELA.SO_PRONTA_DIGITAR'
    );
    expect(wrapper.find('[data-campo-idioma] [role="combobox"]').exists()).toBe(
      true
    );
    expect(wrapper.find('input[placeholder="pt_BR"]').exists()).toBe(false);
    await wrapper
      .find('[data-retorno-mensagem] input')
      .setValue('retomar_conversa');
    await flushPromises();
    const previa = wrapper.find('[data-card-previa-retorno]');
    expect(previa.find('[data-previa-pronta-sem-texto]').exists()).toBe(true);
    expect(previa.find('.bg-n-blue-9').exists()).toBe(false);
    api.getFollowUpMessagingWindow.mockResolvedValue({ data: {} });
  });

  it('os cartões do resumo ficam sempre na mesma ordem, com ou sem reunião', async () => {
    const ordem = wrapper =>
      wrapper
        .findAll('[data-card-parte]')
        .map(cartao => cartao.attributes('data-card-parte'));
    const sem = montar({ meetingsEnabled: true });
    await flushPromises();
    const reunioes = (await import('dashboard/api/crmMeetings')).default;
    reunioes.index.mockResolvedValueOnce({ data: { payload: [{ id: 8 }] } });
    reunioes.show.mockResolvedValueOnce({
      data: {
        payload: {
          id: 8,
          title: 'Apresentação',
          status: 'scheduled',
          starts_at: '2999-10-13T18:00:00Z',
        },
      },
    });
    const com = montar({ meetingsEnabled: true });
    await flushPromises();
    expect(
      com.find('[data-card-parte="agenda"] [data-card-abrir]').text()
    ).toContain('CRM_CARD.ALTERAR');
    expect(ordem(sem)).toEqual(['contato', 'negocio', 'agenda', 'conversa']);
    expect(ordem(com)).toEqual(ordem(sem));
  });

  it('"Onde está no funil" usa o quadro das telas de funil, com o cliente na coluna dele', async () => {
    const wrapper = montar({ card: { ...cardBase, stage_id: 11 } });
    await flushPromises();
    const quadro = wrapper.find('[data-card-lado] [data-funil-quadro]');
    expect(quadro.exists()).toBe(true);
    const colunas = quadro.findAll('[data-coluna]');
    expect(colunas.map(coluna => coluna.attributes('data-coluna'))).toEqual([
      'Novo contato',
      'Em conversa',
    ]);
    expect(colunas[1].attributes('aria-current')).toBe('true');
    expect(colunas[1].find('[data-chegando]').text()).toContain(
      'Mariana Costa'
    );
    expect(colunas[0].find('[data-chegando]').exists()).toBe(false);
  });

  it('Agenda: um botão azul só, o Marcar retorno do rodapé', async () => {
    const wrapper = montar({ meetingsEnabled: true });
    await flushPromises();
    await clicar(wrapper, '[data-card-abrir="agenda"]');
    expect(wrapper.find('[data-agenda-retornos]').exists()).toBe(true);
    expect(wrapper.find('[data-card-principal]').text()).toContain(
      'CRM_CARD.AGENDA.NOVO_LEMBRETE'
    );
    expect(
      wrapper
        .findAll('[data-tela="agenda"] button')
        .filter(botao => botao.classes().includes('bg-n-blue-9'))
    ).toHaveLength(0);
  });

  it('link desligado pelo servidor some da Agenda enquanto o card está aberto', async () => {
    const api = (await import('dashboard/api/crmBookingInvites')).default;
    api.index.mockRejectedValueOnce({
      response: { status: 404, data: { error: 'crm.booking_v2.disabled' } },
    });
    const wrapper = montar({ meetingsEnabled: true });
    await flushPromises();
    await clicar(wrapper, '[data-card-abrir="agenda"]');
    await flushPromises();
    expect(wrapper.find('[data-agenda-opcao="link"]').exists()).toBe(false);
    await clicar(wrapper, '[data-card-voltar]');
    await clicar(wrapper, '[data-card-abrir="agenda"]');
    await flushPromises();
    expect(wrapper.find('[data-agenda-opcao="link"]').exists()).toBe(false);
    expect(wrapper.find('[data-agenda-eu]').exists()).toBe(true);
  });

  it('fora das 24 horas sem a mensagem pronta: a prévia não mostra balão livre e o rodapé diz o que falta', async () => {
    const api = (await import('dashboard/api/crmKanban')).default;
    api.getFollowUpMessagingWindow.mockResolvedValue({
      data: {
        requires_template: true,
        whatsapp_api_inbox: false,
        whatsapp_native_inbox: false,
      },
    });
    const wrapper = montar({
      card: {
        ...cardBase,
        conversation_id: 9,
        conversation: { id: 9, display_id: 42 },
      },
    });
    await flushPromises();
    await clicar(wrapper, '[data-card-abrir="agenda"]');
    await clicar(wrapper, '[data-card-principal]');
    expect(wrapper.find('[data-card-rodape-falta]').text()).toContain(
      'CRM_CARD.RETORNO.FALTA.FRASE'
    );
    await clicar(wrapper, '[data-modo="auto_send_message"]');
    await clicar(wrapper, '[data-retorno-quando] button');
    await flushPromises();
    await wrapper
      .find('[data-retorno-mensagem] textarea')
      .setValue('Oi, Mariana!');
    await wrapper.find('[data-retorno-nome] input').setValue('Retomar');
    const previa = wrapper.find('[data-card-previa-retorno]');
    expect(previa.find('[data-previa-pronta-falta]').text()).toContain(
      'CRM_CARD.RETORNO.PRONTA_FALTA_DIGITAR'
    );
    expect(previa.find('[data-previa-balao]').exists()).toBe(false);
    const principal = wrapper.find('[data-card-principal]');
    expect(principal.attributes('disabled')).toBeDefined();
    expect(wrapper.find('[data-card-rodape-falta]').exists()).toBe(true);

    await wrapper
      .find('[data-retorno-mensagem] input')
      .setValue('retomar_conversa');
    await flushPromises();
    expect(previa.find('[data-previa-pronta-falta]').exists()).toBe(false);
    expect(wrapper.find('[data-card-rodape-falta]').exists()).toBe(false);
    await clicar(wrapper, '[data-card-principal]');
    expect(wrapper.emitted('createFollowUp')[0][0].metadata).toMatchObject({
      template_name: 'retomar_conversa',
      template_language: 'pt_BR',
    });
    api.getFollowUpMessagingWindow.mockResolvedValue({ data: {} });
  });

  it('troca quem cuida na própria gaveta, sem quem não tem o funil', async () => {
    const api = (await import('dashboard/api/crmKanban')).default;
    api.getOwnerOptions.mockResolvedValue({
      data: { payload: { cards: { 5: [3] } } },
    });
    const wrapper = montar();
    await flushPromises();
    await clicar(wrapper, '[data-resumo-dono]');
    const escolha = escolhaDoDono(wrapper);
    expect(escolha.props('options').map(opcao => opcao.value)).toEqual([2, 4]);
    expect(
      wrapper.find('[data-card-principal]').attributes('disabled')
    ).toBeDefined();
    escolha.vm.$emit('update:modelValue', 4);
    await flushPromises();
    expect(
      wrapper
        .find('[data-card-lado] [data-funil-previa]')
        .attributes('data-selo')
    ).toBe('previa');
    await clicar(wrapper, '[data-card-principal]');
    expect(wrapper.emitted('save')[0][0]).toEqual({ owner_id: 4 });
  });

  it('sem permissão, quem cuida é só leitura', async () => {
    const wrapper = montar({ canManageCards: false });
    await flushPromises();
    await clicar(wrapper, '[data-resumo-dono]');
    expect(escolhaDoDono(wrapper)).toBeUndefined();
    expect(wrapper.text()).toContain('Ana Souza');
  });

  it('a conversa abre por um lugar só: no cartão, ou no Responder quando o cliente espera', async () => {
    const comConversa = {
      ...cardBase,
      conversation: { id: 9, display_id: 42 },
    };
    const calmo = montar({ card: comConversa });
    await flushPromises();
    expect(calmo.findAll('[data-resumo-abrir-conversa]')).toHaveLength(1);
    const esperando = montar({
      card: {
        ...comConversa,
        conversation: { id: 9, display_id: 42, waiting_since: 1792000000 },
      },
    });
    await flushPromises();
    expect(esperando.find('[data-card-proximo]').attributes('data-passo')).toBe(
      'espera'
    );
    expect(esperando.find('[data-resumo-abrir-conversa]').exists()).toBe(false);
  });

  it('o lado do resumo mostra só o quadro do funil', async () => {
    const wrapper = montar();
    await flushPromises();
    const lado = wrapper.find('[data-card-lado]');
    expect(lado.find('[data-funil-quadro]').exists()).toBe(true);
    expect(lado.findAll('[data-funil-previa]')).toHaveLength(1);
    expect(lado.text()).not.toContain('CRM_CARD.LADO.EM_RESUMO');
  });

  it('Lembrete: o nome vem primeiro, vazio, e a escolha da Agenda já chega marcada', async () => {
    const wrapper = montar({ meetingsEnabled: true });
    await flushPromises();
    await clicar(wrapper, '[data-card-abrir="agenda"]');
    await clicar(wrapper, '[data-agenda-opcao="lembrete"]');
    const tela = wrapper.find('[data-tela="retorno-novo"]');
    expect(tela.find('input').attributes('placeholder')).toBe(
      'CRM_CARD.RETORNO.TITULO_EXEMPLO'
    );
    expect(tela.find('[data-retorno-nome] input').element.value).toBe('');
    expect(wrapper.find('[data-card-heroi]').text()).toContain(
      'CRM_CARD.RETORNO.TITULO_LEMBRETE'
    );
    expect(wrapper.find('[data-card-rodape-falta]').text()).toContain(
      'CRM_CARD.RETORNO.FALTA.FRASE'
    );
  });

  it('Mensagem no dia só com conversa ligada', async () => {
    const semConversa = montar({ meetingsEnabled: true });
    await flushPromises();
    await clicar(semConversa, '[data-card-abrir="agenda"]');
    expect(
      semConversa.find('[data-agenda-opcao="mensagem"]').attributes('disabled')
    ).toBeDefined();
  });

  it('Adiar um retorno usa a mesma remarcação do calendário', async () => {
    const wrapper = montar({
      followUps: [
        {
          id: 7,
          title: 'Ligar',
          status: 'pending',
          due_at: '2999-01-02T10:00:00Z',
        },
      ],
    });
    await flushPromises();
    await clicar(wrapper, '[data-card-abrir="agenda"]');
    await clicar(wrapper, '[data-retorno-adiar]');
    await clicar(wrapper, '[data-retorno-adiar-quando] button');
    await clicar(wrapper, '[data-retorno-adiar-confirma]');
    expect(despachar.fn).toHaveBeenCalledWith(
      'crmKanban/rescheduleFollowUp',
      expect.objectContaining({ id: 7 })
    );
    expect(wrapper.emitted('refreshCard')).toBeTruthy();
  });

  it('Contato e empresa: duas linhas, cada uma abre a sua tela', async () => {
    const wrapper = montar({
      card: { ...cardBase, company: { id: 3, name: 'Padaria Bom Dia' } },
    });
    await flushPromises();
    const cartao = wrapper.find('[data-card-parte="contato"]');
    expect(cartao.text()).toContain('CRM_CARD.RESUMO.CONTATO_FRASE');
    expect(cartao.find('[data-resumo-empresa]').text()).toContain(
      'Padaria Bom Dia'
    );
    await clicar(wrapper, '[data-card-abrir="contato"]');
    expect(wrapper.find('[data-card-gaveta]').attributes('data-tela')).toBe(
      'contato'
    );
    await clicar(wrapper, '[data-card-voltar]');
    await clicar(wrapper, '[data-card-abrir="empresa"]');
    expect(wrapper.find('[data-card-gaveta]').attributes('data-tela')).toBe(
      'empresa'
    );
    expect(wrapper.find('[data-painel-stub]').attributes('data-parte')).toBe(
      'empresa'
    );
  });

  it('a empresa não some quando o negócio ainda não tem pessoa', async () => {
    const wrapper = montar({
      card: {
        ...cardBase,
        contact: null,
        company: { id: 3, name: 'Padaria Bom Dia' },
      },
    });
    await flushPromises();
    const cartao = wrapper.find('[data-card-parte="contato"]');
    expect(cartao.text()).toContain('CRM_CARD.RESUMO.SEM_CONTATO');
    expect(cartao.find('[data-resumo-empresa]').text()).toContain(
      'Padaria Bom Dia'
    );
  });

  it('Cliente é o status de quem comprou: selo com "desde" e Desfazer', async () => {
    const wrapper = montar({
      card: {
        ...cardBase,
        contact: {
          ...cardBase.contact,
          contact_type: 'customer',
          customer_since: 1790000000,
        },
      },
    });
    await flushPromises();
    expect(wrapper.find('[data-heroi-cliente]').exists()).toBe(true);
    expect(wrapper.find('[data-resumo-cliente]').exists()).toBe(true);
    expect(wrapper.find('[data-card-heroi]').text()).not.toContain(
      'CRM_CARD.RESUMO.ROTULO'
    );
    expect(wrapper.find('[data-resumo-cliente-acao]').text()).toContain(
      'CRM_CARD.RESUMO.DESFAZER_CLIENTE'
    );
  });

  it('Marcar como cliente pede confirmação e usa a mesma rota da ficha do contato', async () => {
    const wrapper = montar();
    await flushPromises();
    expect(wrapper.find('[data-resumo-cliente]').exists()).toBe(false);
    await clicar(wrapper, '[data-resumo-cliente-acao] button');
    expect(dialogos.abertos.at(-1)).toBe(
      'CONTACTS_LAYOUT.DETAILS.CUSTOMER.MARK_DIALOG.TITLE'
    );
    wrapper
      .findAllComponents({ name: 'Dialog' })
      .find(
        dialogo =>
          dialogo.props('title') ===
          'CONTACTS_LAYOUT.DETAILS.CUSTOMER.MARK_DIALOG.TITLE'
      )
      .vm.$emit('confirm');
    await flushPromises();
    expect(despachar.fn).toHaveBeenCalledWith('contacts/setCustomer', {
      id: 7,
      customer: true,
    });
    expect(wrapper.emitted('refreshCard')).toBeTruthy();
  });

  it('o topo mostra a etapa, sem a palavra cliente para quem não comprou', async () => {
    const wrapper = montar();
    await flushPromises();
    const heroi = wrapper.find('[data-card-heroi]');
    expect(heroi.text()).toContain('Novo contato');
    expect(heroi.find('[data-heroi-cliente]').exists()).toBe(false);
  });

  it('mudar de etapa com um toque na coluna do quadro, com confirmação', async () => {
    const wrapper = montar();
    await flushPromises();
    const colunas = wrapper.findAll(
      '[data-card-lado] [data-funil-quadro-escolher]'
    );
    expect(colunas).toHaveLength(1);
    await colunas[0].trigger('click');
    await flushPromises();
    expect(dialogos.abertos.at(-1)).toBe('CRM_CARD.MOVER.TITULO');
    wrapper
      .findAllComponents({ name: 'Dialog' })
      .find(dialogo => dialogo.props('title') === 'CRM_CARD.MOVER.TITULO')
      .vm.$emit('confirm');
    expect(wrapper.emitted('move')).toEqual([[11]]);
  });

  it('marcar reunião com página acontece na própria gaveta', async () => {
    const wrapper = montar({ meetingsEnabled: true });
    await flushPromises();
    await clicar(wrapper, '[data-card-abrir="agenda"]');
    await clicar(wrapper, '[data-agenda-eu]');
    expect(wrapper.find('[data-tela="reuniao-nova"]').exists()).toBe(true);
    expect(wrapper.find('[data-card-principal]').text()).toContain(
      'CRM_CARD.REUNIAO_NOVA.MARCAR'
    );
  });
});
