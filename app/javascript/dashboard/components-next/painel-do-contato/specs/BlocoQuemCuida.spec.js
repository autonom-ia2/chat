import { reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { useAlert } from 'dashboard/composables';
import BlocoQuemCuida from '../BlocoQuemCuida.vue';
import { criarI18n, criarStore } from './apoio';

vi.mock('dashboard/composables', async importOriginal => ({
  ...(await importOriginal()),
  useAlert: vi.fn(),
}));

// #2138 — "Quem cuida": quatro estados, com e sem a Fase 2, para quem opera e
// para quem só lê; a linha de time e prioridade só com valor.
const EU = { id: 7, name: 'Bia' };
const ANA = { id: 3, name: 'Ana' };
const SOFIA = { id: 50, name: 'Sofia' };

const conversaCom = (assignee, extra = {}) => ({
  id: 42,
  inbox_id: 1,
  priority: null,
  ...extra,
  meta: {
    assignee: assignee?.pessoa ?? null,
    assignee_type: assignee?.tipo ?? null,
    team: null,
    ...(extra.meta || {}),
  },
});

const ESTADOS = {
  minha: {
    conversa: conversaCom({ pessoa: EU, tipo: 'User' }),
    frase: 'Está com você.',
    acao: 'Trocar',
  },
  colega: {
    conversa: conversaCom({ pessoa: ANA, tipo: 'User' }),
    frase: 'Está com Ana.',
    acao: 'Trocar',
  },
  ia: {
    conversa: conversaCom({ pessoa: SOFIA, tipo: 'AgentBot' }),
    frase: 'Está com a IA Sofia.',
    acao: 'Trocar',
  },
  ninguem: {
    conversa: conversaCom(null),
    frase: 'Ninguém está cuidando desta conversa.',
    acao: 'Escolher quem cuida',
  },
};

const montar = ({ conversation, podeOperar, fase2, estado = {} }) => {
  const apoio = criarStore({
    eu: EU,
    conversaSelecionada: conversation,
    ...estado,
  });
  const wrapper = mount(BlocoQuemCuida, {
    props: { conversation, podeOperar, fase2 },
    global: { plugins: [apoio.store, criarI18n()] },
    attachTo: document.body,
  });
  return { wrapper, ...apoio };
};

// O jsdom não rola; no navegador o ChoiceSelect rola até a opção ativa.
beforeAll(() => {
  Element.prototype.scrollIntoView = vi.fn();
});

const botoes = wrapper => wrapper.findAll('button').map(b => b.text());

describe('BlocoQuemCuida — os 4 estados', () => {
  Object.entries(ESTADOS).forEach(([nome, caso]) => {
    describe(nome, () => {
      it('sem a Fase 2, quem opera lê a frase e tem uma ação só', () => {
        const { wrapper } = montar({
          conversation: caso.conversa,
          podeOperar: true,
          fase2: false,
        });
        expect(wrapper.get('[data-test-id="quem-cuida"]').text()).toBe(
          caso.frase
        );
        expect(botoes(wrapper)).toEqual([caso.acao]);
        wrapper.unmount();
      });

      it('sem a Fase 2, quem só lê vê a frase, sem botão', () => {
        const { wrapper } = montar({
          conversation: caso.conversa,
          podeOperar: false,
          fase2: false,
        });
        expect(wrapper.get('[data-test-id="quem-cuida"]').text()).toBe(
          caso.frase
        );
        expect(botoes(wrapper)).toEqual([]);
        wrapper.unmount();
      });

      it('com a Fase 2, não há botão (quem passa é o "Passar para…" do topo)', () => {
        [true, false].forEach(podeOperar => {
          const { wrapper } = montar({
            conversation: caso.conversa,
            podeOperar,
            fase2: true,
          });
          const esperado =
            nome === 'ninguem' && podeOperar
              ? 'Ninguém está cuidando desta conversa. Ao responder, ela fica com você.'
              : caso.frase;
          expect(wrapper.get('[data-test-id="quem-cuida"]').text()).toBe(
            esperado
          );
          expect(botoes(wrapper)).toEqual([]);
          wrapper.unmount();
        });
      });
    });
  });
});

describe('BlocoQuemCuida — time e prioridade', () => {
  const frases = wrapper => wrapper.findAll('p').map(p => p.text());

  it('sem time e sem prioridade, não há segunda linha', () => {
    const { wrapper } = montar({
      conversation: ESTADOS.colega.conversa,
      podeOperar: false,
      fase2: false,
    });
    expect(frases(wrapper)).toEqual(['Está com Ana.']);
    wrapper.unmount();
  });

  it('com time e prioridade, uma frase só', () => {
    const conversa = conversaCom(
      { pessoa: ANA, tipo: 'User' },
      { priority: 'high', meta: { team: { id: 1, name: 'Suporte' } } }
    );
    const { wrapper } = montar({ conversation: conversa, podeOperar: false });
    expect(frases(wrapper)).toEqual([
      'Está com Ana.',
      'Está no time Suporte, com prioridade alta.',
    ]);
    wrapper.unmount();
  });

  it('só time, ou só prioridade', () => {
    const soTime = montar({
      conversation: conversaCom(null, {
        meta: { team: { id: 1, name: 'Suporte' } },
      }),
    });
    expect(frases(soTime.wrapper)[1]).toBe('Está no time Suporte.');
    soTime.wrapper.unmount();

    const soPrioridade = montar({
      conversation: conversaCom(null, { priority: 'urgent' }),
    });
    expect(frases(soPrioridade.wrapper)[1]).toBe('Prioridade urgente.');
    soPrioridade.wrapper.unmount();
  });
});

describe('BlocoQuemCuida — escolher quem cuida', () => {
  const agentes = [
    {
      id: 3,
      name: 'Ana',
      assignee_type: 'User',
      availability_status: 'online',
    },
    {
      id: 50,
      name: 'Sofia',
      assignee_type: 'AgentBot',
      availability_status: 'online',
    },
  ];

  it('abre a lista pela API do ChoiceSelect, sem clique simulado no botão dela', async () => {
    const { wrapper } = montar({
      conversation: ESTADOS.ninguem.conversa,
      podeOperar: true,
      fase2: false,
      estado: { agentes },
    });
    await wrapper.get('button').trigger('click');
    await flushPromises();

    const caixa = wrapper.get('[role="combobox"]');
    expect(caixa.attributes('aria-expanded')).toBe('true');
    expect(caixa.attributes('aria-label')).toBe('Quem cuida desta conversa');
    const opcoes = wrapper.findAll('[role="option"]').map(o => o.text());
    expect(opcoes).toEqual(['Ninguém', 'Ana', 'Sofia']);
    wrapper.unmount();
  });

  it('a saída de foco do botão que some ao abrir não fecha a lista; sair dela fecha', async () => {
    const { wrapper } = montar({
      conversation: ESTADOS.ninguem.conversa,
      podeOperar: true,
      fase2: false,
      estado: { agentes },
    });
    const caixa = wrapper.get('button').element.parentElement;
    await wrapper.get('button').trigger('click');
    await flushPromises();

    // O Chrome avisa a saída de foco do botão removido; ela chega à caixa.
    caixa.dispatchEvent(
      new FocusEvent('focusout', { bubbles: true, relatedTarget: null })
    );
    await flushPromises();
    expect(wrapper.find('[role="combobox"]').exists()).toBe(true);

    wrapper
      .get('[role="combobox"]')
      .element.dispatchEvent(
        new FocusEvent('focusout', { bubbles: true, relatedTarget: null })
      );
    await flushPromises();
    expect(wrapper.find('[role="combobox"]').exists()).toBe(false);
    expect(botoes(wrapper)).toEqual(['Escolher quem cuida']);
    wrapper.unmount();
  });

  // salva: a action grava (a conversa guardada muda) ou falha calada, como hoje.
  const escolherAna = async ({ salva }) => {
    const conversa = reactive(conversaCom(null));
    const apoio = montar({
      conversation: conversa,
      podeOperar: true,
      fase2: false,
      estado: {
        agentes,
        respostas: {
          assignAgent: ({ agentId, assigneeType }) => {
            if (!salva) return;
            conversa.meta.assignee = { id: agentId, name: 'Ana' };
            conversa.meta.assignee_type = assigneeType;
          },
        },
      },
    });
    await apoio.wrapper.get('button').trigger('click');
    await flushPromises();
    await apoio.wrapper.findAll('[role="option"]')[1].trigger('click');
    await flushPromises();
    return apoio;
  };

  beforeEach(() => vi.clearAllMocks());

  it('escolher chama assignAgent e diz com quem ficou', async () => {
    const { wrapper, acoes } = await escolherAna({ salva: true });
    expect(acoes).toContainEqual([
      'assignAgent',
      { conversationId: 42, agentId: 3, assigneeType: 'User' },
    ]);
    expect(useAlert).toHaveBeenCalledWith('Agora está com Ana.');
    expect(wrapper.get('[data-test-id="quem-cuida"]').text()).toBe(
      'Está com Ana.'
    );
    wrapper.unmount();
  });

  it('a action não devolve erro: se a conversa não mudou, avisa que não deu', async () => {
    const { wrapper } = await escolherAna({ salva: false });
    expect(useAlert).toHaveBeenCalledWith(
      'Não deu para trocar agora. Tente de novo.'
    );
    expect(useAlert).not.toHaveBeenCalledWith('Agora está com Ana.');
    wrapper.unmount();
  });
});
