import { shallowMount } from '@vue/test-utils';
import { REPLY_EDITOR_MODES } from 'dashboard/components/widgets/WootWriter/constants';
import { nextTick } from 'vue';
import { createStore } from 'vuex';
import ReplyBox from '../ReplyBox.vue';
import WhatsappTemplates from '../WhatsappTemplates/Modal.vue';
import JanelaDeEmojis from 'dashboard/components-next/emoji/JanelaDeEmojis.vue';

// #2113: a conversa do Instagram com a cara do Direct vem da MessagesView (provide);
// aqui ela fica desligada, como sem a tela, e cada teste do Instagram a liga.
const conversaDoInstagram = vi.hoisted(() => ({ ligada: false }));
vi.mock(
  'dashboard/components-next/conversa-canal/instagram/useConversaDoInstagram',
  async original => {
    const { computed } = await import('vue');
    return {
      ...(await original()),
      useInstagramDaConversa: () => ({
        ligado: computed(() => conversaDoInstagram.ligada),
        fuso: computed(() => undefined),
        contato: computed(() => null),
      }),
    };
  }
);

const CHANNELS = [
  { name: 'WhatsApp Cloud', inbox: { channel_type: 'Channel::Whatsapp' } },
  {
    name: 'Twilio WhatsApp',
    inbox: { channel_type: 'Channel::TwilioSms', medium: 'whatsapp' },
  },
  { name: 'API', inbox: { channel_type: 'Channel::Api' } },
  { name: 'Instagram', inbox: { channel_type: 'Channel::Instagram' } },
  { name: 'TikTok', inbox: { channel_type: 'Channel::Tiktok' } },
  { name: 'Facebook', inbox: { channel_type: 'Channel::FacebookPage' } },
  { name: 'Line', inbox: { channel_type: 'Channel::Line' } },
  { name: 'Telegram', inbox: { channel_type: 'Channel::Telegram' } },
  { name: 'Email', inbox: { channel_type: 'Channel::Email' } },
  { name: 'Web widget', inbox: { channel_type: 'Channel::WebWidget' } },
];

const exemptFromMessagingWindow = name =>
  ['WhatsApp Cloud', 'Twilio WhatsApp', 'API'].includes(name);

const REPLIABLE = {
  id: 1,
  inbox_id: 1,
  can_reply: true,
  status: 'open',
  meta: { sender: { id: 2 } },
  messages: [],
};

const buildStore = ({
  inbox,
  chat,
  templates,
  drafts = {},
  inboxes,
  isMetaMessageSendingDisabled = false,
  features = [],
}) =>
  createStore({
    state: {
      chat: { ...REPLIABLE, ...chat },
      replyEditorMode: REPLY_EDITOR_MODES.REPLY,
      drafts: { ...drafts },
    },
    mutations: {
      selectChat: (s, c) => {
        s.chat = c;
      },
      setReplyEditorMode: (s, mode) => {
        s.replyEditorMode = mode;
      },
      setDraft: (s, { key, message }) => {
        s.drafts = { ...s.drafts, [key]: message };
      },
    },
    actions: {
      'draftMessages/setReplyEditorMode': ({ commit }, { mode }) =>
        commit('setReplyEditorMode', mode),
      'draftMessages/set': ({ commit }, payload) => commit('setDraft', payload),
      'draftMessages/delete': ({ commit }, { key }) =>
        commit('setDraft', { key }),
    },
    getters: {
      getSelectedChat: s => s.chat,
      getCurrentUser: () => ({ id: 7, name: 'Agent', accounts: [] }),
      getCurrentAccountId: () => 1,
      getMessageSignature: () => '',
      getUISettings: () => ({}),
      getLastEmailInSelectedChat: () => null,
      'globalConfig/get': () => ({}),
      'globalConfig/isMetaMessageSendingDisabled': () =>
        isMetaMessageSendingDisabled,
      'inboxes/getInbox': () => inboxId => ({
        id: inboxId,
        ...(inboxes?.[inboxId] || inbox),
      }),
      'inboxes/getWhatsAppTemplates': () => () => templates,
      'contacts/getContact': () => () => ({}),
      'draftMessages/get': s => key => s.drafts[key] || '',
      'draftMessages/getReplyEditorMode': s => s.replyEditorMode,
      'accounts/isFeatureEnabledonAccount': () => (_conta, flag) =>
        features.includes(flag),
      getConversationById: s => id => (s.chat.id === id ? s.chat : null),
      'accounts/getAccount': () => () => ({}),
      'portals/allPortals': () => [],
      'integrations/getUIFlags': () => ({ isFetching: false }),
    },
  });

const mountWith = ({
  inbox,
  chat,
  templates = [{ name: 'greeting' }],
  drafts,
  inboxes,
  isMetaMessageSendingDisabled,
  stubs = {},
  attachTo,
  features,
}) => {
  const store = buildStore({
    inbox,
    chat,
    templates,
    drafts,
    inboxes,
    isMetaMessageSendingDisabled,
    features,
  });
  const wrapper = shallowMount(ReplyBox, {
    global: {
      plugins: [store],
      mocks: { $t: key => key },
      // The bottom panel sits inside a <Transition>, which shallowMount stubs
      // without rendering its children.
      stubs: { transition: false, ...stubs },
    },
    attachTo,
  });
  return { wrapper, store };
};

const topPanel = wrapper =>
  wrapper.findComponent({ name: 'ReplyTopPanel' }).props();
const bottomPanel = wrapper =>
  wrapper.findComponent({ name: 'ReplyBottomPanel' }).props();
const editor = wrapper =>
  wrapper.findComponent({ name: 'WootMessageEditor' }).props();

