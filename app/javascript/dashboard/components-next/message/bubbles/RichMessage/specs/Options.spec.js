import { nextTick } from 'vue';
import { config, mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/richMessage.json';
import Message from '../../../Message.vue';
import {
  AGORA,
  montagem,
  montarMensagem,
} from '../../../specs/montarMensagem.js';
import { MESSAGE_STATUS, MESSAGE_TYPES } from '../../../constants';

// A mesma rota mínima do `montarMensagem` (Message.vue lê `route.query`).
vi.mock('vue-router', () => ({ useRoute: () => ({ query: {}, params: {} }) }));

// Troca o i18n vazio do setup global pelo catálogo de verdade desta entrega.
config.global.plugins = [
  createI18n({ legacy: false, locale: 'pt_BR', messages: { pt_BR: ptBR } }),
];

const ID_ENVIADA = 41;
const ESPELHO =
  'Cópia do que o cliente recebeu. Só o cliente pode tocar nestas opções.';

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

const propsDaMensagem = (status, content, richMessage) => ({
  id: ID_ENVIADA,
  messageType: MESSAGE_TYPES.OUTGOING,
  status,
  content,
  conversationId: 7,
  createdAt: AGORA,
  currentUserId: 1,
  sender: { id: 1, name: 'Marina', type: 'User' },
  contentAttributes: { richMessage: { type: 'options', ...richMessage } },
});

// A mensagem inteira (Message.vue), como a conversa do painel monta: a mesma loja mínima do `montarMensagem`,
// com a conversa aberta trazendo as mensagens dadas, no estado reativo da loja (como chegam pelo websocket).
const montar = ({
  conversa = [],
  status = MESSAGE_STATUS.SENT,
  content = 'Como você prefere continuar?',
  ...richMessage
}) => {
  const base = montagem.plugins[0].getters;
  const getters = Object.fromEntries(
    Object.keys(base).map(name => [name, () => base[name]])
  );
  const store = createStore({
    state: () => ({ messages: [...conversa] }),
    getters: {
      ...getters,
      getSelectedChat: state => ({ id: 7, messages: state.messages }),
    },
  });

  return mount(Message, {
    props: propsDaMensagem(status, content, richMessage),
    global: { ...montagem, plugins: [store] },
  });
};

const bolha = wrapper => wrapper.get('[data-bubble-name="rich-options"]');
const botoes = wrapper => bolha(wrapper).findAll('[data-option-button]');
const linhas = wrapper => bolha(wrapper).findAll('li[data-option-row]');

describe('bolha das opções', () => {
  it('é a bolha que a mensagem escolhe para o tipo options', () => {
    const wrapper = montarMensagem({
      id: ID_ENVIADA,
      content: 'Como você prefere continuar?',
      contentAttributes: { richMessage: { type: 'options', options: TRES } },
    });

    expect(bolha(wrapper).exists()).toBe(true);
    expect(botoes(wrapper)).toHaveLength(3);
  });

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
    expect(bolha(wrapper).text()).toContain('Próximo passo');
    expect(bolha(wrapper).text()).toContain('Como você prefere continuar?');
    expect(bolha(wrapper).text()).toContain('Toque em uma opção.');
    expect(linhas(wrapper)).toHaveLength(0);
  });

  it('diz ao leitor de tela que é cópia e não deixa nada da bolha focável', () => {
    const wrapper = montar({ sections: SECOES, button: 'Ver assuntos' });

    expect(bolha(wrapper).get('.sr-only').text()).toBe(ESPELHO);
    expect(bolha(wrapper).findAll('a, button, input, [tabindex]')).toHaveLength(
      0
    );
  });

  it('não afirma nada sobre a escolha quando não acha a resposta', () => {
    const wrapper = montar({ options: TRES });

    expect(bolha(wrapper).text()).not.toContain('O cliente tocou');
    expect(bolha(wrapper).text()).not.toContain('ainda não');
    expect(bolha(wrapper).find('.i-lucide-check').exists()).toBe(false);
  });

  it('marca o botão tocado e diz qual foi, pela resposta do cliente', () => {
    const wrapper = montar({
      options: TRES,
      conversa: [resposta({ id: 'agendar', title: 'Agendar visita' })],
    });

    expect(bolha(wrapper).text()).toContain(
      'O cliente tocou em "Agendar visita"'
    );
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

    expect(bolha(wrapper).text()).toContain(
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

    expect(bolha(wrapper).text()).not.toContain('O cliente tocou');
  });

  it('mostra a lista sempre aberta, com o botão enviado, seções e descrições', () => {
    const wrapper = montar({ sections: SECOES, button: 'Ver assuntos' });

    expect(bolha(wrapper).text()).toContain('Ver assuntos');
    expect(linhas(wrapper).map(linha => linha.text())).toEqual([
      'Remarcar horárioTrocar o dia ou a hora',
      'Cancelar horário',
      'Segunda via',
    ]);
    expect(botoes(wrapper)).toHaveLength(0);
  });

  it('faz de cada seção um grupo com o nome dela', () => {
    const wrapper = montar({ sections: SECOES, button: 'Ver assuntos' });
    const grupos = bolha(wrapper).findAll('[role="group"]');

    expect(grupos.map(grupo => grupo.attributes('aria-label'))).toEqual([
      'Atendimento',
      'Pagamento',
    ]);
    expect(grupos[1].findAll('li')).toHaveLength(1);
  });

  it('vira lista com mais de três opções e mostra só o botão que foi enviado', () => {
    const wrapper = montar({
      options: [...TRES, { id: 'sair', title: 'Encerrar' }],
      button: 'Escolher',
    });

    expect(linhas(wrapper)).toHaveLength(4);
    expect(bolha(wrapper).text()).toContain('Escolher');
    expect(bolha(wrapper).text()).not.toContain('Ver opções');
  });

  it('mostra a seção única sem título com o título que saiu: o texto do botão', () => {
    const wrapper = montar({
      sections: [{ options: [...TRES, { id: 'sair', title: 'Encerrar' }] }],
      button: 'Escolher',
    });
    const grupos = bolha(wrapper).findAll('[role="group"]');

    expect(grupos.map(grupo => grupo.attributes('aria-label'))).toEqual([
      'Escolher',
    ]);
    expect(grupos[0].findAll('li')).toHaveLength(4);
  });

  it('mostra a escolha quando a resposta chega depois, pela loja', async () => {
    const wrapper = montar({ options: TRES });
    expect(bolha(wrapper).text()).not.toContain('O cliente tocou');

    wrapper.vm.$store.state.messages.push(
      resposta({ id: 'horarios', title: 'Ver horários' })
    );
    await nextTick();

    expect(bolha(wrapper).text()).toContain(
      'O cliente tocou em "Ver horários"'
    );
    expect(botoes(wrapper)[1].find('.i-lucide-check').exists()).toBe(true);
  });

  it('usa o título oferecido quando a resposta traz só o id', () => {
    const wrapper = montar({
      options: TRES,
      conversa: [resposta({ id: 'pessoa' })],
    });

    expect(bolha(wrapper).text()).toContain(
      'O cliente tocou em "Falar com uma pessoa"'
    );
  });

  it('não mostra a linha quando a resposta traz só um id que não foi oferecido', () => {
    const wrapper = montar({
      options: TRES,
      conversa: [resposta({ id: 'outra-coisa' })],
    });

    expect(bolha(wrapper).text()).not.toContain('O cliente tocou');
  });

  it('vira lista quando alguma opção tem descrição', () => {
    const wrapper = montar({
      options: [{ id: 'a', title: 'Centro', description: 'Rua das Flores' }],
      button: 'Unidades',
    });

    expect(linhas(wrapper)).toHaveLength(1);
    expect(botoes(wrapper)).toHaveLength(0);
  });

  it('marca a linha escolhida da lista', () => {
    const wrapper = montar({
      sections: SECOES,
      button: 'Ver assuntos',
      conversa: [resposta({ id: 'remarcar', title: 'Remarcar horário' })],
    });

    expect(bolha(wrapper).text()).toContain(
      'O cliente tocou em "Remarcar horário"'
    );
    expect(linhas(wrapper)[0].find('.i-lucide-check').exists()).toBe(true);
    expect(linhas(wrapper)[1].find('.i-lucide-check').exists()).toBe(false);
  });

  it('trata títulos como texto e não quebra com entrada estranha', () => {
    const wrapper = montar({
      options: [{ id: 'x', title: '<img src=x onerror=alert(1)>' }, 'Sim', 7],
      header: { type: 'image' },
    });

    expect(bolha(wrapper).find('img').exists()).toBe(false);
    expect(bolha(wrapper).text()).toContain('<img src=x onerror=alert(1)>');
    expect(bolha(wrapper).text()).toContain('Como você prefere continuar?');
  });
});
