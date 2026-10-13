import { config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import LocationRequest from '../types/LocationRequest.vue';
import ptBR from 'dashboard/i18n/locale/pt_BR/richMessage.json';
import { montarRica } from './montarRica.js';
import { montarMensagem } from '../../../specs/montarMensagem.js';

config.global.plugins = [
  createI18n({ legacy: false, locale: 'pt_BR', messages: { pt_BR: ptBR } }),
];

const CORPO = 'Para achar a unidade mais perto, me envie onde você está.';

describe('bolha do pedido de localização', () => {
  it('mostra o corpo, o botão "Enviar localização" e o aviso para o atendente', () => {
    const wrapper = montarRica(LocationRequest, {
      content: CORPO,
      richMessage: { type: 'location_request' },
    });

    expect(wrapper.text()).toBe(
      `${CORPO}\nEnviar localizaçãoPedimos ao cliente onde ele está`
    );
  });

  it('o botão é só a imagem do que o cliente vê: não é link nem botão clicável', () => {
    const wrapper = montarRica(LocationRequest, {
      content: CORPO,
      richMessage: { type: 'location_request' },
    });

    expect(wrapper.find('a').exists()).toBe(false);
    expect(wrapper.find('button').exists()).toBe(false);
  });

  it('é a bolha que a conversa escolhe para o tipo location_request', () => {
    const wrapper = montarMensagem({
      content: CORPO,
      contentAttributes: { richMessage: { type: 'location_request' } },
    });

    expect(
      wrapper.find('[data-bubble-name="rich-location-request"]').exists()
    ).toBe(true);
  });
});
