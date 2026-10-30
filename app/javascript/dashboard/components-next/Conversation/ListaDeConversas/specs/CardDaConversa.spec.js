import { ref } from 'vue';
import { createStore } from 'vuex';
import { mount, enableAutoUnmount } from '@vue/test-utils';
import CardDaConversa from '../CardDaConversa.vue';
import { criarI18n, emSaoPaulo, FUSO } from './apoio';

// #2202 — o item novo: o mesmo contrato do card antigo (clique, menu, seleção),
// a frase do leitor de tela e as três linhas.
const etapa = ref(null);
vi.mock('dashboard/routes/dashboard/crm/composables/useCrmPermissions', () => ({
  useCrmPermissions: () => ({ canViewCrm: ref(true) }),
}));
vi.mock(
  'dashboard/routes/dashboard/crm/composables/useCrmConversationStages',
  () => ({
    useCrmConversationStage: () => etapa,
  })
);
vi.mock('dashboard/api/crmKanban', () => ({
  default: {
    getPipelines: vi.fn().mockResolvedValue({ data: { payload: [{ id: 1 }] } }),
  },
}));
vi.mock('dashboard/components/widgets/conversation/MessagePreview.vue', () => ({
  default: {
    props: ['message', 'tag'],
    template: '<span data-previa :data-tag="tag">{{ message.content }}</span>',
  },
}));

enableAutoUnmount(afterEach);

const AGORA = emSaoPaulo(2026, 10, 25, 19, 21);
const store = createStore({
  getters: {
    getCurrentUser: () => ({ id: 1, name: 'John' }),
    getCurrentAccountId: () => 1,
    'accounts/getAccount': () => () => ({ id: 1, timezone: FUSO }),
    'inboxes/getInboxes': () => [{ id: 1, channel_type: 'Channel::Whatsapp' }],
    'agents/getAgentById': () => () => ({}),
  },
});

const chat = (extras = {}) => ({
  id: 22,
  timestamp: emSaoPaulo(2026, 10, 25, 16, 58),
  created_at: emSaoPaulo(2026, 10, 25, 16, 50),
  waiting_since: AGORA - 2 * 3600,
  unread_count: 2,
  status: 'open',
  meta: {},
  additional_attributes: {},
  messages: [
    {
      id: 1,
      message_type: 0,
      content: 'Quero fechar o seguro hoje.',
      created_at: AGORA - 3600,
    },
  ],
  ...extras,
});

const montar = (props = {}, provide = {}, opcoes = {}) =>
  mount(CardDaConversa, {
    ...opcoes,
    props: {
      chat: chat(),
      currentContact: { name: 'Marina Costa' },
      inbox: {
        id: 1,
        name: 'WhatsApp Vendas',
        channel_type: 'Channel::Whatsapp',
      },
      showAssignee: true,
      ...props,
    },
    global: {
      plugins: [
        store,
        criarI18n({ CHAT_LIST: { NO_MESSAGES: 'Sem mensagens' } }),
      ],
      stubs: { CustomerBadge: true },
      provide,
    },
  });

