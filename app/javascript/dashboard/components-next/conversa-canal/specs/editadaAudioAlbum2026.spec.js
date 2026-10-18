/* eslint-disable vue/one-component-per-file */
import { computed, defineComponent, h, nextTick, ref } from 'vue';
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/conversaCanal.json';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import Message from '../../message/Message.vue';
import { MESSAGE_STATUS, MESSAGE_TYPES } from '../../message/constants';
import { AGORA, montagem } from '../../message/specs/montarMensagem';
import {
  provideMessageContext,
  useMessageContext,
} from '../../message/provider.js';
import { PELES, fornecerFuso, fornecerPele } from '../pele';
import RotuloEditada from '../RotuloEditada.vue';
import AudioDoWhatsapp from '../audio/AudioDoWhatsapp.vue';
import AlbumDoWhatsapp from '../album/AlbumDoWhatsapp.vue';
import { useAlbunsDaConversa } from '../album/useAlbuns';
import MessageContextMenu from 'dashboard/modules/conversations/components/MessageContextMenu.vue';

vi.mock('vue-router', () => ({ useRoute: () => ({ query: {}, params: {} }) }));
vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
  useTrack: vi.fn(),
}));

// O "pai" do álbum que a Cloud entrega como não suportada, logo antes das fotos.
const marcadorDoAlbum = primeira => ({
  ...primeira,
  id: -1,
  attachments: [],
  contentAttributes: { isUnsupported: true, unsupportedKind: 'unknown' },
});

const i18n = () =>
  createI18n({
    legacy: false,
    locale: 'en',
    messages: { en },
    missingWarn: false,
    fallbackWarn: false,
  });

const naTela = (filho, pele = PELES.WHATSAPP) =>
  defineComponent({
    setup() {
      fornecerPele(computed(() => pele));
      fornecerFuso(computed(() => 'America/Sao_Paulo'));
      return () => filho();
    },
  });

const editada = {
  editedAt: '2026-10-16T18:10:00Z',
  editHistory: [
    { content: 'primeira versão', editedAt: '2026-10-16T18:02:00Z' },
    { content: 'segunda versão', editedAt: '2026-10-16T18:10:00Z' },
  ],
};

describe('editada (#1702)', () => {
  const montarRotulo = () =>
    mount(
      naTela(() => h(RotuloEditada, { atributos: editada })),
      { global: { plugins: [i18n()] }, attachTo: document.body }
    );

  it('"Editada" é um botão; abre as versões, da mais nova para a mais antiga', async () => {
    const wrapper = montarRotulo();
    const botao = wrapper.find('[data-rotulo-editada]');
    expect(botao.text()).toBe('Edited');
    // O nome é o texto que aparece: nada de aria-label por cima.
    expect(botao.attributes('aria-label')).toBeUndefined();
    expect(botao.attributes('aria-expanded')).toBe('false');
    await botao.trigger('click');
    const versoes = wrapper.findAll('[data-versao-anterior]');
    expect(versoes.map(v => v.find('span').text())).toEqual([
      'segunda versão',
      'primeira versão',
    ]);
    expect(versoes[1].text()).toContain('Changed at 15:02');
    expect(wrapper.find('[data-versoes-anteriores]').attributes('role')).toBe(
      'dialog'
    );
    wrapper.unmount();
  });

  it('abrir leva o foco ao painel; Esc fecha e devolve o foco ao "Editada"', async () => {
    const wrapper = montarRotulo();
    const botao = wrapper.find('[data-rotulo-editada]');
    await botao.trigger('click');
    await nextTick();
    const painel = wrapper.find('[data-versoes-anteriores]');
    expect(document.activeElement).toBe(painel.element);
    await painel.trigger('keydown', { key: 'Escape' });
    expect(wrapper.find('[data-versoes-anteriores]').exists()).toBe(false);
    expect(document.activeElement).toBe(botao.element);
    wrapper.unmount();
  });

  const montarMensagem = pele =>
    mount(
      naTela(
        () =>
          h(Message, {
            id: 1,
            messageType: MESSAGE_TYPES.INCOMING,
            status: MESSAGE_STATUS.SENT,
            content: 'terceira versão',
            conversationId: 7,
            createdAt: AGORA,
            currentUserId: 1,
            sender: { id: 7, name: 'Maria', type: 'Contact' },
            contentAttributes: editada,
          }),
        pele
      ),
      {
        global: {
          ...montagem,
          plugins: [...montagem.plugins, i18n()],
          stubs: { ContextMenu: true, Avatar: true },
        },
      }
    );

  it('com a pele, "Editada" fica antes da hora; o texto é o novo', () => {
    const wrapper = montarMensagem(PELES.WHATSAPP);
    const meta = wrapper.find('[data-rotulo-editada]');
    expect(meta.exists()).toBe(true);
    expect(meta.element.parentElement.nextElementSibling.tagName).toBe('DIV');
    expect(wrapper.text()).toContain('terceira versão');
  });

  it('sem a pele, sem rótulo', () => {
    expect(montarMensagem(null).find('[data-rotulo-editada]').exists()).toBe(
      false
    );
  });
});

