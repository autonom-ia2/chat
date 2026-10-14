import { config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/richMessage.json';
import { montarMensagem } from '../../../specs/montarMensagem.js';
import { MESSAGE_TYPES } from '../../../constants';

config.global.plugins = [
  createI18n({ legacy: false, locale: 'pt_BR', messages: { pt_BR: ptBR } }),
];

// A localização que o cliente manda chega com o anexo de sempre e, desde a #1512, com
// `content_attributes.shared_location` (aqui já em camelCase, como a lista de mensagens entrega).
const ANEXO = {
  id: 1,
  fileType: 'location',
  coordinatesLat: -23.5505,
  coordinatesLong: -46.6333,
  fallbackTitle: 'Praça da Sé, Praça da Sé, São Paulo - SP',
};

const montarRecebida = ({ sharedLocation, anexo = ANEXO } = {}) =>
  montarMensagem({
    messageType: MESSAGE_TYPES.INCOMING,
    content: null,
    sender: { id: 3, name: 'Carlos Souza', type: 'contact' },
    attachments: [anexo],
    contentAttributes: sharedLocation ? { sharedLocation } : {},
  });

const nomes = wrapper =>
  wrapper
    .findAll('[data-bubble-name]')
    .map(node => node.attributes('data-bubble-name'));

describe('bolha da localização recebida', () => {
  it('mostra quem mandou, o nome e o endereço, cada um na sua linha', () => {
    const wrapper = montarRecebida({
      sharedLocation: {
        latitude: -23.5505,
        longitude: -46.6333,
        name: 'Praça da Sé',
        address: 'Praça da Sé, São Paulo - SP',
      },
    });

    expect(nomes(wrapper)).toEqual(['received-location']);
    expect(wrapper.text()).toContain(
      'Carlos Souza compartilhou uma localização'
    );
    expect(wrapper.text()).toContain('Praça da Sé');
    expect(wrapper.text()).toContain('Praça da Sé, São Paulo - SP');
  });

  it('só com o endereço mostra o endereço (a bolha antiga ficava sem texto)', () => {
    const wrapper = montarRecebida({
      anexo: { ...ANEXO, fallbackTitle: '' },
      sharedLocation: {
        latitude: -23.5505,
        longitude: -46.6333,
        address: 'Rua Direita, 10 - Sé, São Paulo - SP',
      },
    });

    expect(wrapper.text()).toContain('Rua Direita, 10 - Sé, São Paulo - SP');
    expect(wrapper.get('a').attributes('href')).toBe(
      'https://maps.google.com/?q=-23.5505,-46.6333'
    );
  });

  it('abre o ponto no mapa em outra aba, com alvo de toque de 44 px', () => {
    const link = montarRecebida({
      sharedLocation: { latitude: -23.5505, longitude: -46.6333 },
    }).get('a');

    expect(link.attributes('href')).toBe(
      'https://maps.google.com/?q=-23.5505,-46.6333'
    );
    expect(link.attributes('target')).toBe('_blank');
    expect(link.attributes('rel')).toBe('noopener noreferrer');
    expect(link.classes()).toContain('min-h-11');
    expect(link.text()).toContain('Ver no mapa');
  });

  it('sem nome e sem endereço mostra quem mandou e o link do mapa', () => {
    const wrapper = montarRecebida({
      sharedLocation: { latitude: 1, longitude: 2 },
    });

    expect(wrapper.text()).toBe(
      'Carlos Souza compartilhou uma localizaçãoVer no mapa(abre em outra aba)'
    );
    expect(wrapper.get('a').attributes('href')).toBe(
      'https://maps.google.com/?q=1.0,2.0'
    );
  });

  // O mesmo formato da localização enviada (types/Location.vue) e da versão em texto (location.rb).
  it('monta o link em notação decimal, sem notação científica', () => {
    const link = montarRecebida({
      sharedLocation: { latitude: 1e-7, longitude: -1e-7 },
    }).get('a');

    expect(link.attributes('href')).toBe(
      'https://maps.google.com/?q=0.0000001,-0.0000001'
    );
  });

  it.each([
    ['latitude em texto', { latitude: '-23.5' }],
    ['latitude fora da faixa', { latitude: 91 }],
    ['longitude fora da faixa', { longitude: -181 }],
    ['longitude ausente', { longitude: undefined }],
    ['coordenada que não é número finito', { latitude: Infinity }],
  ])('não cria link de mapa com %s', (_titulo, mudanca) => {
    const wrapper = montarRecebida({
      sharedLocation: {
        latitude: -23.5505,
        longitude: -46.6333,
        name: 'Praça da Sé',
        ...mudanca,
      },
    });

    expect(wrapper.find('a').exists()).toBe(false);
    expect(wrapper.text()).toContain('Praça da Sé');
  });

  it('trata nome e endereço como texto, nunca como HTML', () => {
    const wrapper = montarRecebida({
      sharedLocation: {
        latitude: 1,
        longitude: 2,
        name: '<img src=x onerror=alert(1)>',
        address: '<script>alert(1)</script>',
      },
    });

    expect(wrapper.find('img').exists()).toBe(false);
    expect(wrapper.find('script').exists()).toBe(false);
    expect(wrapper.text()).toContain('<img src=x onerror=alert(1)>');
  });

  it('mensagem antiga, sem shared_location, continua na bolha de antes', () => {
    const wrapper = montarRecebida();

    expect(nomes(wrapper)).toEqual(['attachment']);
    expect(wrapper.text()).toContain(ANEXO.fallbackTitle);
    expect(wrapper.get('a').attributes('href')).toBe(
      'https://maps.google.com/?q=-23.5505,-46.6333'
    );
  });
});
