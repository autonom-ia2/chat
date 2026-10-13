import { defineComponent, ref } from 'vue';
import { config, mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import Options from '../types/Options.vue';
import ptBR from 'dashboard/i18n/locale/pt_BR/richMessage.json';
import { provideMessageContext } from '../../../provider.js';
import {
  MESSAGE_STATUS,
  MESSAGE_TYPES,
  MESSAGE_VARIANTS,
} from '../../../constants';

// Troca o i18n vazio do setup global pelo catálogo de verdade desta entrega.
config.global.plugins = [
  createI18n({ legacy: false, locale: 'pt_BR', messages: { pt_BR: ptBR } }),
];

const ID_ENVIADA = 41;

const TRES = [
  { id: 'agendar', title: 'Agendar visita' },
  { id: 'horarios', title: 'Ver horários' },
  { id: 'pessoa', title: 'Falar com uma pessoa' },
];

const SECOES = [
  {
    title: 'Atendimento',
    options: [
      {
        id: 'remarcar',
        title: 'Remarcar horário',
        description: 'Trocar o dia ou a hora',
      },
      { id: 'cancelar', title: 'Cancelar horário' },
    ],
  },
  { title: 'Pagamento', options: [{ id: 'boleto', title: 'Segunda via' }] },
];

// A resposta do cliente como a loja guarda (chaves da API, em snake_case).
const resposta = (selected, extra = {}) => ({
  id: 50,
  message_type: MESSAGE_TYPES.INCOMING,
  content: selected.title,
  content_attributes: { in_reply_to: ID_ENVIADA, selected_option: selected },
  ...extra,
});

const montar = ({
  conversa = [],
  status = MESSAGE_STATUS.SENT,
  content = 'Como você prefere continuar?',
  ...richMessage
}) => {
  const store = createStore({
    getters: { getSelectedChat: () => ({ id: 7, messages: conversa }) },
  });
  const TestHost = defineComponent({
    components: { Options },
    setup() {
      provideMessageContext({
        id: ref(ID_ENVIADA),
        status: ref(status),
        content: ref(content),
        contentAttributes: ref({
          richMessage: { type: 'options', ...richMessage },
        }),
        variant: ref(MESSAGE_VARIANTS.AGENT),
      });
    },
    template: '<Options />',
  });

  return mount(TestHost, {
    global: {
      plugins: [store],
      directives: {
        dompurifyHtml: (el, { value }) => {
          el.innerHTML = value;
        },
      },
      stubs: { BaseBubble: { template: '<div><slot /></div>' } },
    },
  });
};

const botoes = wrapper => wrapper.findAll('[data-option-button]');
const linhas = wrapper => wrapper.findAll('li[data-option-row]');

describe('bolha das opções', () => {
  it('mostra até três opções como botões, com corpo, cabeçalho e rodapé', () => {
    const wrapper = montar({
      options: TRES,
      header: 'Próximo passo',
      footer: 'Toque em uma opção.',
    });

    expect(botoes(wrapper).map(botao => botao.text())).toEqual([
      'Agendar visita',
      'Ver horários',
      'Falar com uma pessoa',
    ]);
    expect(wrapper.text()).toContain('Próximo passo');
    expect(wrapper.text()).toContain('Como você prefere continuar?');
    expect(wrapper.text()).toContain('Toque em uma opção.');
    expect(linhas(wrapper)).toHaveLength(0);
  });

  it('diz que o cliente ainda não escolheu enquanto não há resposta', () => {
    const wrapper = montar({ options: TRES });

    expect(wrapper.text()).toContain('O cliente ainda não escolheu');
    expect(wrapper.find('.i-lucide-check').exists()).toBe(false);
  });

  it('marca o botão tocado e diz qual foi, pela resposta do cliente', () => {
    const wrapper = montar({
      options: TRES,
      conversa: [resposta({ id: 'agendar', title: 'Agendar visita' })],
    });

    expect(wrapper.text()).toContain('O cliente tocou em "Agendar visita"');
    expect(botoes(wrapper)[0].find('.i-lucide-check').exists()).toBe(true);
    expect(botoes(wrapper)[1].find('.i-lucide-check').exists()).toBe(false);
  });

  it('usa a resposta mais recente quando o cliente tocou mais de uma vez', () => {
    const wrapper = montar({
      options: TRES,
      conversa: [
        resposta({ id: 'agendar', title: 'Agendar visita' }),
        resposta({ id: 'pessoa', title: 'Falar com uma pessoa' }, { id: 51 }),
      ],
    });

    expect(wrapper.text()).toContain(
      'O cliente tocou em "Falar com uma pessoa"'
    );
  });

  it('ignora resposta a outra mensagem, mensagem de saída e resposta sem opção', () => {
    const wrapper = montar({
      options: TRES,
      conversa: [
        resposta(
          { id: 'agendar', title: 'Agendar visita' },
          {
            content_attributes: {
              in_reply_to: 99,
              selected_option: { id: 'agendar', title: 'Agendar visita' },
            },
          }
        ),
        resposta(
          { id: 'agendar', title: 'Agendar visita' },
          { message_type: MESSAGE_TYPES.OUTGOING }
        ),
        {
          id: 52,
          message_type: MESSAGE_TYPES.INCOMING,
          content: 'Quero agendar',
          content_attributes: { in_reply_to: ID_ENVIADA },
        },
      ],
    });

    expect(wrapper.text()).toContain('O cliente ainda não escolheu');
  });

  it('mostra a lista sempre aberta, com seções, descrições e o texto do botão', () => {
    const wrapper = montar({ sections: SECOES, button: 'Ver assuntos' });

    expect(wrapper.text()).toContain('Ver assuntos');
    expect(wrapper.text()).toContain('Atendimento');
    expect(wrapper.text()).toContain('Pagamento');
    expect(linhas(wrapper).map(linha => linha.text())).toEqual([
      'Remarcar horárioTrocar o dia ou a hora',
      'Cancelar horário',
      'Segunda via',
    ]);
    expect(botoes(wrapper)).toHaveLength(0);
  });

  it('vira lista com mais de três opções, com o botão padrão', () => {
    const wrapper = montar({
      options: [...TRES, { id: 'sair', title: 'Encerrar' }],
    });

    expect(linhas(wrapper)).toHaveLength(4);
    expect(wrapper.text()).toContain('Ver opções');
  });

  it('vira lista quando alguma opção tem descrição', () => {
    const wrapper = montar({
      options: [{ id: 'a', title: 'Centro', description: 'Rua das Flores' }],
    });

    expect(linhas(wrapper)).toHaveLength(1);
    expect(botoes(wrapper)).toHaveLength(0);
  });

  it('marca a linha escolhida da lista', () => {
    const wrapper = montar({
      sections: SECOES,
      conversa: [resposta({ id: 'remarcar', title: 'Remarcar horário' })],
    });

    expect(wrapper.text()).toContain('O cliente tocou em "Remarcar horário"');
    expect(linhas(wrapper)[0].find('.i-lucide-check').exists()).toBe(true);
    expect(linhas(wrapper)[1].find('.i-lucide-check').exists()).toBe(false);
  });

  it('não diz nada sobre a escolha quando a mensagem falhou', () => {
    const wrapper = montar({ options: TRES, status: MESSAGE_STATUS.FAILED });

    expect(wrapper.text()).not.toContain('O cliente');
  });

  it('trata títulos como texto e não quebra com entrada estranha', () => {
    const wrapper = montar({
      options: [{ id: 'x', title: '<img src=x onerror=alert(1)>' }, 'Sim', 7],
      header: { type: 'image' },
      sections: undefined,
    });

    expect(wrapper.find('img').exists()).toBe(false);
    expect(wrapper.text()).toContain('<img src=x onerror=alert(1)>');
    expect(wrapper.text()).toContain('Como você prefere continuar?');
  });
});
