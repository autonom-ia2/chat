import { ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import conversaActions from 'dashboard/store/modules/conversations/actions';
import { createConversationPayload } from 'dashboard/store/modules/contactConversations';
import NovaConversaGaveta from '../NovaConversaGaveta.vue';
import { partesDoWhatsapp } from '../envioNoWhatsapp';

// #1988 — a gaveta "Enviar mensagem" no WhatsApp: (1) a caixa com a barra (+, emoji,
// microfone e assinatura) no oficial e no comum, com a gravação saindo como mensagem
// de voz; (2) a janela de 24 h que abre com a gaveta já aberta (ou reaberta): a
// gaveta pergunta de novo o `can_reply`, sem zerar a escolha nem o texto.
const estado = vi.hoisted(() => ({
  canais: [],
  dispatch: null,
  show: null,
  axios: null,
  respostas: [],
  gravador: true,
  assinatura: false,
}));

const traduz = (chave, dados) =>
  dados ? `${chave}:${Object.values(dados).join(',')}` : chave;

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: traduz }),
  // O título da gaveta põe o nome por slot (#2255).
  I18nT: {
    props: ['keypath'],
    template: '<span>{{ keypath }}:<slot name="nome" /></span>',
  },
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ name: 'home', params: { accountId: 7 } }),
  useRouter: () => ({ push: vi.fn(), hasRoute: () => true }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: estado.dispatch }),
  useMapGetter: nome => {
    const getters = {
      'inboxes/getInboxes': [],
      'contacts/getContactById': id => ({ id: Number(id), name: 'Ana Souza' }),
      'inboxes/getConversationWhatsAppTemplates': () => [],
      'inboxes/getInbox': () => ({}),
      'accounts/isRTL': false,
      getCurrentUser: { id: 3 },
      getCurrentAccountId: 7,
      'accounts/isFeatureEnabledonAccount': (conta, chave) =>
        chave === 'voice_recorder' && estado.gravador,
      'globalConfig/get': { directUploadsEnabled: false },
      getMessageSignature: 'Rodrigo, Hub2You',
      getSelectedChat: null,
    };
    return ref(getters[nome]);
  },
}));
vi.mock('dashboard/helper/permissionsHelper.js', () => ({
  getUserPermissions: () => ['agent'],
}));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    fetchSignatureFlagFromUISettings: () => estado.assinatura,
    setSignatureFlagForInbox: vi.fn(),
  }),
}));
vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: vi.fn(),
}));
// O arquivo entra como no envio sem upload direto: direto na lista de anexos.
vi.mock('dashboard/composables/useFileUpload', () => ({
  useFileUpload: ({ attachFile }) => ({
    onFileUpload: file => attachFile({ file, blob: null }),
  }),
}));
vi.mock('dashboard/api/inbox/conversation', () => ({
  default: { show: (...args) => estado.show(...args) },
}));
vi.mock(
  'dashboard/components-next/NewConversation/helpers/composeConversationHelper',
  async original => ({
    ...(await original()),
    fetchContactableInboxes: vi.fn(async () => estado.canais),
  })
);

const AGORA = () => Math.floor(Date.now() / 1000);
const conversa = (dados = {}) => ({
  id: 610,
  displayId: 20,
  status: 'open',
  lastActivityAt: AGORA() - 60 * 60,
  locked: false,
  visible: true,
  ...dados,
});
// WhatsApp oficial (Cloud API) da conta 16, com a conversa #20.
const OFICIAL = (dados = {}) => ({
  id: 1,
  name: 'Vendas',
  channelType: INBOX_TYPES.WHATSAPP,
  provider: 'whatsapp_cloud',
  phoneNumber: '+5511999990000',
  sourceId: 's1',
  conversationToContinue: conversa(dados),
});
// WhatsApp comum: caixa API ligada ao WAHA.
const COMUM = {
  id: 2,
  name: 'WhatsApp API',
  channelType: INBOX_TYPES.API,
  wahaProvider: true,
  sourceId: 's2',
};
const COMUM_COM_CONVERSA = (dados = {}) => ({
  ...COMUM,
  conversationToContinue: conversa(dados),
});

