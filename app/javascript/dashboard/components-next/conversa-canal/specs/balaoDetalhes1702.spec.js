/* eslint-disable vue/one-component-per-file */
import { computed, defineComponent, h } from 'vue';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createPinia } from 'pinia';
import VoiceCall from '../../message/bubbles/VoiceCall.vue';
import en from 'dashboard/i18n/locale/en/conversaCanal.json';
import ptBR from 'dashboard/i18n/locale/pt_BR/conversaCanal.json';
import Message from '../../message/Message.vue';
import MessageError from '../../message/MessageError.vue';
import {
  CONTENT_TYPES,
  MESSAGE_STATUS,
  MESSAGE_TYPES,
  MESSAGE_VARIANTS,
  ORIENTATION,
} from '../../message/constants';
import { montagem } from '../../message/specs/montarMensagem';
import { PELES, fornecerFuso, fornecerPele } from '../pele';
import { classesDoBalao, corDoBico } from '../visualWhatsapp';
import { dataEHoraDaMensagem } from '../dataDaConversa';
import { LIMITE_DO_TEXTO, cortarTextoLongo } from '../textoLongo';
import { ligacaoDaCloudNoCartao } from '../ligacao/ligacao';
import { miniaturaDoAnexoCitado, previaDoAnexoCitado } from '../citacaoDoAnexo';

// Detalhes do balão (#1702): apagada só aqui, a que falhou, a dica da hora no fuso da
// conta, citação de mídia, ligação da Cloud e "Ler mais".
vi.mock('vue-router', () => ({ useRoute: () => ({ query: {}, params: {} }) }));

// 17/10/2025 17:00 UTC = 14:00 em São Paulo. O teste roda com TZ=UTC: se a dica usasse
// o fuso do navegador, sairia 5:00 PM.
const QUANDO = 1760720400;

const i18n = (locale = 'en') =>
  createI18n({
    legacy: false,
    locale,
    messages: { en, pt_BR: ptBR },
    missingWarn: false,
    fallbackWarn: false,
  });

// A dica (v-tooltip) vira um atributo, para o teste ler o que a pessoa veria.
const dica = (el, { value }) => {
  el.dataset.dica = value?.content ?? value ?? '';
};

const global = ({ meta = false } = {}) => ({
  ...montagem,
  // O balão de ligação do Chatwoot usa a loja de ligações (Pinia).
  plugins: [...montagem.plugins, i18n(), createPinia()],
  directives: { ...montagem.directives, tooltip: dica },
  stubs: {
    ...montagem.stubs,
    MessageMeta: !meta,
    NovaConversaEntrada: true,
    GalleryView: true,
    VoiceCall: true,
  },
});

const comPele = (pele, filho) =>
  defineComponent({
    setup() {
      fornecerPele(computed(() => pele));
      fornecerFuso(computed(() => 'America/Sao_Paulo'));
      return () => filho();
    },
  });

const montar = (props = {}, { pele = PELES.WHATSAPP, meta = false } = {}) =>
  mount(
    comPele(pele, () =>
      h(Message, {
        id: 1,
        messageType: MESSAGE_TYPES.INCOMING,
        status: MESSAGE_STATUS.SENT,
        content: 'Olá',
        conversationId: 7,
        createdAt: QUANDO,
        currentUserId: 1,
        sender: { id: 7, name: 'Maria', type: 'Contact' },
        ...props,
      })
    ),
    { global: global({ meta }) }
  );

const ENVIADA = {
  messageType: MESSAGE_TYPES.OUTGOING,
  sender: { id: 1, name: 'Ana', type: 'User' },
};

