/* eslint-disable vue/one-component-per-file */
// #1740: a prévia da mensagem citada lê o texto como o balão dela o mostra. Do cliente
// (e eco do celular, modelo da Meta), no formato do WhatsApp; do robô, no tolerante;
// da pessoa no painel, o markdown de sempre. Sem a pele, a citação de sempre.
import { computed, defineComponent, h } from 'vue';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/conversaCanal.json';
import Message from '../../message/Message.vue';
import { MESSAGE_STATUS, MESSAGE_TYPES } from '../../message/constants';
import { AGORA, montagem } from '../../message/specs/montarMensagem';
import { PELES, fornecerFuso, fornecerPele } from '../pele';
import CitacaoNaResposta from '../CitacaoNaResposta.vue';
import CitacaoDoWhatsapp from '../CitacaoDoWhatsapp.vue';
import { citacaoSolta } from '../citacaoSolta';
import {
  FORMATOS,
  formatarNoFormato,
  formatoDaMensagem,
  previaDaCitada,
} from '../useFormatoDoWhatsapp';

vi.mock('vue-router', () => ({ useRoute: () => ({ query: {}, params: {} }) }));

const { INCOMING, OUTGOING } = MESSAGE_TYPES;

const i18n = () =>
  createI18n({
    legacy: false,
    locale: 'en',
    messages: { en },
    missingWarn: false,
    fallbackWarn: false,
  });

const htmlDireto = {
  dompurifyHtml: (el, { value }) => {
    el.innerHTML = value;
  },
};

describe('formatoDaMensagem e previaDaCitada (#1740)', () => {
  it.each([
    [
      'do cliente, chaves do servidor',
      { content: '*a*', message_type: INCOMING },
      FORMATOS.APP,
    ],
    [
      'eco do celular, chaves do servidor',
      {
        content: '*a*',
        message_type: OUTGOING,
        content_attributes: { external_echo: true },
      },
      FORMATOS.APP,
    ],
    [
      'modelo da Meta',
      {
        content: '*a*',
        message_type: OUTGOING,
        additional_attributes: { template_params: { name: 'oi' } },
      },
      FORMATOS.APP,
    ],
    [
      'robô (sender_type cru)',
      { content: '*a*', message_type: OUTGOING, sender_type: 'AgentBot' },
      FORMATOS.ROBO,
    ],
    [
      'robô (camelCase, sender.type)',
      { content: '*a*', messageType: OUTGOING, sender: { type: 'agent_bot' } },
      FORMATOS.ROBO,
    ],
    [
      'follow-up em nome de pessoa',
      {
        content: '*a*',
        message_type: OUTGOING,
        sender_type: 'User',
        content_attributes: { crm_follow_up_id: 3 },
      },
      FORMATOS.ROBO,
    ],
    [
      'pessoa no painel',
      { content: '*a*', message_type: OUTGOING, sender_type: 'User' },
      null,
    ],
    [
      'nota privada',
      { content: '*a*', message_type: OUTGOING, private: true },
      null,
    ],
  ])('%s', (_, mensagem, formato) => {
    expect(formatoDaMensagem(mensagem)).toBe(formato);
  });

  it.each([
    [
      { content: '*a* ~b~', message_type: INCOMING },
      '<strong>a</strong> <s>b</s>',
    ],
    [
      { content: '**a**', message_type: OUTGOING, sender_type: 'AgentBot' },
      '<strong>a</strong>',
    ],
    [{ content: '**a**', message_type: INCOMING }, '**a**'],
  ])('prévia de %o', (mensagem, esperado) => {
    expect(previaDaCitada(mensagem)).toBe(`<p>${esperado}</p>`);
  });

  it('pessoa no painel: o markdown de sempre (*a* é itálico)', () => {
    const html = previaDaCitada({
      content: '*a*',
      message_type: OUTGOING,
      sender_type: 'User',
    });
    expect(html).toContain('<em>a</em>');
    expect(html).not.toContain('<strong>');
  });

  it('formatarNoFormato sem formato usa o markdown de sempre', () => {
    expect(formatarNoFormato('# t', null)).toContain('<h1');
    expect(formatarNoFormato('# t', FORMATOS.APP)).toBe('<p># t</p>');
  });
});