// #1895: a janela de emojis de verdade, aberta pelo botão do rosto da barra de baixo.
const REAL_EMOJI_WINDOW = {
  ReplyBottomPanel: false,
  NextButton: false,
  Button: false,
  JanelaDeEmojis: false,
  TeleportWithDirection: { template: '<div><slot /></div>' },
};
const mountWithEmojiWindow = () =>
  mountWith({
    inbox: { channel_type: 'Channel::Whatsapp' },
    stubs: REAL_EMOJI_WINDOW,
    attachTo: document.body,
  }).wrapper;
const faceButton = wrapper => wrapper.find('[data-emoji-da-resposta]');
const emojiWindow = () => document.querySelector('[data-janela-de-emojis]');

describe('ReplyBox', () => {
  describe('emoji window opened by the face button (#1895)', () => {
    let wrapper;

    beforeEach(() => {
      wrapper = mountWithEmojiWindow();
    });

    afterEach(() => {
      wrapper.unmount();
      document.body.innerHTML = '';
    });

    it('opens on a real click and inserts the chosen emoji', async () => {
      expect(emojiWindow()).toBeNull();
      await faceButton(wrapper).trigger('click');
      expect(emojiWindow()).not.toBeNull();

      const emoji = emojiWindow().querySelector('.grid button');
      emoji.click();
      await nextTick();
      expect(editor(wrapper).updateSelectionWith).toBe(
        emoji.textContent.trim()
      );
    });

    it('anchors on the bottom bar that holds the face button', async () => {
      await faceButton(wrapper).trigger('click');
      const janela = wrapper.findComponent(JanelaDeEmojis);
      expect(janela.props('ancora').classList.contains('left-wrap')).toBe(true);
      expect(janela.props('ancora').contains(faceButton(wrapper).element)).toBe(
        true
      );
    });

    it('closes on a click outside', async () => {
      await faceButton(wrapper).trigger('click');
      document.body.dispatchEvent(
        new PointerEvent('pointerdown', { bubbles: true })
      );
      document.body.click();
      await nextTick();
      expect(emojiWindow()).toBeNull();
    });

    it('closes on a second click on the face button, without reopening', async () => {
      await faceButton(wrapper).trigger('click');
      faceButton(wrapper).element.dispatchEvent(
        new PointerEvent('pointerdown', { bubbles: true })
      );
      await faceButton(wrapper).trigger('click');
      await nextTick();
      expect(emojiWindow()).toBeNull();
      expect(wrapper.vm.showEmojiPicker).toBe(false);
    });

    it('closes on Escape pressed anywhere and gives the focus back', async () => {
      faceButton(wrapper).element.focus();
      await faceButton(wrapper).trigger('click');
      await nextTick();
      expect(document.activeElement.matches('[data-buscar-emoji]')).toBe(true);

      document.dispatchEvent(
        new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })
      );
      await nextTick();
      expect(emojiWindow()).toBeNull();
      expect(document.activeElement).toBe(faceButton(wrapper).element);
    });

    it('closes when the copilot takes over the bottom bar', async () => {
      await faceButton(wrapper).trigger('click');
      wrapper.vm.copilot.showEditor.value = true;
      await nextTick();
      expect(wrapper.vm.showEmojiPicker).toBe(false);
    });
  });

  describe('Instagram incident restriction', () => {
    it('opens in note mode and restores only the private-note draft', async () => {
      const { wrapper, store } = mountWith({
        inbox: { channel_type: 'Channel::Instagram' },
        isMetaMessageSendingDisabled: true,
        drafts: {
          'draft-1-REPLY': 'unsent public reply',
          'draft-1-NOTE': 'incident note',
        },
      });
      await nextTick();

      expect(topPanel(wrapper).mode).toBe(REPLY_EDITOR_MODES.NOTE);
      expect(topPanel(wrapper).isReplyRestricted).toBe(true);
      expect(bottomPanel(wrapper).isOnPrivateNote).toBe(true);
      expect(editor(wrapper).editorId).toBe('draft-1-NOTE');
      expect(wrapper.vm.message).toBe('incident note');
      expect(store.getters['draftMessages/getReplyEditorMode']).toBe(
        REPLY_EDITOR_MODES.NOTE
      );
      expect(store.getters['draftMessages/get']('draft-1-REPLY')).toBe(
        'unsent public reply'
      );
    });

    it('preserves draft ownership when switching to a restricted conversation', async () => {
      const drafts = {
        'draft-1-REPLY': 'conversation A reply',
        'draft-1-NOTE': 'conversation A note',
        'draft-2-REPLY': 'conversation B reply',
        'draft-2-NOTE': 'conversation B note',
      };
      const { wrapper, store } = mountWith({
        inbox: { channel_type: 'Channel::WebWidget' },
        inboxes: {
          1: { channel_type: 'Channel::WebWidget' },
          2: { channel_type: 'Channel::Instagram' },
        },
        drafts,
        isMetaMessageSendingDisabled: true,
      });
      await nextTick();

      store.commit('selectChat', { ...REPLIABLE, id: 2, inbox_id: 2 });
      await nextTick();

      expect(editor(wrapper)).toMatchObject({
        editorId: 'draft-2-NOTE',
        modelValue: 'conversation B note',
      });
      Object.entries(drafts).forEach(([key, message]) => {
        expect(store.getters['draftMessages/get'](key)).toBe(message);
      });
    });
  });

  describe.each(CHANNELS)('$name', ({ name, inbox }) => {
    // #1895: a janela de emojis própria do fork em todos os canais, no lugar da do Chatwoot.
    it('opens the fork emoji window and inserts the chosen emoji', async () => {
      const { wrapper } = mountWith({ inbox });
      expect(wrapper.findComponent(JanelaDeEmojis).exists()).toBe(false);

      bottomPanel(wrapper).toggleEmojiPicker();
      await nextTick();
      const janela = wrapper.findComponent(JanelaDeEmojis);
      expect(janela.exists()).toBe(true);
      expect(wrapper.findComponent({ name: 'EmojiIconPicker' }).exists()).toBe(
        false
      );

      janela.vm.$emit('escolher', '😀');
      await nextTick();
      expect(editor(wrapper).updateSelectionWith).toBe('😀');

      janela.vm.$emit('fechar');
      await nextTick();
      expect(wrapper.findComponent(JanelaDeEmojis).exists()).toBe(false);
    });

    it('locks the composer and hides template sends when a bot owns a pending conversation', () => {
      const { wrapper } = mountWith({
        inbox,
        chat: {
          status: 'pending',
          meta: { sender: { id: 2 }, assignee_type: 'AgentBot' },
        },
      });

      expect(topPanel(wrapper).isReplyRestricted).toBe(true);
      expect(bottomPanel(wrapper).enableWhatsAppTemplates).toBe(false);
      expect(bottomPanel(wrapper).enableContentTemplates).toBe(false);
      // The note composer stays usable — this is a restriction, not a lockout.
      expect(topPanel(wrapper).isEditorDisabled).toBe(false);
    });

    it('opens directly in note mode when a bot already owns the pending conversation', () => {
      const { wrapper, store } = mountWith({
        inbox,
        chat: {
          can_reply: false,
          status: 'pending',
          meta: { sender: { id: 2 }, assignee_type: 'AgentBot' },
        },
      });

      expect(bottomPanel(wrapper).isOnPrivateNote).toBe(true);
      expect(store.getters['draftMessages/getReplyEditorMode']).toBe(
        REPLY_EDITOR_MODES.NOTE
      );
      expect(topPanel(wrapper).isEditorDisabled).toBe(false);
    });

    it('opens in reply mode for every other conversation', () => {
      const { wrapper, store } = mountWith({ inbox });

      expect(bottomPanel(wrapper).isOnPrivateNote).toBe(false);
      expect(store.getters['draftMessages/getReplyEditorMode']).toBe(
        REPLY_EDITOR_MODES.REPLY
      );
    });

    it.each(['open', 'resolved', 'snoozed'])(
      'leaves the composer open when a bot owns a %s conversation',
      status => {
        const { wrapper } = mountWith({
          inbox,
          chat: {
            status,
            meta: { sender: { id: 2 }, assignee_type: 'AgentBot' },
          },
        });

        expect(topPanel(wrapper).isReplyRestricted).toBe(false);
        expect(bottomPanel(wrapper).enableWhatsAppTemplates).toBe(true);
      }
    );

    it('leaves the composer open when a human owns a pending conversation', () => {
      const { wrapper } = mountWith({
        inbox,
        chat: {
          status: 'pending',
          meta: { sender: { id: 2 }, assignee_type: 'User' },
        },
      });

      expect(topPanel(wrapper).isReplyRestricted).toBe(false);
      expect(bottomPanel(wrapper).enableWhatsAppTemplates).toBe(true);
    });

    it('matches the existing messaging-window rule when no bot is involved', () => {
      const { wrapper } = mountWith({
        inbox,
        chat: { can_reply: false, status: 'resolved' },
      });

      const stillRepliable = exemptFromMessagingWindow(name);
      expect(topPanel(wrapper).isReplyRestricted).toBe(!stillRepliable);
      expect(bottomPanel(wrapper).enableWhatsAppTemplates).toBe(stillRepliable);
      // WhatsApp/API disable the editor and steer to templates; everywhere
      // else the composer falls back to a usable private note.
      expect(topPanel(wrapper).isEditorDisabled).toBe(stillRepliable);
    });
  });

  it('hides the template action when the inbox has no templates synced', () => {
    const { wrapper } = mountWith({
      inbox: { channel_type: 'Channel::Whatsapp' },
      chat: { can_reply: false, status: 'open' },
      templates: [],
    });

    expect(bottomPanel(wrapper).enableWhatsAppTemplates).toBe(false);
    expect(topPanel(wrapper).isReplyRestricted).toBe(false);
  });

  describe('drafts', () => {
    const DRAFTS = {
      'draft-1-REPLY': 'half typed reply',
      'draft-1-NOTE': 'a note',
    };

    it('loads the note draft while a bot owns the conversation', async () => {
      const { wrapper } = mountWith({
        inbox: { channel_type: 'Channel::WebWidget' },
        chat: {
          status: 'pending',
          meta: { sender: { id: 2 }, assignee_type: 'AgentBot' },
        },
        drafts: DRAFTS,
      });
      await nextTick();

      expect(editor(wrapper)).toMatchObject({
        editorId: 'draft-1-NOTE',
        modelValue: 'a note',
      });
    });

    it('leaves the saved reply draft intact and restores it on takeover', async () => {
      const { wrapper, store } = mountWith({
        inbox: { channel_type: 'Channel::WebWidget' },
        chat: {
          status: 'pending',
          meta: { sender: { id: 2 }, assignee_type: 'AgentBot' },
        },
        drafts: DRAFTS,
      });
      await nextTick();
      expect(store.getters['draftMessages/get']('draft-1-REPLY')).toBe(
        'half typed reply'
      );

      store.commit('selectChat', {
        ...REPLIABLE,
        status: 'open',
        meta: { sender: { id: 2 }, assignee_type: 'User' },
      });
      await nextTick();

      expect(editor(wrapper)).toMatchObject({
        editorId: 'draft-1-REPLY',
        modelValue: 'half typed reply',
      });
    });
  });

  it('offers content templates on Twilio WhatsApp when no bot owns the conversation', () => {
    const { wrapper } = mountWith({
      inbox: { channel_type: 'Channel::TwilioSms', medium: 'whatsapp' },
      chat: { can_reply: true, status: 'open' },
    });

    expect(bottomPanel(wrapper).enableContentTemplates).toBe(true);
  });

  describe('on selecting a conversation', () => {
    const selectChat = async chat => {
      const { wrapper, store } = mountWith({
        inbox: { channel_type: 'Channel::WebWidget' },
      });
      store.commit('selectChat', { ...REPLIABLE, id: 99, ...chat });
      await nextTick();
      return { wrapper, store };
    };

    it('switches to note mode when a bot owns a pending conversation', async () => {
      const { wrapper } = await selectChat({
        status: 'pending',
        meta: { sender: { id: 2 }, assignee_type: 'AgentBot' },
      });

      expect(bottomPanel(wrapper).isOnPrivateNote).toBe(true);
    });

    it('stays in reply mode when a human owns a pending conversation', async () => {
      const { wrapper } = await selectChat({
        status: 'pending',
        meta: { sender: { id: 2 }, assignee_type: 'User' },
      });

      expect(bottomPanel(wrapper).isOnPrivateNote).toBe(false);
    });

    it('closes an open template modal when a bot takes over the conversation', async () => {
      const { wrapper, store } = mountWith({
        inbox: { channel_type: 'Channel::Whatsapp' },
      });
      wrapper
        .findComponent({ name: 'ReplyBottomPanel' })
        .vm.$emit('selectWhatsappTemplate');
      await nextTick();
      expect(wrapper.findComponent(WhatsappTemplates).props('show')).toBe(true);

      store.commit('selectChat', {
        ...REPLIABLE,
        status: 'pending',
        meta: { sender: { id: 2 }, assignee_type: 'AgentBot' },
      });
      await nextTick();

      expect(wrapper.findComponent(WhatsappTemplates).props('show')).toBe(
        false
      );
    });

    it('returns to reply mode once the agent takes over', async () => {
      const { wrapper, store } = await selectChat({
        status: 'pending',
        meta: { sender: { id: 2 }, assignee_type: 'AgentBot' },
      });
      expect(bottomPanel(wrapper).isOnPrivateNote).toBe(true);

      store.commit('selectChat', {
        ...REPLIABLE,
        id: 99,
        status: 'open',
        meta: { sender: { id: 2 }, assignee_type: 'User' },
      });
      await nextTick();

      expect(bottomPanel(wrapper).isOnPrivateNote).toBe(false);
      expect(topPanel(wrapper).isReplyRestricted).toBe(false);
      expect(store.getters['draftMessages/getReplyEditorMode']).toBe(
        REPLY_EDITOR_MODES.REPLY
      );
    });

    it('keeps the agent in note mode after they chose it themselves', async () => {
      const { wrapper } = await selectChat({});
      wrapper
        .findComponent({ name: 'ReplyTopPanel' })
        .vm.$emit('setReplyMode', REPLY_EDITOR_MODES.NOTE);
      await nextTick();

      expect(bottomPanel(wrapper).isOnPrivateNote).toBe(true);
    });

    it('mirrors the forced note mode into the draftMessages store', async () => {
      const { store } = await selectChat({
        status: 'pending',
        meta: { sender: { id: 2 }, assignee_type: 'AgentBot' },
      });

      expect(store.getters['draftMessages/getReplyEditorMode']).toBe(
        REPLY_EDITOR_MODES.NOTE
      );
    });
  });
});