describe('CardDaConversa (#2202)', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(AGORA * 1000);
    etapa.value = null;
  });
  afterEach(() => vi.useRealTimers());

  it('três linhas: nome e hora, a prévia com a bolinha, e a espera em vermelho', () => {
    const wrapper = montar();
    expect(wrapper.find('[data-nome]').text()).toBe('Marina Costa');
    expect(wrapper.find('[data-hora]').text()).toBe('16:58');
    expect(wrapper.find('[data-nao-lidas]').text()).toBe('2');
    const sinal = wrapper.find('[data-sinal]');
    expect(sinal.text()).toBe('Esperando há 2 horas');
    expect(sinal.classes()).toContain('text-n-ruby-11');
  });

  it('sem nome e sem telefone: o e-mail; sem e-mail, o identificador (no texto e no leitor de tela)', () => {
    const comEmail = montar({
      currentContact: { email: 'cliente@exemplo.test' },
    });
    expect(comEmail.find('[data-nome]').text()).toBe('cliente@exemplo.test');
    expect(
      comEmail.find('[data-card-texto]').attributes('aria-label')
    ).toContain('cliente@exemplo.test');
    expect(comEmail.find('.i-lucide-user').exists()).toBe(true);
    const soId = montar({ currentContact: { identifier: 'id-externo-7' } });
    expect(soId.find('[data-nome]').text()).toBe('id-externo-7');
  });

  it('avatar de 36 px no celular e 40 no resto, por classe (sem medir a janela)', () => {
    const wrapper = montar();
    expect(wrapper.find('[data-avatar="36"]').classes()).toContain('md:hidden');
    expect(wrapper.find('[data-avatar="40"]').classes()).toEqual(
      expect.arrayContaining(['hidden', 'md:inline-flex'])
    );
  });

  it('a prévia dentro do botão é span', () => {
    const wrapper = montar();
    expect(wrapper.find('[data-previa]').attributes('data-tag')).toBe('span');
  });

  it('contato que só tem o número: telefone legível no nome e ícone de pessoa no avatar', () => {
    const wrapper = montar({
      currentContact: { name: '5511955554444', phone_number: '+5511955554444' },
    });
    expect(wrapper.find('[data-nome]').text()).toBe('+55 11 95555-4444');
    expect(wrapper.find('.i-lucide-user').exists()).toBe(true);
  });

  it('nome gravado que é outro número: fica no nome, e o Avatar mostra o ícone de pessoa (#2255)', () => {
    const wrapper = montar({
      currentContact: {
        name: '+55 11 93333-2222',
        phone_number: '+5511955554444',
      },
    });
    expect(wrapper.find('[data-nome]').text()).toBe('+55 11 93333-2222');
    expect(wrapper.find('.i-lucide-user').exists()).toBe(true);
    expect(wrapper.find('.select-none').exists()).toBe(false);
  });

  it('raiz div.conversation e o mesmo contrato do card antigo (click e contextmenu)', async () => {
    const wrapper = montar({ isActiveChat: true });
    expect(wrapper.classes()).toEqual(
      expect.arrayContaining(['conversation', 'active'])
    );
    await wrapper.trigger('click');
    await wrapper.trigger('contextmenu');
    expect(wrapper.emitted('click')).toHaveLength(1);
    expect(wrapper.emitted('contextmenu')).toHaveLength(1);
  });

  it('frase única para o leitor de tela', () => {
    const rotulo = montar().find('[data-card-texto]').attributes('aria-label');
    expect(rotulo).toBe(
      'Marina Costa. Última mensagem: 16:58. Marina Costa escreveu: Quero fechar o seguro hoje. 2 mensagens novas. Esperando há 2 horas.'
    );
  });

  it('robô com o selo "IA" e "Gabriela, assistente de IA" para o leitor', () => {
    const wrapper = montar({
      chat: chat({
        unread_count: 0,
        waiting_since: 0,
        messages: [
          {
            id: 2,
            message_type: 1,
            sender_type: 'AgentBot',
            sender: { name: 'Gabriela', type: 'agent_bot' },
            content: 'Já aviso a equipe.',
          },
        ],
      }),
    });
    expect(wrapper.find('[data-prefixo]').text()).toBe('GabrielaIA:');
    expect(
      wrapper.find('[data-card-texto]').attributes('aria-label')
    ).toContain('Gabriela, assistente de IA, escreveu: Já aviso a equipe.');
  });

  it('a etapa é texto (não link) e fica numa peça que desce inteira', () => {
    etapa.value = {
      stage_name: 'Documentação pendente de assinatura',
      pipeline_name: 'Viagem',
      subjects_count: 1,
    };
    const wrapper = montar();
    const elemento = wrapper.find('[data-etapa]');
    expect(elemento.text()).toBe('Documentação pendente de assinatura');
    expect(elemento.element.tagName).toBe('SPAN');
    expect(elemento.classes()).toContain('whitespace-nowrap');
    expect(wrapper.find('[data-linha="3"]').classes()).toContain('flex-wrap');
  });

  it('o relógio recalcula a espera sem mudar a conversa', async () => {
    const wrapper = montar({ chat: chat({ waiting_since: AGORA - 14 * 60 }) });
    expect(wrapper.find('[data-sinal]').attributes('data-faixa')).toBe('calma');
    await vi.advanceTimersByTimeAsync(60000);
    expect(wrapper.find('[data-sinal]').attributes('data-faixa')).toBe(
      'atencao'
    );
  });

  it('âmbar: 11 no fundo da lista; 12 no item aberto, para passar no AA (medido: 4,30 com o 11)', () => {
    const espera = chat({ waiting_since: AGORA - 40 * 60 });
    const normal = montar({ chat: espera }).find('[data-sinal]');
    expect(normal.classes()).toContain('text-n-amber-11');
    const aberto = montar({ chat: espera, isActiveChat: true }).find(
      '[data-sinal]'
    );
    expect(aberto.classes()).toContain('text-n-amber-12');
    expect(aberto.classes()).not.toContain('text-n-amber-11');
  });

  describe('no resultado da busca (#2211)', () => {
    it('sem a caixa de seleção, mesmo marcada', () => {
      const naLista = montar({ selected: true });
      expect(naLista.find('input[type="checkbox"]').exists()).toBe(true);
      const naBusca = montar({ selected: true }, { cardNaBusca: true });
      expect(naBusca.find('input[type="checkbox"]').exists()).toBe(false);
    });

    it('o card é um botão nativo (Tab chega, Enter e Espaço abrem) e o clique dele abre a conversa', async () => {
      const wrapper = montar(
        {},
        { cardNaBusca: true },
        { attachTo: document.body }
      );
      const botao = wrapper.find('[data-card-texto]');
      // Na ordem do Tab: botão habilitado, sem tabindex negativo, nada escondido em volta.
      expect(botao.element.disabled).toBe(false);
      expect(botao.element.closest('[aria-hidden="true"], [inert]')).toBeNull();
      botao.element.focus();
      expect(document.activeElement).toBe(botao.element);
      // Enter e Espaço num <button> o navegador transforma em clique (o jsdom não simula essa
      // ativação; a jornada da demo aperta Tab e Enter de verdade).
      expect(botao.element.tagName).toBe('BUTTON');
      expect(botao.attributes('type')).toBe('button');
      expect(botao.attributes('tabindex')).toBeUndefined();
      await botao.trigger('click');
      expect(wrapper.emitted('click')).toHaveLength(1);
    });
  });
});