describe('apagada pela equipe: só aqui ou para todos (#1702)', () => {
  it('sem a revogação no canal, diz que o cliente ainda vê', () => {
    const balao = montar({ ...ENVIADA, contentAttributes: { deleted: true } });
    const aviso = balao.find('[data-apagada-pela-equipe]');
    expect(aviso.text()).toBe(
      'You deleted this message only here. The customer still sees it.'
    );
    expect(aviso.attributes()).toHaveProperty('data-apagada-so-aqui');
    expect(aviso.find('.i-ph-prohibit').exists()).toBe(true);
  });

  it('com revogada_no_canal, o texto do app (sumiu para todos)', () => {
    const balao = montar({
      ...ENVIADA,
      contentAttributes: { deleted: true, revogadaNoCanal: true },
    });
    const aviso = balao.find('[data-apagada-pela-equipe]');
    expect(aviso.text()).toBe('You deleted this message');
    expect(aviso.attributes()).not.toHaveProperty('data-apagada-so-aqui');
  });

  it('a do cliente apagada por ele continua como está', () => {
    const recebida = montar({ contentAttributes: { deleted: true } });
    expect(recebida.find('[data-apagada-pela-equipe]').text()).toBe(
      'This message was deleted'
    );
    const peloCliente = montar({
      contentAttributes: { deletedByContactAt: '2026-10-16T18:00:00Z' },
    });
    expect(peloCliente.find('[data-apagada-pelo-cliente]').exists()).toBe(true);
    expect(peloCliente.find('[data-apagada-pela-equipe]').exists()).toBe(false);
  });

  it('o aviso existe em pt_BR', () => {
    expect(ptBR.CONVERSA_CANAL.APAGADA.ENVIADA_SO_AQUI).toBe(
      'Você apagou esta mensagem só aqui. O cliente ainda vê.'
    );
  });
});

describe('mensagem que falhou (#1702)', () => {
  it('balão verde da enviada, sem o rosa, e o bico da mesma cor', () => {
    const estado = {
      variante: MESSAGE_VARIANTS.ERROR,
      lado: ORIENTATION.RIGHT,
      primeira: true,
      nomeDoBalao: 'text',
    };
    expect(classesDoBalao(estado)).toContain('!bg-[#D9FDD3]');
    expect(classesDoBalao(estado)).not.toContain('FDE7E9');
    expect(corDoBico(estado)).toBe('text-[#D9FDD3] dark:text-[#144D37]');
  });

  it('ícone vermelho de exclamação ao lado da hora, no lugar dos tiques', () => {
    const balao = montar(
      { ...ENVIADA, status: MESSAGE_STATUS.FAILED },
      { meta: true }
    );
    const falha = balao.find('[data-falha-do-whatsapp]');
    expect(falha.exists()).toBe(true);
    expect(falha.classes()).toContain('i-ph-warning-circle-fill');
    expect(falha.attributes('aria-label')).toBe('Not sent');
    expect(balao.find('[data-tiques-do-whatsapp]').exists()).toBe(false);
    expect(balao.find('[data-bubble-name="text"]').classes()).toContain(
      '!bg-[#D9FDD3]'
    );
  });

  it('o aviso com "tentar de novo" (MessageError) continua embaixo', () => {
    const balao = montar({
      ...ENVIADA,
      status: MESSAGE_STATUS.FAILED,
      contentAttributes: { externalError: 'Janela de 24 h fechada' },
    });
    expect(balao.findComponent(MessageError).exists()).toBe(true);
  });

  it('sem a pele, nada muda: sem o ícone e o balão do Chatwoot', () => {
    const balao = montar(
      { ...ENVIADA, status: MESSAGE_STATUS.FAILED },
      { pele: null, meta: true }
    );
    expect(balao.find('[data-falha-do-whatsapp]').exists()).toBe(false);
    expect(balao.find('[data-bubble-name="text"]').classes()).toContain(
      'bg-n-ruby-4'
    );
  });
});

describe('dica da hora no fuso da conta (#1702)', () => {
  it('a dica usa o fuso da conta, sem o nome do fuso', () => {
    const balao = montar({}, { meta: true });
    const hora = balao.find('time');
    expect(hora.text()).toBe('14:00');
    expect(hora.attributes('data-dica')).toBe('Oct 17, 2025, 2:00 PM');
  });

  it('no idioma do painel e nunca "Brasília"', () => {
    const texto = dataEHoraDaMensagem(QUANDO, 'America/Sao_Paulo', 'pt-BR');
    expect(texto).toContain('14:00');
    expect(texto).toContain('17');
    expect(texto).not.toContain('Brasília');
    expect(texto).not.toContain('BRT');
  });

  it('sem a pele, a dica segue no fuso do navegador', () => {
    const balao = montar({}, { pele: null, meta: true });
    expect(balao.find('time').attributes('data-dica')).toContain('5:00');
  });
});