describe('ReplyBox CRM subject', () => {
  it('sends the chosen subject with the message, and nothing without one', async () => {
    const { wrapper, store } = mountWith({
      inbox: { channel_type: 'Channel::Api' },
    });
    const dispatch = vi.spyOn(store, 'dispatch').mockResolvedValue();

    await wrapper.vm.sendMessage({ conversationId: 1, message: 'Oi' });
    expect(dispatch).toHaveBeenCalledWith('createPendingMessageAndSend', {
      conversationId: 1,
      message: 'Oi',
    });

    wrapper.vm.crmSubjectCardId = 5;
    await wrapper.vm.sendMessage({
      conversationId: 1,
      message: 'Segue a proposta',
      contentAttributes: { in_reply_to: 3 },
    });
    expect(dispatch).toHaveBeenCalledWith('createPendingMessageAndSend', {
      conversationId: 1,
      message: 'Segue a proposta',
      contentAttributes: { in_reply_to: 3, crm_card_id: 5 },
    });
  });
});

// #2249: o repasse do assunto recebe só a pessoa responsável; robô com o meu id não conta.
describe('ReplyBox CRM subject: responsável do repasse (#2249)', () => {
  const globalConfigAntes = window.globalConfig;
  beforeEach(() => {
    window.globalConfig = { CRM_KANBAN_ENABLED: 'true' };
  });
  afterEach(() => {
    window.globalConfig = globalConfigAntes;
  });

  it.each([
    ['AgentBot', null],
    ['Captain::Assistant', null],
    ['User', 7],
  ])(
    'responsável %s com o id do usuário: assignee-id %s',
    (assigneeType, esperado) => {
      const { wrapper } = mountWith({
        inbox: { channel_type: 'Channel::Api' },
        chat: {
          meta: {
            sender: { id: 2 },
            assignee: { id: 7 },
            assignee_type: assigneeType,
          },
        },
      });
      const repasse = wrapper.findComponent({ name: 'CrmRepasseDoAssunto' });
      expect(repasse.exists()).toBe(true);
      expect(repasse.props('assigneeId')).toBe(esperado);
    }
  );
});

