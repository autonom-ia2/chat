import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import VueDOMPurifyHTML from 'vue-dompurify-html';
import { domPurifyConfig } from 'shared/helpers/HTMLSanitizer.js';
import en from 'dashboard/i18n/locale/en/conversaCanal.json';
import CitacaoDoWhatsapp from '../CitacaoDoWhatsapp.vue';
import { citacaoSolta } from '../citacaoSolta';
import { MESSAGE_TYPES } from '../../message/constants';

// #1702/#1709: a citação dentro do balão, com o v-dompurify-html de verdade (a
// mesma configuração do painel).
const montar = props =>
  mount(CitacaoDoWhatsapp, {
    props,
    attachTo: document.body,
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'en', messages: { en } }),
        [VueDOMPurifyHTML, domPurifyConfig],
      ],
    },
  });

const daCliente = {
  id: 9,
  messageType: MESSAGE_TYPES.INCOMING,
  sender: { name: 'Maria' },
};

describe('CitacaoDoWhatsapp', () => {
  afterEach(() => {
    delete window.citacaoExecutou;
  });

  it('link da prévia vira texto (nada focável dentro do botão)', () => {
    const wrapper = montar({
      mensagem: daCliente,
      previa: '<p>Veja <a href="https://exemplo.com.br">exemplo.com.br</a></p>',
    });
    expect(wrapper.find('a').exists()).toBe(false);
    expect(wrapper.text()).toContain('Veja exemplo.com.br');
    expect(wrapper.text()).toContain('Maria');
    wrapper.unmount();
  });

  it('<script> e atributo de evento na prévia não executam', () => {
    const wrapper = montar({
      mensagem: daCliente,
      previa:
        '<p>oi<script>window.citacaoExecutou = true</script><img src="x" onerror="window.citacaoExecutou = true"></p>',
    });
    expect(wrapper.find('script').exists()).toBe(false);
    expect(wrapper.find('img[onerror]').exists()).toBe(false);
    expect(window.citacaoExecutou).toBeUndefined();
    wrapper.unmount();
  });

  it('citação não conferida: sem nome, faixa cinza, aviso e sem toque', async () => {
    const solta = citacaoSolta({
      quotedMessage: {
        messageId: null,
        content: 'trecho do celular',
        fromMe: true,
        unverified: true,
      },
    });
    const wrapper = montar({ solta, nomeDoCliente: 'Maria' });
    expect(wrapper.text()).not.toContain('Maria');
    expect(wrapper.text()).not.toContain(en.CONVERSA_CANAL.CITACAO.VOCE);
    expect(wrapper.text()).toContain('trecho do celular');
    expect(wrapper.find('[data-citacao-nao-conferida]').exists()).toBe(true);
    expect(wrapper.classes()).toContain('border-s-[#8696A0]');
    expect(wrapper.attributes('role')).toBeUndefined();
    await wrapper.trigger('click');
    expect(wrapper.emitted('ir')).toBeUndefined();
    wrapper.unmount();
  });

  it('citação da conversa é um botão que leva à mensagem', async () => {
    const wrapper = montar({ mensagem: daCliente, previa: 'oi' });
    expect(wrapper.attributes('role')).toBe('button');
    await wrapper.trigger('keydown', { key: 'Enter' });
    expect(wrapper.emitted('ir')).toHaveLength(1);
    wrapper.unmount();
  });
});
