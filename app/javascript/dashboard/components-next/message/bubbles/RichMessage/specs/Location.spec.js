import { config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import Location from '../types/Location.vue';
import ptBR from 'dashboard/i18n/locale/pt_BR/richMessage.json';
import { montarRica } from './montarRica.js';
import { montarMensagem } from '../../../specs/montarMensagem.js';

config.global.plugins = [
  createI18n({ legacy: false, locale: 'pt_BR', messages: { pt_BR: ptBR } }),
];

const UNIDADE = {
  type: 'location',
  latitude: -23.5489,
  longitude: -46.6388,
  name: 'Unidade Centro',
  address: 'Rua das Flores, 123, sala 45 - Centro, São Paulo - SP, 01000-000',
};

describe('bolha da localização enviada', () => {
  it('mostra quem enviou, o nome e o endereço por extenso, sem carregar mapa', () => {
    const wrapper = montarRica(Location, { richMessage: UNIDADE });

    expect(wrapper.text()).toContain(
      'Marina Lopes compartilhou uma localização'
    );
    expect(wrapper.text()).toContain('Unidade Centro');
    expect(wrapper.text()).toContain(UNIDADE.address);
    expect(wrapper.find('img').exists()).toBe(false);
    expect(wrapper.find('iframe').exists()).toBe(false);
  });

  it('deixa o endereço longo quebrar linha em vez de cortar', () => {
    const wrapper = montarRica(Location, { richMessage: UNIDADE });
    const address = wrapper
      .findAll('div')
      .find(node => node.text() === UNIDADE.address);

    expect(address.classes()).toContain('break-words');
    expect(address.classes()).not.toContain('truncate');
  });

  it('o atendente abre o ponto no mapa em outra aba, com alvo de toque de 44 px', () => {
    const link = montarRica(Location, { richMessage: UNIDADE }).get('a');

    expect(link.attributes('href')).toBe(
      'https://maps.google.com/?q=-23.5489,-46.6388'
    );
    expect(link.attributes('target')).toBe('_blank');
    expect(link.attributes('rel')).toBe('noopener noreferrer');
    expect(link.classes()).toContain('min-h-11');
    expect(link.text()).toContain('Ver no mapa');
  });

  it.each([
    ['latitude em texto', { latitude: '-23.5' }],
    ['latitude fora da faixa', { latitude: 91 }],
    ['longitude fora da faixa', { longitude: -181 }],
    ['longitude ausente', { longitude: undefined }],
    ['coordenada que não é número finito', { latitude: Infinity }],
  ])('não cria link de mapa com %s', (_titulo, mudanca) => {
    const wrapper = montarRica(Location, {
      richMessage: { ...UNIDADE, ...mudanca },
    });

    expect(wrapper.find('a').exists()).toBe(false);
    expect(wrapper.text()).toContain('Unidade Centro');
  });

  it('trata nome e endereço como texto, nunca como HTML', () => {
    const wrapper = montarRica(Location, {
      richMessage: {
        ...UNIDADE,
        name: '<img src=x onerror=alert(1)>',
        address: '<script>alert(1)</script>',
      },
    });

    expect(wrapper.find('img').exists()).toBe(false);
    expect(wrapper.find('script').exists()).toBe(false);
    expect(wrapper.text()).toContain('<img src=x onerror=alert(1)>');
  });

  it('sem nome e endereço mostra só quem enviou e o link do mapa', () => {
    const wrapper = montarRica(Location, {
      richMessage: { type: 'location', latitude: 1, longitude: 2 },
    });

    expect(wrapper.text()).toBe(
      'Marina Lopes compartilhou uma localizaçãoVer no mapa(abre em outra aba)'
    );
  });

  it('aparece na conversa mesmo com a mensagem sem texto', () => {
    const wrapper = montarMensagem({
      content: null,
      contentAttributes: { richMessage: UNIDADE },
    });

    expect(wrapper.find('[data-bubble-name="rich-location"]').exists()).toBe(
      true
    );
    expect(wrapper.text()).toContain('Unidade Centro');
  });
});