describe('áudio ouvido pelo cliente (#1702)', () => {
  const montarAudio = ({ lado, atributos }) =>
    mount(
      defineComponent({
        setup() {
          provideMessageContext({
            sender: ref({ name: 'Ana' }),
            orientation: ref(lado),
            contentAttributes: ref(atributos),
          });
          return () =>
            h(AudioDoWhatsapp, {
              attachment: { dataUrl: 'https://x.test/a.ogg' },
            });
        },
      }),
      {
        global: {
          plugins: [createStore({ getters: {} }), i18n()],
          stubs: { Avatar: true },
        },
      }
    );
  const microfone = wrapper =>
    wrapper.find('.i-ph-microphone-fill').element.parentElement;

  it('enviado e ouvido: microfone azul e aviso para o leitor de tela', () => {
    const wrapper = montarAudio({
      lado: 'right',
      atributos: { playedAt: '2026-10-16T18:00:00Z' },
    });
    expect(microfone(wrapper).className).toContain('text-[#53BDEB]');
    expect(wrapper.find('[data-audio-ouvido]').text()).toBe(
      'The customer listened to this audio'
    );
  });

  it('enviado e ainda não ouvido: microfone cinza', () => {
    const wrapper = montarAudio({ lado: 'right', atributos: {} });
    expect(microfone(wrapper).className).toContain('text-[#0A0A0A]/45');
    expect(wrapper.find('[data-audio-ouvido]').exists()).toBe(false);
  });
});

