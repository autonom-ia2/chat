// Nota técnica antiga do conector WAHA (#1941, item 2): na caixa WAHA comum, a nota
// privada que começa pelo título do conector aparece como a linha de aviso, com o texto
// curto, na conversa e na prévia da lista. Nota comum e mensagem do cliente ficam iguais.
import { nextTick } from 'vue';
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { withFullI18n } from 'test-i18n';
import en from 'dashboard/i18n/locale/en/conversaCanal.json';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import Message from '../../message/Message.vue';
import { MESSAGE_STATUS, MESSAGE_TYPES } from '../../message/constants';
import {
  AGORA,
  gettersDaMontagem,
  montagem,
} from '../../message/specs/montarMensagem';
import MessagePreview from '../../Conversation/ConversationCard/MessagePreview.vue';
import MessagePreviewAntigo from '../../../components/widgets/conversation/MessagePreview.vue';
import {
  PREFIXO_DA_NOTA_DO_CONECTOR,
  ehNotaDoConector,
} from '../notaDoConector';

// Com o catálogo de verdade: a chave errada ou faltando não passa.
withFullI18n('pt_BR');
const AVISO_DA_NOTA_DO_CONECTOR =
  '⚠️ Uma mensagem do WhatsApp não chegou aqui. Confira no celular da caixa.';

vi.mock('vue-router', () => ({ useRoute: () => ({ query: {}, params: {} }) }));

const CAIXA_WAHA = {
  id: 3,
  channel_type: INBOX_TYPES.API,
  waha_provider: true,
};
const CAIXA_API = {
  id: 4,
  channel_type: INBOX_TYPES.API,
  waha_provider: false,
};
const CAIXA_OFICIAL = { id: 5, channel_type: INBOX_TYPES.WHATSAPP };
const CAIXAS = [CAIXA_WAHA, CAIXA_API, CAIXA_OFICIAL];

const NOTA_TECNICA = `${PREFIXO_DA_NOTA_DO_CONECTOR}

Motivo: falha ao baixar a mídia (HTTP 500) depois de 3 tentativas.
ID externo: false_5511999999999@c.us_3EB0ABC`;

const caixaPorId = () => id => CAIXAS.find(caixa => caixa.id === id) || {};

const loja = createStore({
  getters: { ...gettersDaMontagem, 'inboxes/getInbox': caixaPorId },
});

// A lista de caixas chega depois da conversa (painel abrindo direto numa conversa).
const lojaQueCarrega = () =>
  createStore({
    state: { caixas: [] },
    getters: {
      ...gettersDaMontagem,
      'inboxes/getInbox': estado => id =>
        estado.caixas.find(caixa => caixa.id === id) || {},
    },
    mutations: {
      carregar(estado, caixas) {
        estado.caixas = caixas;
      },
    },
  });

const montarMensagem = (props = {}) =>
  mount(Message, {
    props: {
      id: 1,
      messageType: MESSAGE_TYPES.OUTGOING,
      status: MESSAGE_STATUS.SENT,
      content: NOTA_TECNICA,
      conversationId: 7,
      createdAt: AGORA,
      currentUserId: 1,
      inboxId: CAIXA_WAHA.id,
      private: true,
      sender: { id: 1, name: 'Marina', type: 'User' },
      ...props,
    },
    global: { ...montagem, plugins: [loja] },
  });

const nomesDasBolhas = wrapper =>
  wrapper
    .findAll('[data-bubble-name]')
    .map(node => node.attributes('data-bubble-name'));

describe('ehNotaDoConector (#1941)', () => {
  it('o título é o do conector, com o ⚠️ de dois pontos de código', () => {
    expect(PREFIXO_DA_NOTA_DO_CONECTOR.codePointAt(0)).toBe(0x26a0);
    expect(PREFIXO_DA_NOTA_DO_CONECTOR.codePointAt(1)).toBe(0xfe0f);
    expect(PREFIXO_DA_NOTA_DO_CONECTOR).toBe(
      '⚠️ **Não foi possível receber uma mensagem do WhatsApp**'
    );
  });

  it('reconhece a nota privada da caixa WAHA que começa pelo título', () => {
    expect(
      ehNotaDoConector({
        caixa: CAIXA_WAHA,
        privada: true,
        conteudo: NOTA_TECNICA,
      })
    ).toBe(true);
  });

  it.each([
    ['mensagem pública com o mesmo texto', CAIXA_WAHA, false, NOTA_TECNICA],
    ['privacidade ausente', CAIXA_WAHA, undefined, NOTA_TECNICA],
    ['caixa API sem WAHA', CAIXA_API, true, NOTA_TECNICA],
    ['WhatsApp oficial', CAIXA_OFICIAL, true, NOTA_TECNICA],
    ['caixa ainda não carregada', undefined, true, NOTA_TECNICA],
    ['nota comum', CAIXA_WAHA, true, 'Cliente pediu retorno amanhã.'],
    ['título no meio da nota', CAIXA_WAHA, true, `Veja: ${NOTA_TECNICA}`],
    [
      'título sem o seletor de emoji',
      CAIXA_WAHA,
      true,
      NOTA_TECNICA.replace('️', ''),
    ],
    ['nota sem texto', CAIXA_WAHA, true, null],
  ])('não reconhece: %s', (_, caixa, privada, conteudo) => {
    expect(ehNotaDoConector({ caixa, privada, conteudo })).toBe(false);
  });
});

