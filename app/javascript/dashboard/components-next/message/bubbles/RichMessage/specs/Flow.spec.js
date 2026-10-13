import { defineComponent, ref } from 'vue';
import { config, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import Flow from '../types/Flow.vue';
import ptBR from 'dashboard/i18n/locale/pt_BR/richMessage.json';
import { provideMessageContext } from '../../../provider.js';
import { MESSAGE_VARIANTS, MESSAGE_TYPES } from '../../../constants';
import { montarMensagem } from '../../../specs/montarMensagem.js';

// Troca o i18n vazio do setup global pelo catálogo de verdade desta entrega.
config.global.plugins = [
  createI18n({ legacy: false, locale: 'pt_BR', messages: { pt_BR: ptBR } }),
];

// Como a lista de mensagens entrega: chaves em camelCase em profundidade, inclusive dentro de `data`.
const DADOS_INICIAIS = {
  userSessionId: 'sessao-secreta-42',
  cotacao: { cep: '01001000', placa: 'ABC1D23' },
};

const mountFlow = ({ content = 'Entre com seus dados.', ...richMessage }) => {
  const TestHost = defineComponent({
    components: { Flow },
    setup() {
      provideMessageContext({
        content: ref(content),
        contentAttributes: ref({
          richMessage: { type: 'flow', ...richMessage },
        }),
        variant: ref(MESSAGE_VARIANTS.AGENT),
      });
    },
    template: '<Flow />',
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

describe('bolha do formulário (Flow)', () => {
  it('mostra o corpo, o botão com o texto que o cliente vê e o nome do formulário', () => {
    const wrapper = mountFlow({
      flowId: '1234567890',
      cta: 'Iniciar',
      name: 'Login do corretor',
    });

    expect(wrapper.text()).toContain('Entre com seus dados.');
    expect(wrapper.text()).toContain('Iniciar');
    expect(wrapper.text()).toContain('Formulário enviado: Login do corretor');
  });

  it('sem nome, diz só que um formulário foi enviado', () => {
    const wrapper = mountFlow({ flowId: '1234567890', cta: 'Iniciar' });

    expect(wrapper.text()).toContain('Formulário enviado');
    expect(wrapper.text()).not.toContain('Formulário enviado:');
  });

  it('o botão não é link: o atendente não abre o formulário pelo painel', () => {
    const wrapper = mountFlow({ cta: 'Iniciar', name: 'Login' });

    expect(wrapper.find('a').exists()).toBe(false);
    expect(wrapper.find('[href]').exists()).toBe(false);
  });

  it('mostra o cabeçalho e o rodapé quando vieram', () => {
    const wrapper = mountFlow({
      cta: 'Iniciar',
      header: 'Proposta GTA',
      footer: 'Leva um minuto.',
    });

    expect(wrapper.text()).toContain('Proposta GTA');
    expect(wrapper.text()).toContain('Leva um minuto.');
  });

  it('nunca mostra os dados iniciais nem o token', () => {
    const wrapper = mountFlow({
      cta: 'Iniciar',
      name: 'Login',
      token: 'sessao-1739999999-123456',
      screen: 'LOGIN',
      data: DADOS_INICIAIS,
    });

    expect(wrapper.text()).not.toContain('sessao-secreta-42');
    expect(wrapper.text()).not.toContain('01001000');
    expect(wrapper.text()).not.toContain('ABC1D23');
    expect(wrapper.text()).not.toContain('sessao-1739999999-123456');
    expect(wrapper.html()).not.toContain('01001000');
  });

  it('trata texto do botão, nome e cabeçalho como texto, nunca como HTML', () => {
    const wrapper = mountFlow({
      cta: '<img src=x onerror=alert(1)>',
      name: '<b>Login</b>',
      header: '<script>alert(1)</script>',
    });

    expect(wrapper.find('img').exists()).toBe(false);
    expect(wrapper.find('b').exists()).toBe(false);
    expect(wrapper.find('script').exists()).toBe(false);
    expect(wrapper.text()).toContain('<img src=x onerror=alert(1)>');
  });

  it('não quebra quando os campos não são texto', () => {
    const wrapper = mountFlow({ cta: { a: 1 }, name: 42, header: ['x'] });

    expect(wrapper.text()).toContain('Entre com seus dados.');
    expect(wrapper.text()).toContain('Formulário enviado');
    expect(wrapper.text()).not.toContain('Formulário enviado:');
  });

  it('a conversa escolhe esta bolha para mensagem de saída com rich_message do tipo flow', () => {
    const wrapper = montarMensagem({
      messageType: MESSAGE_TYPES.OUTGOING,
      content: 'Entre com seus dados.',
      contentAttributes: {
        richMessage: { type: 'flow', cta: 'Iniciar', name: 'Login' },
      },
    });

    expect(wrapper.find('[data-bubble-name="rich-flow"]').exists()).toBe(true);
    expect(wrapper.text()).toContain('Formulário enviado: Login');
  });
});