// #2067: o ícone "ficar com a conversa ao enviar" ao lado do Enviar; quem atribui é o servidor.
describe('ReplyBox ficar com a conversa (#2067)', () => {
  const FLAG = 'ficar_com_a_conversa_ao_enviar';
  const ANA = { id: 9, name: 'Ana' };
  const LIA = { id: 3, name: 'Lia' };
  const montar = (meta, { inbox, ligada = true } = {}) =>
    mountWith({
      inbox: inbox || {
        channel_type: 'Channel::Whatsapp',
        provider: 'whatsapp_cloud',
      },
      chat: { meta: { sender: { id: 2 }, ...meta } },
      features: ligada ? [FLAG] : [],
    });
  const envios = dispatch =>
    dispatch.mock.calls
      .filter(([nome]) => nome === 'createPendingMessageAndSend')
      .map(([, payload]) => payload);
  const enviado = dispatch => envios(dispatch)[0];
  // Espia o envio sem engolir o rascunho (onde a escolha do ícone fica guardada).
  const espiar = (store, responder = () => Promise.resolve({})) => {
    const original = store.dispatch.bind(store);
    return vi
      .spyOn(store, 'dispatch')
      .mockImplementation((nome, payload) =>
        nome.startsWith('draftMessages/')
          ? original(nome, payload)
          : responder(nome, payload)
      );
  };
  const esperar = async () => {
    await nextTick();
    await new Promise(resolve => {
      setTimeout(resolve, 0);
    });
  };

  it.each([
    ['sem ninguém', {}, true],
    ['com a IA', { assignee: LIA, assignee_type: 'AgentBot' }, true],
    ['com colega', { assignee: ANA, assignee_type: 'User' }, false],
  ])('%s: o ícone aparece mesmo sem nada digitado', (_n, meta, ligada) => {
    const { wrapper } = montar(meta);
    expect(bottomPanel(wrapper).ficar).toMatchObject({ aplica: true, ligada });
  });

  it('não aparece quando a conversa já é minha', () => {
    const { wrapper } = montar({ assignee: { id: 7 }, assignee_type: 'User' });
    expect(bottomPanel(wrapper).ficar).toBeNull();
  });

  // Pega a tela nova com a flag desligada: fica exatamente como na main.
  it('flag desligada: sem ícone, com a faixa "Atribuir a mim" e nada a mais no envio', async () => {
    const { wrapper, store } = montar(
      { assignee: LIA, assignee_type: 'AgentBot' },
      { ligada: false }
    );
    expect(bottomPanel(wrapper).ficar).toBeNull();
    expect(
      wrapper.findComponent({ name: 'ReplyBoxBanner' }).props('ficarAoEnviar')
    ).toBe(false);

    const dispatch = espiar(store);
    await wrapper.vm.sendMessage({ conversationId: 1, message: 'Oi' });
    expect(enviado(dispatch)).toEqual({ conversationId: 1, message: 'Oi' });
  });

  it('flag ligada: a faixa "Atribuir a mim" sai', () => {
    const { wrapper } = montar({});
    expect(
      wrapper.findComponent({ name: 'ReplyBoxBanner' }).props('ficarAoEnviar')
    ).toBe(true);
  });

  it('nunca na nota privada, e a nota não pede para ficar', async () => {
    const { wrapper, store } = montar({});
    wrapper.vm.setReplyMode(REPLY_EDITOR_MODES.NOTE);
    await nextTick();
    expect(bottomPanel(wrapper).ficar).toBeNull();

    const dispatch = espiar(store);
    await wrapper.vm.sendMessage({
      conversationId: 1,
      message: 'nota',
      private: true,
    });
    expect(enviado(dispatch).ficarComAConversa).toBe(false);
  });

  it('o envio leva o dono que a tela viu', async () => {
    const { wrapper, store } = montar({ assignee: ANA, assignee_type: 'User' });
    const dispatch = espiar(store);

    await wrapper.vm.sendMessage({ conversationId: 1, message: 'Oi' });
    expect(enviado(dispatch)).toMatchObject({
      ficarComAConversa: false,
      ficarComAConversaDe: { tipo: 'pessoa', id: 9 },
    });
  });

  it('o modelo segue a regra do texto: de colega continua com o colega', async () => {
    const { wrapper, store } = montar({ assignee: ANA, assignee_type: 'User' });
    const dispatch = espiar(store);

    await wrapper.vm.onSendWhatsAppReply({
      message: 'Olá',
      templateParams: { name: 'oi' },
    });
    expect(enviado(dispatch)).toMatchObject({
      templateParams: { name: 'oi' },
      ficarComAConversa: false,
    });
  });

  it('ligar o ícone vale para aquela mensagem e volta ao padrão depois de enviar', async () => {
    const { wrapper, store } = montar({ assignee: ANA, assignee_type: 'User' });
    const dispatch = espiar(store);

    wrapper.vm.ficar.alternar();
    await wrapper.vm.onSendWhatsAppReply({
      message: 'Olá',
      templateParams: { name: 'oi' },
    });
    expect(enviado(dispatch).ficarComAConversa).toBe(true);
    expect(wrapper.vm.ficar.ligada).toBe(false);
  });

  it('texto e anexo que saem em várias mensagens levam a mesma decisão', () => {
    const { wrapper, store } = montar({
      assignee: LIA,
      assignee_type: 'AgentBot',
    });
    const dispatch = espiar(store);
    wrapper.vm.message = 'Segue a foto';
    wrapper.vm.attachedFiles = [
      { resource: { file: new Blob(['x']) }, isPrivate: false },
    ];

    wrapper.vm.confirmOnSendReply();

    // Uma com a foto e o texto como legenda (Cloud API: um anexo por mensagem).
    expect(envios(dispatch)).toHaveLength(1);
    envios(dispatch).forEach(payload => {
      expect(payload).toMatchObject({
        ficarComAConversa: true,
        ficarComAConversaDe: { tipo: 'ia' },
      });
    });
  });

  // Pega a conversa que ninguém pega quando a 1ª parte falha e a 2ª sai (as partes saem em paralelo).
  it('dois anexos: duas mensagens, todas com o mesmo pedido', () => {
    const { wrapper, store } = montar({ assignee: ANA, assignee_type: 'User' });
    const dispatch = espiar(store);
    wrapper.vm.ficar.alternar();
    wrapper.vm.message = 'Seguem as duas';
    wrapper.vm.attachedFiles = [
      { resource: { file: new Blob(['a']) }, isPrivate: false },
      { resource: { file: new Blob(['b']) }, isPrivate: false },
    ];

    wrapper.vm.confirmOnSendReply();

    expect(envios(dispatch)).toHaveLength(2);
    expect(envios(dispatch).map(p => p.ficarComAConversa)).toEqual([
      true,
      true,
    ]);
  });

  // Pega o envio que passou a esperar o servidor para rolar, avisar, limpar o rascunho e medir
  // (vale para todas as contas, inclusive com a flag desligada).
  describe('ordem do envio igual à main', () => {
    const ouvir = async () => {
      const { emitter } = await import('shared/helpers/mitt');
      const { BUS_EVENTS } = await import('shared/constants/busEvents');
      const ouvidos = [];
      const enviados = () => ouvidos.push('MESSAGE_SENT');
      const toasts = () => ouvidos.push('toast');
      emitter.on(BUS_EVENTS.MESSAGE_SENT, enviados);
      emitter.on('newToastMessage', toasts);
      return {
        ouvidos,
        parar: () => {
          emitter.off(BUS_EVENTS.MESSAGE_SENT, enviados);
          emitter.off('newToastMessage', toasts);
        },
      };
    };
    const servidorParado = () => {
      const servidor = {};
      servidor.promessa = new Promise((resolve, reject) => {
        Object.assign(servidor, { resolve, reject });
      });
      return servidor;
    };

    it.each([
      ['desligada', false],
      ['ligada', true],
    ])(
      'flag %s: avisa e apaga o rascunho antes da resposta do servidor',
      async (_n, ligada) => {
        const { wrapper, store } = montar({}, { ligada });
        const servidor = servidorParado();
        const dispatch = espiar(store, nome =>
          nome === 'createPendingMessageAndSend'
            ? servidor.promessa
            : Promise.resolve({})
        );
        const escuta = await ouvir();

        const envio = wrapper.vm.sendMessage({
          conversationId: 1,
          message: 'Oi',
        });
        expect(escuta.ouvidos).toEqual(['MESSAGE_SENT']);
        const nomes = dispatch.mock.calls.map(([nome]) => nome);
        expect(nomes.indexOf('draftMessages/delete')).toBeGreaterThan(
          nomes.indexOf('createPendingMessageAndSend')
        );
        expect(dispatch).toHaveBeenCalledWith('draftMessages/delete', {
          key: 'draft-1-REPLY',
        });

        servidor.resolve({});
        await envio;
        escuta.parar();
      }
    );

    it('flag desligada: a recusa do servidor não vira aviso (como na main)', async () => {
      const { wrapper, store } = montar({}, { ligada: false });
      espiar(store, nome =>
        nome === 'createPendingMessageAndSend'
          ? Promise.reject(new Error('x'))
          : Promise.resolve({})
      );
      const escuta = await ouvir();

      const resultado = await wrapper.vm.sendMessage({
        conversationId: 1,
        message: 'Oi',
      });
      await esperar();
      escuta.parar();

      expect(resultado).toEqual({ ok: false });
      expect(escuta.ouvidos).toEqual(['MESSAGE_SENT']);
    });

    it('flag ligada: a recusa do servidor avisa', async () => {
      const { wrapper, store } = montar({});
      espiar(store, nome =>
        nome === 'createPendingMessageAndSend'
          ? Promise.reject(new Error('x'))
          : Promise.resolve({})
      );
      const escuta = await ouvir();

      await wrapper.vm.sendMessage({ conversationId: 1, message: 'Oi' });
      await esperar();
      escuta.parar();

      expect(escuta.ouvidos).toEqual(['MESSAGE_SENT', 'toast']);
    });

    // Pega o rascunho de outra conversa apagado quando a resposta chega depois da troca.
    it('trocar de conversa durante um envio lento não apaga o rascunho da outra', async () => {
      const { wrapper, store } = montar({});
      const servidor = servidorParado();
      const dispatch = espiar(store, nome =>
        nome === 'createPendingMessageAndSend'
          ? servidor.promessa
          : Promise.resolve({})
      );

      const envio = wrapper.vm.sendMessage({
        conversationId: 1,
        message: 'Oi',
      });
      store.commit('selectChat', { ...REPLIABLE, id: 2 });
      store.commit('setDraft', {
        key: 'draft-2-REPLY',
        message: 'rascunho da 2',
      });
      await nextTick();
      servidor.resolve({});
      await envio;
      await esperar();

      const apagados = dispatch.mock.calls
        .filter(([nome]) => nome === 'draftMessages/delete')
        .map(([, { key }]) => key);
      expect(apagados).not.toContain('draft-2-REPLY');
      expect(store.state.drafts['draft-2-REPLY']).toBe('rascunho da 2');
    });
  });

  // Pega a escolha perdida quando o envio falha (a promessa do envio não voltava).
  it('o envio falhou: a escolha do ícone volta', async () => {
    const { wrapper, store } = montar({ assignee: ANA, assignee_type: 'User' });
    espiar(store, nome =>
      nome === 'createPendingMessageAndSend'
        ? Promise.reject(new Error('x'))
        : Promise.resolve({})
    );
    wrapper.vm.ficar.alternar();

    await wrapper.vm.sendMessage({ conversationId: 1, message: 'Oi' });
    await esperar();

    expect(wrapper.vm.ficar.ligada).toBe(true);
  });

  // Pega o aviso falso: uma parte ficou, a outra achou a conversa já minha ou perdeu a trava.
  it.each([
    ['nenhuma parte ficou: avisa', [true, true], true],
    ['uma parte ficou: não avisa', [true, false], false],
  ])('em partes, %s', async (_n, naoDeu, avisa) => {
    const { wrapper, store } = montar({});
    const alertas = [];
    const escutar = mensagem => alertas.push(mensagem);
    const { emitter } = await import('shared/helpers/mitt');
    emitter.on('newToastMessage', escutar);
    const respostas = naoDeu.map(nao =>
      nao ? { ficar_com_a_conversa_nao_deu: true } : {}
    );
    espiar(store, nome =>
      Promise.resolve(
        nome === 'createPendingMessageAndSend' ? respostas.shift() : {}
      )
    );
    wrapper.vm.message = 'Seguem';
    wrapper.vm.attachedFiles = [
      { resource: { file: new Blob(['a']) }, isPrivate: false },
      { resource: { file: new Blob(['b']) }, isPrivate: false },
    ];

    wrapper.vm.confirmOnSendReply();
    await esperar();
    emitter.off('newToastMessage', escutar);

    expect(
      JSON.stringify(alertas).includes('CONVERSA_CANAL.FICAR.NAO_DEU')
    ).toBe(avisa);
  });

  it('o servidor não conseguiu ficar com a conversa: a tela avisa', async () => {
    const { wrapper, store } = montar({});
    const alertas = [];
    const escutar = mensagem => alertas.push(mensagem);
    const { emitter } = await import('shared/helpers/mitt');
    emitter.on('newToastMessage', escutar);
    espiar(store, () =>
      Promise.resolve({ ficar_com_a_conversa_nao_deu: true })
    );

    await wrapper.vm.sendMessage({ conversationId: 1, message: 'Oi' });
    await esperar();
    emitter.off('newToastMessage', escutar);

    expect(JSON.stringify(alertas)).toContain('CONVERSA_CANAL.FICAR.NAO_DEU');
  });

  it('ficou: relê a conversa uma vez por envio, não por parte', async () => {
    const { wrapper, store } = montar({});
    const dispatch = espiar(store);
    wrapper.vm.message = 'Segue';
    wrapper.vm.attachedFiles = [
      { resource: { file: new Blob(['a']) }, isPrivate: false },
      { resource: { file: new Blob(['b']) }, isPrivate: false },
    ];

    wrapper.vm.confirmOnSendReply();
    await esperar();

    const releituras = dispatch.mock.calls.filter(
      ([nome]) => nome === 'getConversation'
    );
    expect(releituras).toEqual([['getConversation', 1]]);
  });

  it('o evento ao vivo já trouxe o dono novo: não relê', async () => {
    const { wrapper, store } = montar({});
    const dispatch = espiar(store, nome => {
      if (nome === 'createPendingMessageAndSend') {
        store.commit('selectChat', {
          ...store.state.chat,
          meta: {
            sender: { id: 2 },
            assignee: { id: 7 },
            assignee_type: 'User',
          },
        });
      }
      return Promise.resolve({});
    });

    await wrapper.vm.sendMessage({ conversationId: 1, message: 'Oi' });
    await esperar();

    expect(dispatch).not.toHaveBeenCalledWith('getConversation', 1);
  });

  describe('o "+" (onSendRichMessage)', () => {
    const RICO = { content: 'Escolha', richMessage: { type: 'options' } };
    const pendente = dispatch =>
      dispatch.mock.calls.find(([nome]) => nome === 'sendMessageWithData')[1];

    it('leva a mesma regra do texto', async () => {
      const { wrapper, store } = montar({
        assignee: LIA,
        assignee_type: 'AgentBot',
      });
      const dispatch = espiar(store);

      await wrapper.vm.onSendRichMessage(RICO);

      expect(pendente(dispatch)).toMatchObject({
        ficarComAConversa: true,
        ficarComAConversaDe: { tipo: 'ia' },
      });
    });

    it('recusado: a escolha volta e o erro sobe para a janela', async () => {
      const { wrapper, store } = montar({
        assignee: ANA,
        assignee_type: 'User',
      });
      espiar(store, nome =>
        nome === 'sendMessageWithData'
          ? Promise.reject(new Error('recusada'))
          : Promise.resolve({})
      );
      wrapper.vm.ficar.alternar();

      await expect(wrapper.vm.onSendRichMessage(RICO)).rejects.toThrow(
        'recusada'
      );
      expect(wrapper.vm.ficar.ligada).toBe(true);
    });
  });
});

