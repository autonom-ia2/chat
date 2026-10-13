import { defineComponent, ref } from 'vue';
import { config, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import Flow from '../types/Flow.vue';
import ptBR from 'dashboard/i18n/locale/pt_BR/richMessage.json';
import { provideMessageContext } from '../../../provider.js';
import {
  MESSAGE_VARIANTS,
  MESSAGE_TYPES,
  MESSAGE_STATUS,
} from '../../../constants';
import { montarMensagem } from '../../../specs/montarMensagem.js';

// Troca o i18n vazio do setup global pelo catálogo de verdade desta entrega.
config.global.plugins = [
  createI18n({ legacy: false, locale: 'pt_BR', messages: { pt_BR: ptBR } }),
];

const AVISO_LEITOR =
  '(abre o formulário no WhatsApp do cliente, não no painel)';

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

// As linhas de texto puro (sem elementos dentro) que falam do formulário, com o texto exato.
const formLabelsOf = wrapper =>
  wrapper
    .findAll('div')
    .filter(
      node =>
        node.element.children.length === 0 &&
        node.text().startsWith('Formulário')
    )
    .map(node => node.text());

describe('bolha do formulário (Flow)', () => {
  it('mostra o corpo, o botão com o texto que o cliente vê e o nome do formulário', () => {
    const wrapper = mountFlow({
      flowId: '1234567890',
      cta: 'Iniciar',
      name: 'Login do corretor',
    });

    expect(wrapper.text()).toContain('Entre com seus dados.');
    expect(wrapper.text()).toContain('Iniciar');
    expect(wrapper.text()).toContain('Formulário: Login do corretor');
  });

  it('sem nome, diz só que é um formulário do WhatsApp', () => {
    const wrapper = mountFlow({ flowId: '1234567890', cta: 'Iniciar' });

    expect(wrapper.text()).toContain('Formulário do WhatsApp');
    expect(wrapper.text()).not.toContain('Formulário:');
  });

  it('a linha do formulário diz exatamente o nome, sem afirmar o envio', () => {
    expect(formLabelsOf(mountFlow({ cta: 'Iniciar', name: 'Login' }))).toEqual([
      'Formulário: Login',
    ]);
    expect(formLabelsOf(mountFlow({ cta: 'Iniciar' }))).toEqual([
      'Formulário do WhatsApp',
    ]);
  });

  it('sem texto do botão, não desenha a caixa do botão', () => {
    const wrapper = mountFlow({ name: 'Login' });

    expect(wrapper.find('.sr-only').exists()).toBe(false);
    expect(wrapper.find('.rounded-lg').exists()).toBe(false);
    expect(formLabelsOf(wrapper)).toEqual(['Formulário: Login']);
  });

  it('o botão não é link nem é focável: o atendente não abre o formulário pelo painel', () => {
    const wrapper = mountFlow({ cta: 'Iniciar', name: 'Login' });

    expect(wrapper.find('a').exists()).toBe(false);
    expect(wrapper.find('button').exists()).toBe(false);
    expect(wrapper.find('[href]').exists()).toBe(false);
    expect(wrapper.find('[tabindex]').exists()).toBe(false);
  });

  it('diz ao leitor de tela que o botão abre no WhatsApp do cliente, não no painel', () => {
    const wrapper = mountFlow({ cta: 'Iniciar', name: 'Login' });
    const hint = wrapper.get('.sr-only');

    expect(hint.text()).toBe(AVISO_LEITOR);
    expect(hint.element.parentElement.textContent).toContain('Iniciar');
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
    expect(wrapper.text()).toContain('Formulário do WhatsApp');
    expect(wrapper.text()).not.toContain('Formulário:');
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
    expect(wrapper.text()).toContain('Formulário: Login');
  });

  it('com a mensagem que falhou, a bolha mostra o formulário pelo nome e a conversa mostra o motivo da falha', () => {
    const wrapper = montarMensagem({
      messageType: MESSAGE_TYPES.OUTGOING,
      status: MESSAGE_STATUS.FAILED,
      content: 'Entre com seus dados.',
      contentAttributes: {
        richMessage: { type: 'flow', cta: 'Iniciar', name: 'Login' },
        externalError: 'Flow not published',
      },
    });
    const bubble = wrapper.get('[data-bubble-name="rich-flow"]');

    expect(formLabelsOf(bubble)).toEqual(['Formulário: Login']);
    expect(bubble.text()).not.toContain('Flow not published');
    expect(wrapper.text()).toContain('Flow not published');
  });
});