describe('citação de mídia no balão (#1702)', () => {
  const citando = (anexo, opcoes) =>
    montar(
      {
        ...ENVIADA,
        content: 'Recebi',
        inReplyTo: {
          id: 9,
          content: '',
          messageType: MESSAGE_TYPES.INCOMING,
          sender: { name: 'Maria' },
          attachments: [anexo],
        },
      },
      opcoes
    );

  it('documento: ícone e o nome do arquivo', () => {
    const balao = citando({
      fileType: 'file',
      dataUrl: 'https://s3.test/a/contrato%20final.pdf?x=1',
    });
    const citacao = balao.find('[role="button"]');
    expect(citacao.text()).toContain('contrato final.pdf');
    expect(citacao.find('.i-ph-file-fill').exists()).toBe(true);
  });

  it('foto: "Photo", ícone de câmera e a miniatura', () => {
    const citacao = citando({
      fileType: 'image',
      thumbUrl: 'https://s3.test/mini.jpg',
      dataUrl: 'https://s3.test/foto.jpg',
    }).find('[role="button"]');
    expect(citacao.text()).toContain('Photo');
    expect(citacao.find('.i-ph-camera-fill').exists()).toBe(true);
    expect(citacao.find('img').attributes('src')).toBe(
      'https://s3.test/mini.jpg'
    );
  });

  it('vídeo: miniatura só quando há thumbUrl', () => {
    const comMiniatura = citando({
      fileType: 'video',
      thumbUrl: 'https://s3.test/mini.jpg',
      dataUrl: 'https://s3.test/v.mp4',
    }).find('[role="button"]');
    expect(comMiniatura.text()).toContain('Video');
    expect(comMiniatura.find('img').exists()).toBe(true);
    const semMiniatura = citando({
      fileType: 'video',
      dataUrl: 'https://s3.test/v.mp4',
    }).find('[role="button"]');
    expect(semMiniatura.find('img').exists()).toBe(false);
  });

  it('áudio e figurinha: os rótulos do app', () => {
    const t = chave => chave;
    expect(
      previaDoAnexoCitado({ attachments: [{ file_type: 'audio' }] }, t)
    ).toBe('CONVERSA_CANAL.CITACAO.AUDIO');
    expect(
      previaDoAnexoCitado(
        { attachments: [{ fileType: 'image', isSticker: true }] },
        t
      )
    ).toBe('CONVERSA_CANAL.MIDIA.FIGURINHA');
    expect(previaDoAnexoCitado({ attachments: [] }, t)).toBe(
      'CONVERSA_CANAL.CITACAO.SEM_TEXTO'
    );
    expect(
      miniaturaDoAnexoCitado({
        attachments: [{ file_type: 'video', data_url: 'v.mp4' }],
      })
    ).toBe('');
  });

  it('sem a pele, a citação do Chatwoot com o rótulo de sempre', () => {
    const balao = citando(
      { fileType: 'file', dataUrl: 'https://s3.test/contrato.pdf' },
      { pele: null }
    );
    expect(balao.text()).toContain('CHAT_LIST.ATTACHMENTS.file.CONTENT');
    expect(balao.text()).not.toContain('contrato.pdf');
  });
});