describe('ReplyBox #1702 (conversa com a cara do WhatsApp)', () => {
  const RICO = {
    content: 'Escolha',
    richMessage: { type: 'options', options: [] },
  };

  it('o "+" envia esperando o servidor, com o assunto do CRM e a resposta citada', async () => {
    const { wrapper, store } = mountWith({
      inbox: { channel_type: 'Channel::Whatsapp' },
    });
    const dispatch = vi.spyOn(store, 'dispatch').mockResolvedValue();
    wrapper.vm.crmSubjectCardId = 5;
    wrapper.vm.inReplyTo = { id: 3 };

    await wrapper.vm.onSendRichMessage(RICO);

    const [acao, pendente] = dispatch.mock.calls.find(
      ([nome]) => nome === 'sendMessageWithData'
    );
    expect(acao).toBe('sendMessageWithData');
    expect(pendente).toMatchObject({
      conversation_id: 1,
      content: 'Escolha',
      private: false,
      contentAttributes: {
        rich_message: RICO.richMessage,
        in_reply_to: 3,
        crm_card_id: 5,
      },
    });
  });

  it('o "+" devolve a recusa do servidor para a janela mostrar', async () => {
    const { wrapper, store } = mountWith({
      inbox: { channel_type: 'Channel::Whatsapp' },
    });
    const recusa = { response: { data: { error: 'Título repetido.' } } };
    vi.spyOn(store, 'dispatch').mockImplementation(nome =>
      nome === 'sendMessageWithData'
        ? Promise.reject(recusa)
        : Promise.resolve()
    );

    await expect(wrapper.vm.onSendRichMessage(RICO)).rejects.toBe(recusa);
  });

  describe('seta do gravador', () => {
    const voz = { isVoiceMessage: true };

    it('envia quando o áudio gravado vira anexo na mesma conversa', async () => {
      const { wrapper } = mountWith({
        inbox: { channel_type: 'Channel::Whatsapp' },
      });
      const enviar = vi.spyOn(wrapper.vm, 'onSendReply').mockImplementation();
      wrapper.vm.enviarAudioAoAnexar = true;

      wrapper.vm.enviarSeForAGravacao(voz, 1);
      await nextTick();

      expect(enviar).toHaveBeenCalledTimes(1);
      expect(wrapper.vm.enviarAudioAoAnexar).toBe(false);
    });

    it('não envia sem a seta, com anexo comum ou se a conversa mudou', async () => {
      const { wrapper } = mountWith({
        inbox: { channel_type: 'Channel::Whatsapp' },
      });
      const enviar = vi.spyOn(wrapper.vm, 'onSendReply').mockImplementation();

      wrapper.vm.enviarSeForAGravacao(voz, 1);
      wrapper.vm.enviarAudioAoAnexar = true;
      wrapper.vm.enviarSeForAGravacao({ isVoiceMessage: false }, 1);
      wrapper.vm.enviarSeForAGravacao(voz, 2);
      await nextTick();

      expect(enviar).not.toHaveBeenCalled();
      expect(wrapper.vm.enviarAudioAoAnexar).toBe(false);
    });

    it('cancelar ou trocar de conversa esquece o pedido de envio', () => {
      const { wrapper } = mountWith({
        inbox: { channel_type: 'Channel::Whatsapp' },
      });
      wrapper.vm.enviarAudioAoAnexar = true;
      wrapper.vm.resetRecorderAndClearAttachments();
      expect(wrapper.vm.enviarAudioAoAnexar).toBe(false);
    });
  });

  it('com a chave desligada, a caixa fica como sempre', () => {
    const { wrapper } = mountWith({
      inbox: { channel_type: 'Channel::Whatsapp' },
    });
    expect(wrapper.vm.textoDoCampo).toBe('');
    expect(wrapper.vm.messagePlaceHolder).toBe('CONVERSATION.FOOTER.MSG_INPUT');
    expect(wrapper.findComponent({ name: 'GravadorDoWhatsapp' }).exists()).toBe(
      false
    );
  });
});

