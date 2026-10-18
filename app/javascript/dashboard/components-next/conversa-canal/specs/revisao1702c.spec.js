/* eslint-disable vue/one-component-per-file */
import { computed, defineComponent, h } from 'vue';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/conversaCanal.json';
import Message from '../../message/Message.vue';
import { MESSAGE_STATUS, MESSAGE_TYPES } from '../../message/constants';
import { AGORA, montagem } from '../../message/specs/montarMensagem';
import { PELES, fornecerFuso, fornecerPele } from '../pele';
import CitacaoNaResposta from '../CitacaoNaResposta.vue';

// Achados da revisão crítica do PR de ajustes (17/10): menu fantasma no aviso de
// atividade, foto/vídeo com legenda fora da regra de tamanho e a citação na caixa de
// resposta ao lado do texto, com o desenho do Chatwoot.
vi.mock('vue-router', () => ({ useRoute: () => ({ query: {}, params: {} }) }));

const i18n = () =>
  createI18n({
    legacy: false,
    locale: 'en',
    messages: { en },
    missingWarn: false,
    fallbackWarn: false,
  });

const global = () => ({
  ...montagem,
  plugins: [...montagem.plugins, i18n()],
  stubs: { ...montagem.stubs, NovaConversaEntrada: true, GalleryView: true },
});

const comPele = filho =>
  defineComponent({
    setup() {
      fornecerPele(computed(() => PELES.WHATSAPP));
      fornecerFuso(computed(() => 'America/Sao_Paulo'));
      return () => filho();
    },
  });

const montar = (props = {}) =>
  mount(
    comPele(() =>
      h(Message, {
        id: 1,
        messageType: MESSAGE_TYPES.INCOMING,
        status: MESSAGE_STATUS.SENT,
        content: 'Olá',
        conversationId: 7,
        createdAt: AGORA,
        currentUserId: 1,
        sender: { id: 7, name: 'Maria', type: 'Contact' },
        ...props,
      })
    ),
    { global: global() }
  );

const FOTO_ALTA = {
  id: 9,
  fileType: 'image',
  dataUrl: 'https://s3.test/print.png',
  width: 1080,
  height: 1920,
};

describe('revisão do PR de ajustes (#1702)', () => {
  it('aviso de atividade não tem o botão de menu do balão', () => {
    const aviso = montar({
      messageType: MESSAGE_TYPES.ACTIVITY,
      content: 'Conversa atribuída a Marina',
    });

    expect(aviso.find('[data-menu-do-balao]').exists()).toBe(false);
  });

  it('mensagem comum continua com o botão de menu', () => {
    expect(montar().find('[data-menu-do-balao]').exists()).toBe(true);
  });

  it('foto 9:16 com legenda sai no tamanho do app (238x330), em cima da legenda', () => {
    const balao = montar({ content: 'Olha o print', attachments: [FOTO_ALTA] });

    const midia = balao.find('[data-midia-do-whatsapp] img');
    expect(midia.classes()).toEqual(
      expect.arrayContaining(['h-[330px]', 'w-[238px]', 'object-cover'])
    );
    const html = balao.html();
    expect(html.indexOf('data-midia-do-whatsapp')).toBeLessThan(
      html.indexOf('Olha o print')
    );
  });

  it('vídeo com legenda usa o vídeo do app, não o chip do Chatwoot', () => {
    const balao = montar({
      content: 'Olha o vídeo',
      attachments: [
        { id: 3, fileType: 'video', dataUrl: 'https://s3.test/v.mp4' },
      ],
    });

    expect(balao.find('[data-video-do-whatsapp]').exists()).toBe(true);
    expect(balao.find('.contain-content').exists()).toBe(false);
  });

  it('a citação na caixa de resposta é o cartão do WhatsApp, com o X', async () => {
    const citacao = mount(CitacaoNaResposta, {
      props: {
        message: {
          id: 5,
          content: 'Qual o horário?',
          message_type: MESSAGE_TYPES.INCOMING,
          sender: { name: 'Maria' },
        },
      },
      global: {
        plugins: [i18n()],
        directives: {
          dompurifyHtml: (el, { value }) => {
            el.innerHTML = value;
          },
        },
      },
    });

    expect(citacao.text()).toContain('Maria');
    expect(citacao.text()).toContain('Qual o horário?');
    await citacao.find('button').trigger('click');
    expect(citacao.emitted('dismiss')).toHaveLength(1);
  });

  it('a citação na caixa de resposta não é botão (não leva a lugar nenhum)', () => {
    const citacao = mount(CitacaoNaResposta, {
      props: {
        message: { id: 7, content: 'Oi', message_type: MESSAGE_TYPES.INCOMING },
      },
      global: {
        plugins: [i18n()],
        directives: {
          dompurifyHtml: (el, { value }) => {
            el.innerHTML = value;
          },
        },
      },
    });

    expect(citacao.find('[role="button"]').exists()).toBe(false);
    expect(citacao.find('[tabindex="0"]').exists()).toBe(false);
  });

  it('citação de figurinha diz Figurinha, como o balão', () => {
    const citacao = mount(CitacaoNaResposta, {
      props: {
        message: {
          id: 8,
          content: '',
          message_type: MESSAGE_TYPES.INCOMING,
          attachments: [
            { file_type: 'image', extension: 'webp', is_sticker: true },
          ],
        },
      },
      global: {
        plugins: [i18n()],
        directives: {
          dompurifyHtml: (el, { value }) => {
            el.innerHTML = value;
          },
        },
      },
    });

    expect(citacao.text()).toContain(en.CONVERSA_CANAL.MIDIA.FIGURINHA);
  });

  it('citação de foto sem texto mostra "Foto"', () => {
    const citacao = mount(CitacaoNaResposta, {
      props: {
        message: {
          id: 6,
          content: '',
          message_type: MESSAGE_TYPES.OUTGOING,
          attachments: [{ file_type: 'image', thumb_url: 'https://s3.test/t' }],
        },
      },
      global: {
        plugins: [i18n()],
        directives: {
          dompurifyHtml: (el, { value }) => {
            el.innerHTML = value;
          },
        },
      },
    });

    expect(citacao.text()).toContain(en.CONVERSA_CANAL.CITACAO.FOTO);
  });
});