describe('ligação da Cloud API (#1702)', () => {
  const ligacao = (call, props = {}, opcoes = {}) =>
    montar(
      {
        ...ENVIADA,
        // O servidor sempre grava um texto (call_message_builder.rb).
        content: 'WhatsApp call',
        contentType: CONTENT_TYPES.VOICE_CALL,
        call,
        ...props,
      },
      opcoes
    );

  it('feita pela empresa e atendida: o cartão do app, com a hora', () => {
    const cartao = ligacao({
      status: 'completed',
      direction: 'outbound',
    }).find('[data-ligacao-do-whatsapp]');
    expect(cartao.exists()).toBe(true);
    expect(cartao.find('[data-titulo-da-ligacao]').text()).toBe('Voice call');
    expect(cartao.text()).toContain('14:00');
    expect(cartao.classes()).toContain('bg-[#D9FDD3]');
    expect(cartao.find('.i-ph-phone-outgoing-fill').exists()).toBe(true);
  });

  it('feita pela empresa sem resposta: sem o vermelho da perdida', () => {
    const cartao = ligacao({
      status: 'no-answer',
      direction: 'outbound',
    }).find('[data-ligacao-do-whatsapp]');
    const titulo = cartao.find('[data-titulo-da-ligacao]');
    expect(titulo.text()).toBe('Voice call, no answer');
    expect(titulo.classes()).not.toContain('text-[#EA0038]');
  });

  it('do cliente, atendida: o cartão do lado do cliente', () => {
    const cartao = ligacao(
      { status: 'completed', direction: 'inbound' },
      {
        messageType: MESSAGE_TYPES.INCOMING,
        sender: { id: 7, type: 'Contact' },
      }
    ).find('[data-ligacao-do-whatsapp]');
    expect(cartao.classes()).toContain('bg-white');
    expect(cartao.find('.i-ph-phone-incoming-fill').exists()).toBe(true);
  });

  it('com ação no balão do Chatwoot (perdida, gravação, tocando), ele fica', () => {
    const perdida = ligacao(
      { status: 'no-answer', direction: 'inbound' },
      {
        messageType: MESSAGE_TYPES.INCOMING,
        sender: { id: 7, type: 'Contact' },
      }
    );
    expect(perdida.find('[data-ligacao-do-whatsapp]').exists()).toBe(false);
    expect(perdida.findComponent(VoiceCall).exists()).toBe(true);
    expect(
      ligacaoDaCloudNoCartao({
        chamada: { status: 'completed', recordingUrl: 'https://s3.test/a.wav' },
        enviada: true,
      })
    ).toBe(false);
    expect(
      ligacaoDaCloudNoCartao({
        chamada: { status: 'completed' },
        enviada: true,
        anexos: [{ fileType: 'audio' }],
      })
    ).toBe(false);
    expect(
      ligacaoDaCloudNoCartao({ chamada: { status: 'ringing' }, enviada: false })
    ).toBe(false);
    expect(
      ligacaoDaCloudNoCartao({
        chamada: { status: 'in-progress' },
        enviada: true,
      })
    ).toBe(false);
  });

  it('sem a pele, o balão de ligação do Chatwoot', () => {
    const balao = ligacao(
      { status: 'completed', direction: 'outbound' },
      {},
      { pele: null }
    );
    expect(balao.find('[data-ligacao-do-whatsapp]').exists()).toBe(false);
    expect(balao.findComponent(VoiceCall).exists()).toBe(true);
  });
});

describe('"Ler mais" no texto longo (#1702)', () => {
  const LONGO = 'palavra '.repeat(200).trim();

  it('corta no último espaço antes do limite, com reticências', () => {
    const cortado = cortarTextoLongo(LONGO);
    expect(cortado.length).toBeLessThanOrEqual(LIMITE_DO_TEXTO + 1);
    expect(cortado.endsWith('palavra…')).toBe(true);
    expect(cortarTextoLongo('curto')).toBeNull();
    expect(cortarTextoLongo('a'.repeat(LIMITE_DO_TEXTO))).toBeNull();
    // Sem espaço para cortar, corta no limite.
    expect(cortarTextoLongo('a'.repeat(1000))).toBe(
      `${'a'.repeat(LIMITE_DO_TEXTO)}…`
    );
  });

  it('com a pele, mostra o começo e "Read more" abre tudo', async () => {
    const balao = montar({ content: LONGO });
    const texto = () => balao.find('.prose-bubble').text();
    expect(texto().length).toBeLessThan(LONGO.length);
    const botao = balao.find('[data-ler-mais]');
    expect(botao.text()).toBe('Read more');
    await botao.trigger('click');
    expect(texto()).toBe(LONGO);
    expect(balao.find('[data-ler-mais]').exists()).toBe(false);
  });

  it('texto curto não ganha o botão', () => {
    expect(montar().find('[data-ler-mais]').exists()).toBe(false);
  });

  it('sem a pele, o texto inteiro, como sempre', () => {
    const balao = montar({ content: LONGO }, { pele: null });
    expect(balao.find('[data-ler-mais]').exists()).toBe(false);
    expect(balao.find('.prose-bubble').text()).toBe(LONGO);
  });
});