describe('texto do aviso (#1941)', () => {
  it('em inglês, o texto combinado', () => {
    expect(en.CONVERSA_CANAL.NOTA_DO_CONECTOR.AVISO).toBe(
      '⚠️ A WhatsApp message did not reach this conversation. Check the inbox phone.'
    );
  });
});

describe('na conversa (#1941)', () => {
  it('a nota técnica vira a linha de aviso, sem o corpo técnico e sem menu', () => {
    const wrapper = montarMensagem();

    expect(nomesDasBolhas(wrapper)).toEqual(['activity']);
    expect(wrapper.text()).toContain(AVISO_DA_NOTA_DO_CONECTOR);
    expect(wrapper.html()).not.toContain('HTTP 500');
    expect(wrapper.html()).not.toContain('Não foi possível receber');
    expect(wrapper.get('.message-bubble-container').classes()).toContain(
      'justify-center'
    );
    expect(wrapper.find('context-menu-stub').exists()).toBe(false);
  });

  it('a caixa que carrega depois troca a nota pelo aviso', async () => {
    const lojaDaVez = lojaQueCarrega();
    const wrapper = mount(Message, {
      props: {
        id: 1,
        messageType: MESSAGE_TYPES.OUTGOING,
        status: MESSAGE_STATUS.SENT,
        content: NOTA_TECNICA,
        conversationId: 7,
        createdAt: AGORA,
        currentUserId: 1,
        inboxId: CAIXA_WAHA.id,
        private: true,
        sender: { id: 1, name: 'Marina', type: 'User' },
      },
      global: { ...montagem, plugins: [lojaDaVez] },
    });
    expect(nomesDasBolhas(wrapper)).toEqual(['text']);

    lojaDaVez.commit('carregar', CAIXAS);
    await nextTick();

    expect(nomesDasBolhas(wrapper)).toEqual(['activity']);
    expect(wrapper.text()).toContain(AVISO_DA_NOTA_DO_CONECTOR);
    expect(wrapper.html()).not.toContain('HTTP 500');
  });

  it('nota comum na caixa WAHA continua nota privada', () => {
    const wrapper = montarMensagem({ content: 'Cliente pediu retorno.' });

    expect(nomesDasBolhas(wrapper)).toEqual(['text']);
    expect(wrapper.text()).toContain('Cliente pediu retorno.');
    expect(wrapper.text()).not.toContain(AVISO_DA_NOTA_DO_CONECTOR);
  });

  it('mensagem do cliente com o mesmo texto fica como chegou', () => {
    const wrapper = montarMensagem({
      private: false,
      messageType: MESSAGE_TYPES.INCOMING,
      sender: { id: 9, name: 'Camila', type: 'Contact' },
    });

    expect(nomesDasBolhas(wrapper)).toEqual(['text']);
    expect(wrapper.text()).toContain('Não foi possível receber');
    expect(wrapper.text()).not.toContain(AVISO_DA_NOTA_DO_CONECTOR);
  });

  it('a mesma nota numa caixa que não é WAHA fica como está', () => {
    const wrapper = montarMensagem({ inboxId: CAIXA_OFICIAL.id });

    expect(nomesDasBolhas(wrapper)).toEqual(['text']);
    expect(wrapper.text()).toContain('Não foi possível receber');
    expect(wrapper.text()).not.toContain(AVISO_DA_NOTA_DO_CONECTOR);
  });
});

describe('na prévia da lista (#1941)', () => {
  const ultima = (mudancas = {}) => ({
    message_type: MESSAGE_TYPES.OUTGOING,
    private: true,
    content: NOTA_TECNICA,
    inbox_id: CAIXA_WAHA.id,
    attachments: [],
    ...mudancas,
  });
  const montarPrevia = (Previa, mensagem) =>
    mount(Previa, {
      props: { message: mensagem },
      global: { plugins: [loja], stubs: { FluentIcon: true } },
    });

  it.each([
    ['nova', MessagePreview],
    ['antiga', MessagePreviewAntigo],
  ])('a prévia %s mostra o aviso curto', (_, Previa) => {
    const texto = montarPrevia(Previa, ultima()).text();

    expect(texto).toContain(AVISO_DA_NOTA_DO_CONECTOR);
    expect(texto).not.toContain('Não foi possível receber');
    expect(texto).not.toContain('HTTP 500');
  });

  it('a prévia nova troca o cadeado pelo ícone de aviso', () => {
    const html = montarPrevia(MessagePreview, ultima()).html();

    expect(html).toContain('i-lucide-info');
    expect(html).not.toContain('i-lucide-lock-keyhole');
  });

  it.each([
    ['nova', MessagePreview, 'nota comum', { content: 'Retorno amanhã.' }],
    [
      'antiga',
      MessagePreviewAntigo,
      'nota comum',
      { content: 'Retorno amanhã.' },
    ],
    ['nova', MessagePreview, 'mensagem do cliente', { private: false }],
    ['antiga', MessagePreviewAntigo, 'mensagem do cliente', { private: false }],
    ['nova', MessagePreview, 'outra caixa', { inbox_id: CAIXA_OFICIAL.id }],
    ['antiga', MessagePreviewAntigo, 'outra caixa', { inbox_id: CAIXA_API.id }],
  ])('a prévia %s fica igual para %s', (_, Previa, __, mudancas) => {
    const texto = montarPrevia(Previa, ultima(mudancas)).text();

    expect(texto).not.toContain(AVISO_DA_NOTA_DO_CONECTOR);
    expect(texto).toContain(mudancas.content || 'Não foi possível receber');
  });
});