// O gravador de verdade usa o microfone; aqui a seta entrega um áudio pronto.
const AUDIO = new File(['ogg'], 'gravacao.ogg', { type: 'audio/ogg' });
const GravadorDeMentira = {
  name: 'GravadorDoWhatsapp',
  emits: ['finishRecord', 'enviar', 'cancelar'],
  template: `<div data-gravador>
    <button data-seta @click="$emit('enviar')" />
    <button data-lixeira @click="$emit('cancelar')" />
  </div>`,
  methods: {
    stopRecording() {
      this.$emit('finishRecord', {
        name: AUDIO.name,
        type: AUDIO.type,
        size: AUDIO.size,
        file: AUDIO,
      });
    },
  },
};

// Cada gaveta montada ouve o websocket; desmontar no fim solta o ouvinte.
const montadas = [];
const montar = () => {
  const wrapper = mount(NovaConversaGaveta, {
    props: { contactId: '9' },
    slots: { trigger: '<button data-abrir>Enviar mensagem</button>' },
    attachTo: document.body,
    global: {
      mocks: { $t: traduz },
      directives: { tooltip: {} },
      stubs: {
        TeleportWithDirection: { template: '<div><slot /></div>' },
        transition: true,
        GravadorDoWhatsapp: GravadorDeMentira,
        Avatar: true,
      },
    },
  });
  montadas.push(wrapper);
  return wrapper;
};

const abrirOuFechar = async wrapper => {
  await wrapper.find('[data-abrir]').trigger('click');
  await flushPromises();
};
const abrir = async () => {
  const wrapper = montar();
  await abrirOuFechar(wrapper);
  return wrapper;
};
const caixa = wrapper => wrapper.find('[data-caixa-do-whatsapp]');
const principal = wrapper => wrapper.find('[data-nova-conversa-principal]');
const chamadas = acao =>
  estado.dispatch.mock.calls.filter(([nome]) => nome === acao);
const SO_PRONTA = 'NOVA_CONVERSA.MENSAGEM.SO_PRONTA_TITULO';

