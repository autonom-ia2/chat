import { defineComponent, ref } from 'vue';
import { config, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/richMessage.json';
import Poll from '../types/Poll.vue';
import { pollVotedTitles } from '../pollAnswer.js';
import { provideMessageContext } from '../../../provider.js';
import { MESSAGE_VARIANTS } from '../../../constants';

config.global.plugins = [
  createI18n({ legacy: false, locale: 'pt_BR', messages: { pt_BR: ptBR } }),
];

const ENQUETE = {
  type: 'poll',
  options: [
    { id: 'sim', title: 'Sim' },
    { id: 'nao', title: 'Não' },
  ],
};

// O voto como a lista de mensagens entrega (camelCase), agregado na própria enquete (#1702).
const voto = (options, senderId = 5) => ({
  senderType: 'Contact',
  senderId,
  options,
  at: '2026-10-16T10:00:00Z',
});

const montar = (pollVotes, richMessage = ENQUETE) => {
  const Host = defineComponent({
    components: { Poll },
    setup() {
      provideMessageContext({
        id: ref(70),
        content: ref('Vem amanhã?'),
        contentAttributes: ref({ richMessage, pollVotes }),
        variant: ref(MESSAGE_VARIANTS.AGENT),
      });
    },
    template: '<Poll />',
  });
  return mount(Host, {
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

describe('bolha da enquete', () => {
  it('mostra a pergunta e as opções, sem voto', () => {
    const wrapper = montar(undefined);

    expect(wrapper.text()).toContain('Vem amanhã?');
    expect(wrapper.findAll('[data-poll-option]').map(li => li.text())).toEqual([
      'Sim',
      'Não',
    ]);
    expect(wrapper.text()).toContain('Enquete: uma resposta');
    expect(wrapper.find('[data-poll-vote]').exists()).toBe(false);
  });

  it('mostra o voto gravado na enquete (o novo já substituiu o anterior)', () => {
    expect(
      montar([voto(['Não'])])
        .find('[data-poll-vote]')
        .text()
    ).toBe('Votou: Não');
  });

  it('volta a "Sem voto" quando o cliente retira o voto', () => {
    expect(
      montar([voto([])])
        .find('[data-poll-vote]')
        .text()
    ).toBe('Sem voto');
  });

  it('lista todas as marcadas na enquete de várias respostas', () => {
    const wrapper = montar([voto(['Sim', 'Não'])], {
      ...ENQUETE,
      multiple: true,
    });

    expect(wrapper.text()).toContain('Enquete: uma ou mais respostas');
    expect(wrapper.find('[data-poll-vote]').text()).toBe('Votou: Sim, Não');
  });
});

describe('pollVotedTitles', () => {
  it('junta os títulos dos eleitores sem repetir e ignora o que não é texto', () => {
    expect(pollVotedTitles(null)).toBeNull();
    expect(pollVotedTitles([])).toBeNull();
    expect(
      pollVotedTitles([voto(['Sim', 7]), voto(['Sim', 'Não'], 6)])
    ).toEqual(['Sim', 'Não']);
  });
});
