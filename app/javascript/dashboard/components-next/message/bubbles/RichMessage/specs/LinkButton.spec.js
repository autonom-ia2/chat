import { defineComponent, ref } from 'vue';
import { config, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import LinkButton from '../types/LinkButton.vue';
import ptBR from 'dashboard/i18n/locale/pt_BR/richMessage.json';
import { provideMessageContext } from '../../../provider.js';
import { MESSAGE_VARIANTS } from '../../../constants';

const URL_LONGA = `https://exemplo.com.br/agendar/${'unidade-centro-'.repeat(20)}?origem=whatsapp&campanha=volta@aulas|2026`;

// Troca o i18n vazio do setup global pelo catálogo de verdade desta entrega.
config.global.plugins = [
  createI18n({ legacy: false, locale: 'pt_BR', messages: { pt_BR: ptBR } }),
];

const mountLinkButton = ({
  content = 'Escolha pelo site.',
  ...richMessage
}) => {
  const TestHost = defineComponent({
    components: { LinkButton },
    setup() {
      provideMessageContext({
        content: ref(content),
        contentAttributes: ref({
          richMessage: { type: 'link_button', ...richMessage },
        }),
        variant: ref(MESSAGE_VARIANTS.AGENT),
      });
    },
    template: '<LinkButton />',
  });

  return mount(TestHost, {
    global: {
      directives: {
        dompurifyHtml: (el, { value }) => {
          el.innerHTML = value;
        },
      },
      stubs: { BaseBubble: { template: '<div><slot /></div>' } },
    },
  });
};

describe('bolha do botão de link', () => {
  it('mostra o corpo, o botão com o rótulo e o endereço inteiro', () => {
    const wrapper = mountLinkButton({
      label: 'Escolher horário',
      url: 'https://exemplo.com.br/agendar?origem=whatsapp',
    });

    expect(wrapper.text()).toContain('Escolha pelo site.');
    expect(wrapper.get('a').text()).toContain('Escolher horário');
    expect(wrapper.text()).toContain(
      'Abre: https://exemplo.com.br/agendar?origem=whatsapp'
    );
  });

  it('diz ao leitor de tela que abre em outra aba e liga o endereço ao link', () => {
    const wrapper = mountLinkButton({
      label: 'Escolher horário',
      url: 'https://exemplo.com.br/agendar',
    });
    const link = wrapper.get('a');
    const hint = link.get('.sr-only');
    const address = wrapper.get(`#${link.attributes('aria-describedby')}`);

    expect(hint.text()).toBe('(abre em outra aba)');
    expect(address.text()).toBe('Abre: https://exemplo.com.br/agendar');
  });

  it('usa como link o endereço interpretado, nunca um caminho relativo ao painel', () => {
    const wrapper = mountLinkButton({
      label: 'Abrir',
      url: 'https:exemplo.com.br/agendar',
    });

    expect(wrapper.get('a').attributes('href')).toBe(
      'https://exemplo.com.br/agendar'
    );
    expect(wrapper.text()).toContain('Abre: https:exemplo.com.br/agendar');
  });

  it('abre o endereço em outra aba, sem dar a página de origem ao destino', () => {
    const link = mountLinkButton({
      label: 'Abrir',
      url: 'http://exemplo.com.br',
    }).get('a');

    expect(link.attributes('href')).toBe('http://exemplo.com.br/');
    expect(link.attributes('target')).toBe('_blank');
    expect(link.attributes('rel')).toBe('noopener noreferrer');
  });

  it('mostra o cabeçalho e o rodapé quando vieram', () => {
    const wrapper = mountLinkButton({
      label: 'Abrir',
      url: 'https://exemplo.com.br',
      header: 'Agendamento',
      footer: 'Leva um minuto.',
    });

    expect(wrapper.text()).toContain('Agendamento');
    expect(wrapper.text()).toContain('Leva um minuto.');
  });

  it('sem cabeçalho e rodapé mostra só corpo, botão e endereço', () => {
    const wrapper = mountLinkButton({
      label: 'Abrir',
      url: 'https://exemplo.com.br',
    });

    expect(wrapper.text()).toBe(
      'Escolha pelo site.\nAbrir(abre em outra aba)Abre: https://exemplo.com.br'
    );
  });

  it('escreve o endereço longo inteiro e deixa quebrar linha', () => {
    const wrapper = mountLinkButton({ label: 'Abrir', url: URL_LONGA });
    const address = wrapper
      .findAll('div')
      .find(node => node.text() === `Abre: ${URL_LONGA}`);

    expect(address.classes()).toContain('break-all');
    expect(address.classes()).not.toContain('truncate');
    expect(wrapper.get('a').attributes('href')).toBe(URL_LONGA);
  });

  it.each([
    // eslint-disable-next-line no-script-url
    'javascript:alert(1)',
    'data:text/html,<script>alert(1)</script>',
    'ftp://exemplo.com.br/arquivo',
    'exemplo.com.br/agendar',
    '',
  ])('não cria link para endereço que não é http ou https: %s', url => {
    const wrapper = mountLinkButton({ label: 'Abrir', url });

    expect(wrapper.find('a').exists()).toBe(false);
    expect(wrapper.text()).toContain('Abrir');
    expect(wrapper.text()).toContain(`Abre: ${url}`.trim());
  });

  it('trata rótulo e endereço como texto, nunca como HTML', () => {
    const wrapper = mountLinkButton({
      label: '<img src=x onerror=alert(1)>',
      url: 'https://exemplo.com.br/?q=<b>oi</b>',
      header: '<script>alert(1)</script>',
    });

    expect(wrapper.find('img').exists()).toBe(false);
    expect(wrapper.find('b').exists()).toBe(false);
    expect(wrapper.find('script').exists()).toBe(false);
    expect(wrapper.text()).toContain('<img src=x onerror=alert(1)>');
  });

  it('não quebra quando rótulo e endereço não são texto', () => {
    const wrapper = mountLinkButton({ label: { a: 1 }, url: 42 });

    expect(wrapper.find('a').exists()).toBe(false);
    expect(wrapper.text()).toContain('Escolha pelo site.');
  });
});