describe('NovaConversaGaveta — WhatsApp (#1988)', () => {
  beforeEach(() => {
    estado.canais = [OFICIAL()];
    estado.gravador = true;
    estado.assinatura = false;
    estado.respostas = [{ can_reply: true }];
    // Cada pergunta ao servidor leva a próxima resposta; a última se repete.
    estado.show = vi.fn(async () => ({
      data:
        estado.respostas.length > 1
          ? estado.respostas.shift()
          : estado.respostas[0],
    }));
    estado.axios = vi.fn(async () => ({ data: { id: 900 } }));
    globalThis.axios = estado.axios;
    window.history.pushState({}, '', '/app/accounts/7/contacts/9');
    estado.dispatch = vi.fn(async (acao, dados) => {
      if (acao === 'contactConversations/create') {
        return { id: 42, account_id: 7 };
      }
      if (acao === 'sendMessageWithData') {
        return conversaActions.sendMessageWithData({ commit: vi.fn() }, dados);
      }
      return null;
    });
  });

  afterEach(() => {
    montadas.splice(0).forEach(wrapper => wrapper.unmount());
    document.body.innerHTML = '';
  });

  describe('ponto 1 — a caixa com a barra', () => {
    it('WhatsApp oficial que pode responder: texto, +, emoji, microfone e assinatura', async () => {
      const wrapper = await abrir();

      expect(caixa(wrapper).exists()).toBe(true);
      expect(wrapper.find('[data-mais-do-email]').exists()).toBe(true);
      expect(wrapper.find('[data-emoji-do-whatsapp]').exists()).toBe(true);
      expect(wrapper.find('[data-gravar-do-whatsapp]').exists()).toBe(true);
      expect(wrapper.find('[data-assinatura-do-whatsapp]').exists()).toBe(true);
    });

    it('WhatsApp comum (WAHA, caixa API) também tem a caixa com a barra', async () => {
      estado.canais = [COMUM];
      const wrapper = await abrir();

      expect(caixa(wrapper).exists()).toBe(true);
      expect(wrapper.find('[data-mais-do-email]').exists()).toBe(true);
      expect(wrapper.find('[data-gravar-do-whatsapp]').exists()).toBe(true);
    });

    it('caixa API sem WAHA fica com o campo simples, sem a barra', async () => {
      estado.canais = [{ ...COMUM, wahaProvider: false }];
      const wrapper = await abrir();

      expect(caixa(wrapper).exists()).toBe(false);
      expect(wrapper.find('#nova-conversa-texto').exists()).toBe(true);
    });

    it('fora da janela de 24 h só cabe mensagem aprovada: sem caixa nem barra', async () => {
      estado.respostas = [{ can_reply: false }];
      const wrapper = await abrir();

      expect(wrapper.text()).toContain(SO_PRONTA);
      expect(caixa(wrapper).exists()).toBe(false);
      expect(wrapper.find('[data-barra-do-whatsapp]').exists()).toBe(false);
    });

    it('caixa híbrida pelo número reserva: só texto, sem + e sem microfone', async () => {
      estado.respostas = [{ can_reply: true, whatsapp_api_reply: true }];
      const wrapper = await abrir();

      expect(caixa(wrapper).exists()).toBe(true);
      expect(wrapper.find('[data-emoji-do-whatsapp]').exists()).toBe(true);
      expect(wrapper.find('[data-mais-do-email]').exists()).toBe(false);
      expect(wrapper.find('[data-gravar-do-whatsapp]').exists()).toBe(false);
    });

    it('sem a chave de gravação da conta, o microfone não aparece', async () => {
      estado.gravador = false;
      const wrapper = await abrir();

      expect(wrapper.find('[data-gravar-do-whatsapp]').exists()).toBe(false);
    });

    it('a assinatura ligada vai no fim do texto, na prévia e no envio', async () => {
      estado.assinatura = true;
      const wrapper = await abrir();

      await wrapper.find('#nova-conversa-texto').setValue('Oi, Ana');
      expect(wrapper.find('[data-previa-balao]').text()).toContain(
        'Rodrigo, Hub2You'
      );
      await principal(wrapper).trigger('click');
      await flushPromises();

      const [[, pendente]] = chamadas('sendMessageWithData');
      expect(pendente.message.startsWith('Oi, Ana')).toBe(true);
      expect(pendente.message).toContain('Rodrigo, Hub2You');
    });

    it('a gravação sai como mensagem de voz na conversa que continua', async () => {
      const wrapper = await abrir();

      await wrapper.find('[data-gravar-do-whatsapp]').trigger('click');
      await wrapper.find('[data-seta]').trigger('click');
      await vi.waitFor(() => expect(estado.axios).toHaveBeenCalledTimes(1));
      await flushPromises();

      const [[pedido]] = estado.axios.mock.calls;
      expect(pedido.url).toBe('/api/v1/accounts/7/conversations/20/messages');
      expect(pedido.data.get('is_voice_message')).toBe('true');
      expect(pedido.data.getAll('attachments[]')).toEqual([AUDIO]);
      expect(chamadas('contactConversations/create')).toHaveLength(0);
    });

    it('Cloud API: parte do meio falha e o Enviar de novo manda só o resto, sem repetir', async () => {
      const wrapper = await abrir();
      await wrapper.find('#nova-conversa-texto').setValue('Segue');
      await wrapper.find('[data-gravar-do-whatsapp]').trigger('click');
      // Duas gravações: a primeira fica (sem enviar), a segunda vai com a seta.
      wrapper.findComponent({ name: 'GravadorDoWhatsapp' }).vm.stopRecording();
      await vi.waitFor(() =>
        expect(wrapper.findAll('[data-vozes-do-whatsapp] li')).toHaveLength(1)
      );
      let falhar = true;
      estado.axios = vi.fn(async pedido => {
        const ehVoz = pedido.data instanceof FormData;
        if (ehVoz && falhar) {
          falhar = false;
          throw new Error('rede');
        }
        return { data: { id: 900 } };
      });
      globalThis.axios = estado.axios;

      await principal(wrapper).trigger('click');
      await flushPromises();
      // Só gravação + texto: o texto saiu sozinho; a gravação falhou e ficou na caixa.
      expect(estado.axios).toHaveBeenCalledTimes(2);
      expect(wrapper.find('#nova-conversa-texto').element.value).toBe('');
      expect(wrapper.findAll('[data-vozes-do-whatsapp] li')).toHaveLength(1);

      await principal(wrapper).trigger('click');
      await flushPromises();
      expect(estado.axios).toHaveBeenCalledTimes(3);
      const ultimo = estado.axios.mock.calls[2][0];
      expect(ultimo.data.get('is_voice_message')).toBe('true');
      expect(ultimo.data.get('content')).toBe(null);
    });

    it('a lixeira cancela a gravação: nada é anexado nem enviado', async () => {
      const wrapper = await abrir();

      await wrapper.find('[data-gravar-do-whatsapp]').trigger('click');
      await wrapper.find('[data-lixeira]').trigger('click');
      await flushPromises();

      expect(wrapper.find('[data-gravador]').exists()).toBe(false);
      expect(wrapper.find('[data-barra-do-whatsapp]').exists()).toBe(true);
      expect(estado.axios).not.toHaveBeenCalled();
    });
  });

  describe('ponto 2 — a janela de 24 h abre com a gaveta aberta', () => {
    it('reproduz a conta 16: gaveta reaberta depois do "Oi" pergunta de novo e libera o texto', async () => {
      estado.respostas = [{ can_reply: false }, { can_reply: true }];
      const wrapper = await abrir();
      expect(wrapper.text()).toContain(SO_PRONTA);

      // Fecha; o cliente escreve "Oi"; abre de novo. Os canais chegam com a
      // última atividade nova (o cartão diz "há menos de um minuto").
      await abrirOuFechar(wrapper);
      estado.canais = [OFICIAL({ lastActivityAt: AGORA() })];
      await abrirOuFechar(wrapper);

      expect(estado.show).toHaveBeenCalledTimes(2);
      expect(wrapper.text()).not.toContain(SO_PRONTA);
      expect(caixa(wrapper).exists()).toBe(true);
    });

    it('mensagem do cliente pelo websocket, com a gaveta aberta, libera o texto', async () => {
      estado.respostas = [{ can_reply: false }, { can_reply: true }];
      const wrapper = await abrir();
      expect(wrapper.text()).toContain(SO_PRONTA);

      emitter.emit(BUS_EVENTS.MENSAGEM_AO_VIVO, {
        conversation_id: 20,
        message_type: 0,
      });
      await flushPromises();

      expect(estado.show).toHaveBeenCalledTimes(2);
      expect(caixa(wrapper).exists()).toBe(true);
      expect(
        wrapper.find('[data-nova-conversa-continuar] input').element.checked
      ).toBe(true);
    });

    it('mensagem chega enquanto a pergunta completa está no ar: pergunta de novo depois', async () => {
      let responder;
      estado.show = vi.fn(
        () =>
          new Promise(resolve => {
            responder = resolve;
          })
      );
      const wrapper = montar();
      await abrirOuFechar(wrapper);
      emitter.emit(BUS_EVENTS.MENSAGEM_AO_VIVO, {
        conversation_id: 20,
        message_type: 0,
      });
      estado.show = vi.fn(async () => ({ data: { can_reply: true } }));
      responder({ data: { can_reply: false } });
      await flushPromises();

      expect(estado.show).toHaveBeenCalledTimes(1);
      expect(caixa(wrapper).exists()).toBe(true);
    });

    it('mensagem de outra conversa ou enviada pela empresa não pergunta de novo', async () => {
      estado.respostas = [{ can_reply: false }];
      await abrir();

      emitter.emit(BUS_EVENTS.MENSAGEM_AO_VIVO, {
        conversation_id: 21,
        message_type: 0,
      });
      emitter.emit(BUS_EVENTS.MENSAGEM_AO_VIVO, {
        conversation_id: 20,
        message_type: 1,
      });
      await flushPromises();

      expect(estado.show).toHaveBeenCalledTimes(1);
    });

    it('perguntar de novo não zera a escolha "Começar conversa nova" nem o texto', async () => {
      estado.canais = [COMUM_COM_CONVERSA()];
      const wrapper = await abrir();

      await wrapper.find('[data-nova-conversa-comecar] input').setValue(true);
      await wrapper.find('#nova-conversa-texto').setValue('Rascunho da Ana');
      await abrirOuFechar(wrapper);
      estado.canais = [COMUM_COM_CONVERSA({ lastActivityAt: AGORA() })];
      await abrirOuFechar(wrapper);

      expect(estado.show).toHaveBeenCalledTimes(2);
      expect(
        wrapper.find('[data-nova-conversa-comecar] input').element.checked
      ).toBe(true);
      expect(wrapper.find('#nova-conversa-texto').element.value).toBe(
        'Rascunho da Ana'
      );
    });

    it('a pergunta de novo não mostra "carregando" nem tira a mensagem da tela', async () => {
      // No WhatsApp comum o texto livre aparece mesmo com can_reply falso.
      estado.canais = [COMUM_COM_CONVERSA()];
      estado.respostas = [{ can_reply: false }];
      let responder;
      const wrapper = await abrir();
      await wrapper.find('#nova-conversa-texto').setValue('Oi');
      estado.show = vi.fn(
        () =>
          new Promise(resolve => {
            responder = resolve;
          })
      );

      emitter.emit(BUS_EVENTS.MENSAGEM_AO_VIVO, {
        conversation_id: 20,
        message_type: 0,
      });
      await flushPromises();
      // Ainda sem resposta: o campo continua à vista, com o texto.
      expect(estado.show).toHaveBeenCalledTimes(1);
      expect(wrapper.find('#nova-conversa-texto').element.value).toBe('Oi');
      expect(wrapper.text()).not.toContain(
        'NOVA_CONVERSA.ONDE_ENTRA.CARREGANDO'
      );
      responder({ data: { can_reply: true } });
      await flushPromises();
      expect(wrapper.find('#nova-conversa-texto').element.value).toBe('Oi');
    });
  });
});