describe('álbum (#1702)', () => {
  const BASE = Date.UTC(2026, 9, 16, 18, 0) / 1000;
  const item = (id, extras = {}) => ({
    id,
    messageType: 0,
    senderId: 7,
    senderType: 'Contact',
    createdAt: BASE + id,
    status: 'sent',
    content: null,
    contentAttributes: {},
    attachments: [
      { id: id * 10, fileType: 'image', dataUrl: `https://x.test/${id}.jpg` },
    ],
    ...extras,
  });

  // O balão de verdade (Base.vue) é trocado por um que mostra o nome e as reações que
  // o álbum passa adiante.
  const BalaoFalso = defineComponent({
    setup(_, { slots, attrs }) {
      const { contentAttributes } = useMessageContext();
      return () =>
        h('div', { 'data-balao': attrs['data-bubble-name'] }, [
          h(
            'span',
            { 'data-reacoes': '' },
            (contentAttributes.value.reactions || []).map(r => r.emoji).join('')
          ),
          slots.default?.(),
        ]);
    },
  });

  const montarAlbum = mensagens => {
    const Balao = defineComponent({
      setup() {
        provideMessageContext({
          id: ref(mensagens[0].id),
          createdAt: ref(mensagens[0].createdAt),
          status: ref(mensagens[0].status),
          // Como no Message.vue: o contexto sempre traz o tipo (0 = recebida).
          messageType: ref(mensagens[0].messageType ?? 0),
          variant: ref('user'),
          contentAttributes: ref(mensagens[0].contentAttributes),
        });
        return () => h(AlbumDoWhatsapp);
      },
    });
    const Conversa = defineComponent({
      setup() {
        useAlbunsDaConversa(
          // O álbum recebido começa no marcador da Cloud (o "pai" não suportado).
          computed(() => [marcadorDoAlbum(mensagens[0]), ...mensagens]),
          computed(() => null)
        );
        return () => h(Balao);
      },
    });
    return mount(
      naTela(() => h(Conversa)),
      {
        global: {
          plugins: [
            createStore({ getters: { getSelectedChatAttachments: () => [] } }),
            i18n(),
          ],
          directives: {
            dompurifyHtml: (el, { value }) => {
              el.innerHTML = value;
            },
          },
          stubs: { BaseBubble: BalaoFalso, GalleryView: true },
        },
      }
    );
  };

  it('com legenda: agrupa, legenda embaixo do mosaico e hora fora da foto', () => {
    const wrapper = montarAlbum([
      item(1),
      item(2, { content: 'Fotos da obra' }),
    ]);
    expect(wrapper.findAll('[data-quadro-do-album]')).toHaveLength(2);
    expect(wrapper.find('[data-legenda-do-album]').text()).toContain(
      'Fotos da obra'
    );
    expect(wrapper.find('[data-balao]').attributes('data-balao')).toBe(
      'album-legenda'
    );
  });

  it('sem legenda, o nome de sempre (hora sobre a foto)', () => {
    const wrapper = montarAlbum([item(1), item(2)]);
    expect(wrapper.find('[data-balao]').attributes('data-balao')).toBe('album');
    expect(wrapper.find('[data-legenda-do-album]').exists()).toBe(false);
  });

  it('o selo junta as reações de todos os itens', () => {
    const wrapper = montarAlbum([
      item(1, { contentAttributes: { reactions: [{ emoji: '👍' }] } }),
      item(2, { contentAttributes: { reactions: [{ emoji: '❤️' }] } }),
    ]);
    expect(wrapper.find('[data-reacoes]').text()).toBe('👍❤️');
  });

  it('citação de item do meio: o quadro tem o id para rolar e pisca', async () => {
    const wrapper = montarAlbum([item(1), item(2), item(3)]);
    const quadros = wrapper.findAll('[data-quadro-do-album]');
    expect(quadros[0].attributes('id')).toBeUndefined();
    expect(quadros[1].attributes('id')).toBe('message2');
    emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE, { messageId: 2 });
    await nextTick();
    expect(quadros[1].classes()).toContain('outline-[#25D366]');
    expect(quadros[2].classes()).not.toContain('outline-[#25D366]');
    emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE, { messageId: 99 });
    await nextTick();
    expect(quadros[1].classes()).toContain('outline-[#25D366]');
  });
});

describe('menu do álbum apaga todos os itens (#1702)', () => {
  const montarMenu = message => {
    const deleteMessage = vi.fn();
    const store = createStore({
      getters: {
        'accounts/getAccount': () => () => ({}),
        getCurrentAccountId: () => 1,
        getUISettings: () => ({}),
      },
      actions: { deleteMessage },
    });
    const wrapper = mount(MessageContextMenu, {
      props: { message, enabledOptions: {} },
      global: { plugins: [store], stubs: { ContextMenu: true } },
    });
    return { wrapper, deleteMessage };
  };

  it('com idsDoAlbum, apaga cada item', async () => {
    const { wrapper, deleteMessage } = montarMenu({
      id: 1,
      conversationId: 7,
      idsDoAlbum: [1, 2, 3],
    });
    await wrapper.vm.confirmDeletion();
    expect(deleteMessage.mock.calls.map(([, payload]) => payload)).toEqual([
      { conversationId: 7, messageId: 1 },
      { conversationId: 7, messageId: 2 },
      { conversationId: 7, messageId: 3 },
    ]);
  });

  it('sem álbum, só a mensagem', async () => {
    const { wrapper, deleteMessage } = montarMenu({ id: 5, conversationId: 7 });
    await wrapper.vm.confirmDeletion();
    expect(deleteMessage).toHaveBeenCalledTimes(1);
    expect(deleteMessage.mock.calls[0][1]).toEqual({
      conversationId: 7,
      messageId: 5,
    });
  });
});