describe('ReplyBox #1702: Documento do "+" marca o anexo, não o envio', () => {
  const anexo = (nome, comoDocumento) => ({
    resource: { file: new File(['x'], nome) },
    comoDocumento,
  });

  it('num envio só (WAHA), diz quais anexos vão como documento', () => {
    const { wrapper } = mountWith({ inbox: { channel_type: 'Channel::Api' } });
    wrapper.vm.attachedFiles = [
      anexo('foto.jpg', false),
      anexo('foto-original.jpg', true),
    ];
    const payload = wrapper.vm.getMessagePayload('Oi');
    expect(payload.files).toHaveLength(2);
    expect(payload.documentIndexes).toEqual([1]);
  });

  it('sem documento, o envio fica como sempre', () => {
    const { wrapper } = mountWith({ inbox: { channel_type: 'Channel::Api' } });
    wrapper.vm.attachedFiles = [anexo('foto.jpg', false)];
    expect(wrapper.vm.getMessagePayload('Oi')).not.toHaveProperty(
      'documentIndexes'
    );
  });

  it('um envio por anexo (WhatsApp oficial): cada um leva a sua marca', () => {
    const { wrapper } = mountWith({
      inbox: { channel_type: 'Channel::Whatsapp' },
    });
    wrapper.vm.attachedFiles = [
      anexo('foto.jpg', false),
      anexo('foto-original.jpg', true),
    ];
    const payloads = wrapper.vm.getMultipleMessagesPayload('Oi');
    expect(payloads.map(p => p.documentIndexes)).toEqual([[], [0]]);
  });
});