describe('partesDoWhatsapp (#1988)', () => {
  const foto = { resource: { id: 'f' }, isVoiceMessage: false };
  const voz = { resource: { id: 'v' }, isVoiceMessage: true };

  it('WAHA: tudo numa mensagem só, com a marca de voz', () => {
    expect(
      partesDoWhatsapp({
        texto: 'Oi',
        anexos: [voz, foto],
        umPorMensagem: false,
      })
    ).toEqual([{ texto: 'Oi', anexos: [voz, foto], voz: true }]);
  });

  it('Cloud API: um anexo por mensagem e a legenda no primeiro que não é áudio', () => {
    expect(
      partesDoWhatsapp({
        texto: 'Oi',
        anexos: [voz, foto],
        umPorMensagem: true,
      })
    ).toEqual([
      { texto: '', anexos: [voz], voz: true },
      { texto: 'Oi', anexos: [foto], voz: false },
    ]);
  });

  it('Cloud API só com gravação: o texto sai sozinho antes, para não se perder', () => {
    expect(
      partesDoWhatsapp({ texto: 'Oi', anexos: [voz], umPorMensagem: true })
    ).toEqual([
      { texto: 'Oi', anexos: [], voz: false },
      { texto: '', anexos: [voz], voz: true },
    ]);
  });

  it('sem anexo: só o texto', () => {
    expect(partesDoWhatsapp({ texto: 'Oi', umPorMensagem: true })).toEqual([
      { texto: 'Oi', anexos: [], voz: false },
    ]);
  });
});

describe('criação da conversa com a gravação (#1988)', () => {
  it('leva message[is_voice_message] para o MessageBuilder', () => {
    const payload = createConversationPayload({
      params: {
        inboxId: 1,
        sourceId: 's1',
        assigneeId: 3,
        message: { content: '', is_voice_message: true },
      },
      contactId: 9,
      files: [AUDIO],
    });

    expect(payload.get('message[is_voice_message]')).toBe('true');
    expect(payload.getAll('message[attachments][]')).toEqual([AUDIO]);
  });
});
