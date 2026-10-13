import { config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import LocationRequest from '../types/LocationRequest.vue';
import ptBR from 'dashboard/i18n/locale/pt_BR/richMessage.json';
import { CAIXAS, montarRica } from './montarRica.js';
import { montarMensagem } from '../../../specs/montarMensagem.js';

config.global.plugins = [
  createI18n({ legacy: false, locale: 'pt_BR', messages: { pt_BR: ptBR } }),
];

const CORPO = 'Para achar a unidade mais perto, me envie onde você está.';
const PEDIDO = { type: 'location_request' };

describe('bolha do pedido de localização', () => {
  it('no WhatsApp oficial mostra o corpo, o botão "Enviar localização" e o aviso para o atendente', () => {
    const wrapper = montarRica(LocationRequest, {
      content: CORPO,
      richMessage: PEDIDO,
      inbox: CAIXAS.whatsappCloud,
    });

    expect(wrapper.text()).toContain(CORPO);
    expect(wrapper.text()).toContain('Enviar localização');
    expect(wrapper.text()).toContain('Pedimos ao cliente onde ele está');
  });

  it('diz ao leitor de tela que o botão aparece no WhatsApp do cliente', () => {
    const hint = montarRica(LocationRequest, {
      content: CORPO,
      richMessage: PEDIDO,
    }).get('.sr-only');

    expect(hint.text()).toBe('(botão que aparece no WhatsApp do cliente)');
  });

  it('no WhatsApp do 360dialog não desenha o botão: o cliente recebeu só o corpo', () => {
    const wrapper = montarRica(LocationRequest, {
      content: CORPO,
      richMessage: PEDIDO,
      inbox: CAIXAS.whatsapp360dialog,
    });

    expect(wrapper.text()).toBe(`${CORPO}\nPedimos ao cliente onde ele está`);
    expect(wrapper.text()).not.toContain('Enviar localização');
  });

  it('o botão é só a imagem do que o cliente vê: não é link nem botão clicável', () => {
    const wrapper = montarRica(LocationRequest, {
      content: CORPO,
      richMessage: PEDIDO,
    });

    expect(wrapper.find('a').exists()).toBe(false);
    expect(wrapper.find('button').exists()).toBe(false);
  });

  it('é a bolha que a conversa escolhe para o tipo location_request', () => {
    const wrapper = montarMensagem({
      content: CORPO,
      contentAttributes: { richMessage: PEDIDO },
    });

    expect(
      wrapper.find('[data-bubble-name="rich-location-request"]').exists()
    ).toBe(true);
  });
});