describe('ReplyBox #2113: respondendo a uma mensagem do Instagram', () => {
  afterEach(() => {
    conversaDoInstagram.ligada = false;
  });

  const citacao = wrapper => wrapper.findComponent({ name: 'ReplyToMessage' });

  it('com a cara do Direct, a citação fica numa linha própria no topo da pílula', async () => {
    conversaDoInstagram.ligada = true;
    const { wrapper } = mountWith({
      inbox: { channel_type: 'Channel::Instagram' },
    });
    wrapper.vm.inReplyTo = { id: 3, content: 'Tem a bolsa em preto?' };
    await nextTick();

    expect(citacao(wrapper).exists()).toBe(true);
    expect(citacao(wrapper).attributes('data-resposta-do-instagram')).toBe('');
    expect(citacao(wrapper).element.parentElement.classList).toContain(
      'reply-box'
    );
  });

  it('sem a cara do Direct, a citação segue dentro do campo, como antes', async () => {
    const { wrapper } = mountWith({
      inbox: { channel_type: 'Channel::Instagram' },
    });
    wrapper.vm.inReplyTo = { id: 3, content: 'Tem a bolsa em preto?' };
    await nextTick();

    expect(citacao(wrapper).exists()).toBe(true);
    expect(
      citacao(wrapper).attributes('data-resposta-do-instagram')
    ).toBeUndefined();
    expect(citacao(wrapper).element.parentElement.classList).toContain(
      'reply-box__top'
    );
  });
});
