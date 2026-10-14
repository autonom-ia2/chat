import { config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import Contact from '../types/Contact.vue';
import ptBR from 'dashboard/i18n/locale/pt_BR/richMessage.json';
import { montarRica } from './montarRica.js';
import { montarMensagem } from '../../../specs/montarMensagem.js';

config.global.plugins = [
  createI18n({ legacy: false, locale: 'pt_BR', messages: { pt_BR: ptBR } }),
];

const RECEPCAO = {
  type: 'contact',
  name: 'Recepção da Unidade Centro',
  phone: '+55 11 4000-0473',
};

describe('bolha do contato enviado', () => {
  it('mostra quem enviou, o nome e o telefone do contato', () => {
    const wrapper = montarRica(Contact, { richMessage: RECEPCAO });

    expect(wrapper.text()).toBe(
      'Marina Lopes compartilhou um contatoRecepção da Unidade Centro+55 11 4000-0473'
    );
  });

  it('não oferece ação: o contato é nosso, não há o que salvar', () => {
    const wrapper = montarRica(Contact, { richMessage: RECEPCAO });

    expect(wrapper.find('a').exists()).toBe(false);
    expect(wrapper.find('button').exists()).toBe(false);
  });

  it('sem o nome de quem enviou, mostra só o contato', () => {
    const wrapper = montarRica(Contact, {
      richMessage: RECEPCAO,
      sender: null,
    });

    expect(wrapper.text()).toBe('Recepção da Unidade Centro+55 11 4000-0473');
  });

  it('não quebra quando nome e telefone não são texto', () => {
    const wrapper = montarRica(Contact, {
      richMessage: { type: 'contact', name: { a: 1 }, phone: 5511 },
    });

    expect(wrapper.text()).toBe('Marina Lopes compartilhou um contato');
  });

  it('trata nome e telefone como texto, nunca como HTML', () => {
    const wrapper = montarRica(Contact, {
      richMessage: { ...RECEPCAO, name: '<b>Recepção</b>' },
    });

    expect(wrapper.find('b').exists()).toBe(false);
    expect(wrapper.text()).toContain('<b>Recepção</b>');
  });

  it('aparece na conversa mesmo com a mensagem sem texto', () => {
    const wrapper = montarMensagem({
      content: '',
      contentAttributes: { richMessage: RECEPCAO },
    });

    expect(wrapper.find('[data-bubble-name="rich-contact"]').exists()).toBe(
      true
    );
    expect(wrapper.text()).toContain('+55 11 4000-0473');
  });
});