describe('CitacaoNaResposta com o formato do WhatsApp (#1740)', () => {
  const montar = message =>
    mount(CitacaoNaResposta, {
      props: { message },
      global: { plugins: [i18n()], directives: htmlDireto },
    });

  it('do cliente: *x* negrito e ~x~ riscado, como no app', () => {
    const citacao = montar({
      id: 5,
      content: '*Pedido* ~antigo~ #3',
      message_type: INCOMING,
      sender: { name: 'Maria' },
    });
    expect(citacao.find('strong').text()).toBe('Pedido');
    expect(citacao.find('s').text()).toBe('antigo');
    expect(citacao.find('h1').exists()).toBe(false);
    expect(citacao.find('em').exists()).toBe(false);
  });

  it('da pessoa no painel: o markdown de sempre', () => {
    const citacao = montar({
      id: 6,
      content: '*ênfase*',
      message_type: OUTGOING,
      sender_type: 'User',
      sender: { name: 'Ana', type: 'user' },
    });
    expect(citacao.find('em').text()).toBe('ênfase');
  });
});

describe('Citação solta com o formato do WhatsApp (#1740)', () => {
  it('o trecho do celular sai com a formatação do app e sem links', () => {
    const solta = citacaoSolta({
      quotedMessage: {
        messageId: null,
        content: '*oi* veja https://x.com/_a_',
        fromMe: false,
        unverified: true,
      },
    });
    const wrapper = mount(CitacaoDoWhatsapp, {
      props: { solta },
      global: { plugins: [i18n()], directives: htmlDireto },
    });
    expect(wrapper.find('strong').text()).toBe('oi');
    expect(wrapper.find('a').exists()).toBe(false);
    expect(wrapper.find('em').exists()).toBe(false);
    expect(wrapper.text()).toContain('https://x.com/_a_');
  });
});

describe('Citação no balão (#1740)', () => {
  const global = () => ({
    ...montagem,
    plugins: [...montagem.plugins, i18n()],
    stubs: { ...montagem.stubs, NovaConversaEntrada: true },
  });

  const montar = (inReplyTo, pele) =>
    mount(
      defineComponent({
        setup() {
          fornecerPele(computed(() => pele));
          fornecerFuso(computed(() => 'America/Sao_Paulo'));
          return () =>
            h(Message, {
              id: 1,
              messageType: OUTGOING,
              status: MESSAGE_STATUS.SENT,
              content: 'Resposta',
              conversationId: 7,
              createdAt: AGORA,
              currentUserId: 1,
              sender: { id: 1, name: 'Ana', type: 'user' },
              inReplyTo,
            });
        },
      }),
      { global: global() }
    );

  const doCliente = {
    id: 2,
    content: '*negrito* e _itálico_',
    messageType: INCOMING,
    sender: { name: 'Maria', type: 'contact' },
  };

  it('com a pele, a prévia lê o texto do cliente no formato do app', () => {
    const wrapper = montar(doCliente, PELES.WHATSAPP);
    const citacao = wrapper.findComponent({ name: 'CitacaoDoWhatsapp' });
    expect(citacao.find('strong').text()).toBe('negrito');
    expect(citacao.find('em').text()).toBe('itálico');
  });

  it('sem a pele, a citação de sempre (markdown: *x* itálico)', () => {
    const wrapper = montar(doCliente, null);
    expect(wrapper.findComponent({ name: 'CitacaoDoWhatsapp' }).exists()).toBe(
      false
    );
    expect(wrapper.find('.line-clamp-2 strong').exists()).toBe(false);
    expect(wrapper.find('.line-clamp-2 em').text()).toBe('negrito');
  });
});
