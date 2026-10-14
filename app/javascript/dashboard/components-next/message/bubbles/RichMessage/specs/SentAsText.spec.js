import { config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/richMessage.json';
import { montarMensagem } from '../../../specs/montarMensagem.js';
import { MESSAGE_STATUS } from '../../../constants';

config.global.plugins = [
  createI18n({ legacy: false, locale: 'pt_BR', messages: { pt_BR: ptBR } }),
];

// chat#1555: o envio rico que saiu como texto (WhatsApp Híbrido, canal sem o formato, caixa API) traz
// `rich_message_sent_as: 'text'` e o texto enviado; a bolha mostra o que o cliente recebeu.
const LINK_BUTTON = {
  type: 'link_button',
  label: 'Abrir',
  url: 'https://exemplo.com.br/x',
};
const TEXTO_ENVIADO = 'Já tenho o retorno\n\nAbrir: https://exemplo.com.br/x';

const nomes = wrapper =>
  wrapper
    .findAll('[data-bubble-name]')
    .map(node => node.attributes('data-bubble-name'));

const montar = contentAttributes =>
  montarMensagem({ content: 'Já tenho o retorno', contentAttributes });

describe('bolha do envio rico que saiu como texto', () => {
  it('mostra o texto que o cliente recebeu e a linha "Enviado como texto"', () => {
    const wrapper = montar({
      richMessage: LINK_BUTTON,
      richMessageSentAs: 'text',
      richMessageSentText: TEXTO_ENVIADO,
    });

    expect(nomes(wrapper)).toEqual(['rich-sent-as-text']);
    expect(wrapper.text()).toContain('Já tenho o retorno');
    expect(wrapper.text()).toContain('Abrir: https://exemplo.com.br/x');
    expect(wrapper.text()).toContain('Enviado como texto');
    expect(wrapper.find('[data-bubble-name="rich-link-button"]').exists()).toBe(
      false
    );
  });

  it('vale também para tipo que não tem bolha própria', () => {
    const wrapper = montar({
      richMessage: { type: 'tipo_sem_bolha' },
      richMessageSentAs: 'text',
      richMessageSentText: 'Já tenho o retorno\n\nComplemento',
    });

    expect(nomes(wrapper)).toEqual(['rich-sent-as-text']);
    expect(wrapper.text()).toContain('Complemento');
  });

  it('trata o texto enviado como texto, nunca como HTML', () => {
    const wrapper = montar({
      richMessage: LINK_BUTTON,
      richMessageSentAs: 'text',
      richMessageSentText: '<img src=x onerror=alert(1)>',
    });

    expect(wrapper.find('img').exists()).toBe(false);
  });

  it('sem a marca continua na bolha do formato', () => {
    const wrapper = montar({ richMessage: LINK_BUTTON });

    expect(nomes(wrapper)).toEqual(['rich-link-button']);
    expect(wrapper.text()).not.toContain('Enviado como texto');
  });

  it('com falha segue a bolha do formato com o motivo, como hoje (ex.: webhook da caixa API deu 500)', () => {
    const wrapper = montarMensagem({
      content: 'Já tenho o retorno',
      status: MESSAGE_STATUS.FAILED,
      contentAttributes: {
        richMessage: LINK_BUTTON,
        richMessageSentAs: 'text',
        richMessageSentText: TEXTO_ENVIADO,
        externalError: 'O webhook da caixa respondeu 500.',
      },
    });

    expect(nomes(wrapper)).toEqual(['rich-link-button']);
    expect(wrapper.text()).toContain('O webhook da caixa respondeu 500.');
    expect(wrapper.text()).not.toContain('Enviado como texto');
  });

  it('nota privada com a marca não ganha a bolha: não foi ao cliente', () => {
    const wrapper = montarMensagem({
      content: 'Já tenho o retorno',
      private: true,
      contentAttributes: {
        richMessage: LINK_BUTTON,
        richMessageSentAs: 'text',
        richMessageSentText: TEXTO_ENVIADO,
      },
    });

    expect(nomes(wrapper)).not.toContain('rich-sent-as-text');
  });
});
