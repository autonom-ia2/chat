import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import AgenteSemana from '../../components/pagina/AgenteSemana.vue';
import PaginaBlocos from '../../components/pagina/PaginaBlocos.vue';
import PaginaHeroi from '../../components/pagina/PaginaHeroi.vue';
import GavetaFotoNome from '../../components/pagina/GavetaFotoNome.vue';
import { ESTADO } from '../../utils/estadoDoAgente';
import en from '../../../../../../i18n/locale/en/agents.json';
import ptBR from '../../../../../../i18n/locale/pt_BR/agents.json';

// Cópia real em pt_BR (protótipo jornada.html, T07): frases exatas, {nome} neutro e o vocabulário
// Atendendo/Parado, nunca "Ligar".
withFullI18n('pt_BR');

vi.mock('vue-router', () => ({
  useRouter: () => ({ resolve: rota => ({ href: `/app/${rota.name}` }) }),
}));
// Sem a agenda nova na conta (#1253): a linha Marca reuniões fica fora, como na conta comum.
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return {
    useMapGetter: () => computed(() => undefined),
    useStore: () => ({ dispatch: vi.fn() }),
  };
});
vi.mock('../../composables/usePermissoesDaJornada', async () => {
  const { computed } = await import('vue');
  return {
    usePermissoesDaJornada: () => ({
      podeConectarCanal: computed(() => true),
      podeEscolherQuemRecebe: computed(() => true),
      crmLigado: computed(() => true),
    }),
  };
});

const AGENTE = { id: 7, name: 'Bia', mode: 'guided' };

describe('cópia da página do agente em pt_BR', () => {
  it('writes the week cards like the prototype', () => {
    const wrapper = mount(AgenteSemana, {
      props: { nome: 'Bia', numeros: { respondidas: 1234, passadas: 87 } },
    });
    const [respondidas, passadas] = wrapper.findAll('[data-numero]');
    expect(respondidas.text()).toContain('1.234');
    expect(respondidas.text()).toContain('conversas respondidas');
    // #2000 (revisão de produto) — a nota não repete o período nem o número do cartão ao lado.
    expect(respondidas.text()).toContain(
      'Conversas em que Bia mandou ao menos uma resposta.'
    );
    // #2000 — a maioria das passagens é por horário ou a pedido do cliente.
    expect(passadas.text()).toContain('passadas para alguém da equipe');
    expect(passadas.text()).toContain(
      'Por horário, a pedido do cliente ou porque não soube.'
    );
    expect(passadas.text()).not.toContain('Quando não soube responder');
  });

  it('says "esta semana" in so many words and shows the solved ones (#2000)', () => {
    const wrapper = mount(AgenteSemana, {
      props: {
        nome: 'Bia',
        numeros: { respondidas: 3, passadas: 1, resolvidas: 2 },
      },
    });
    expect(wrapper.get('[data-periodo]').text()).toBe(
      'Esta semana (os últimos 7 dias, contando hoje)'
    );
    expect(wrapper.get('[data-no-mes]').text()).toBe(
      'Em Números › Equipe você vê esses números do mês.'
    );
    const resolvidas = wrapper.get('[data-numero="resolvidas"]');
    expect(resolvidas.text()).toContain('resolvidas sem a equipe');
    expect(resolvidas.text()).toContain(
      'Terminaram sem ninguém da equipe precisar entrar.'
    );
  });

  it('says each card opens the conversations, only for whoever can open them', () => {
    const montar = podeAbrir =>
      mount(AgenteSemana, {
        props: { nome: 'Bia', numeros: { respondidas: 3 }, podeAbrir },
      });
    expect(montar(true).findAll('[data-ver]')).toHaveLength(3);
    expect(montar(true).get('[data-ver]').text()).toBe('Ver as conversas');
    expect(montar(false).find('[data-ver]').exists()).toBe(false);
  });

  it('uses the singular for one conversation (#1369)', () => {
    const wrapper = mount(AgenteSemana, {
      props: { nome: 'Bia', numeros: { respondidas: 1, passadas: 1 } },
    });
    const [respondidas, passadas] = wrapper.findAll('[data-numero]');
    expect(respondidas.text()).toContain('conversa respondida');
    expect(respondidas.text()).not.toContain('conversas');
    expect(passadas.text()).toContain('passada para alguém da equipe');
    expect(passadas.text()).not.toContain('passadas');
  });

  it('writes the blocks with the Assignment sentence', () => {
    const wrapper = mount(PaginaBlocos, {
      props: {
        agente: AGENTE,
        nome: 'Bia',
        podeGerenciar: true,
        temCanal: true,
        textoOnde: 'No WhatsApp do Centro, sempre.',
        quantasFontes: 2,
        quantasPerguntas: 1,
      },
    });
    const texto = wrapper.text();
    expect(texto).toContain('Pergunte como se fosse seu cliente.');
    // #1369 — com arquivos e sites, a frase não diz que sabe só a conversa.
    expect(texto).toContain(
      'Bia sabe o que você contou na conversa e o que está nos arquivos e sites.'
    );
    expect(texto).toContain('2 arquivos e sites');
    expect(texto).toContain('Há 1 pergunta de cliente para conferir.');
    expect(texto).toContain('No WhatsApp do Centro, sempre.');
    expect(texto).toContain(
      'Chama-se Bia. Para ouvir como fala, faça um teste.'
    );
    expect(texto).toContain(
      'Quando não souber, Bia passa a conversa para a equipe. Quem recebe é definido em Atribuição.'
    );
    expect(texto).toContain('Escolher quem recebe');
    expect(texto).toContain(
      'Para mudar quando Bia passa, use Mudar conversando.'
    );
  });

  it('keeps the knowledge sentence in step with the files count (#1369)', () => {
    const montarBlocos = (quantasFontes, agente = AGENTE) =>
      mount(PaginaBlocos, {
        props: {
          agente,
          nome: 'Bia',
          temCanal: true,
          textoOnde: '',
          quantasFontes,
        },
      }).text();

    const semFontes = montarBlocos(0);
    expect(semFontes).toContain('Bia sabe o que você contou na conversa.');
    expect(semFontes).toContain('Só o que você contou na conversa');

    const umaFonte = montarBlocos(1);
    expect(umaFonte).toContain(
      'Bia sabe o que você contou na conversa e o que está no arquivo ou site.'
    );
    expect(umaFonte).toContain('1 arquivo ou site');

    // O resumo da IA, quando já existe, continua valendo.
    expect(
      montarBlocos(1, { ...AGENTE, knowledge_summary: 'Sabe os preços.' })
    ).toContain('Sabe os preços.');
  });

  it('writes the hero with the state words', () => {
    const wrapper = mount(PaginaHeroi, {
      props: {
        nome: 'Bia',
        estado: ESTADO.PARADO,
        onde: 'No WhatsApp do Centro · sempre',
        hrefLista: '/app/agentes',
        podeGerenciar: true,
        acaoPrincipal: 'mudar',
        itensMais: [{ chave: 'foto', texto: 'Foto e nome' }],
      },
    });
    const texto = wrapper.text();
    expect(texto).toContain('Voltar para Agentes');
    expect(texto).toContain('Parado');
    expect(texto).toContain('Mudar conversando');
    expect(texto).toContain('Mais opções');
    expect(texto).not.toContain('Ligar');
    expect(wrapper.get('[role="switch"]').attributes('aria-label')).toBe(
      'Bia atendendo os clientes'
    );
  });

  describe('gaveta Nome / Foto e nome', () => {
    const montarGaveta = props =>
      mount(GavetaFotoNome, {
        attachTo: document.body,
        props: { agente: { ...AGENTE, actuation: 'external' }, ...props },
      });

    afterEach(() => {
      document.body.innerHTML = '';
    });

    it('says the customer sees the channel photo, in short sentences', () => {
      const wrapper = montarGaveta({
        canal: { nome: 'WhatsApp do Centro', foto: 'https://x/whats.png' },
        temCanal: true,
      });
      const texto = document.body.textContent;
      expect(texto).toContain('Nome');
      expect(texto).not.toContain('Foto e nome');
      expect(texto).not.toContain('Trocar foto');
      expect(texto).toContain(
        'Seus clientes veem a foto do canal WhatsApp do Centro.'
      );
      expect(texto).toContain(
        'O nome aparece aqui no painel. Se você pedir outro nome em Mudar conversando, ele muda e a gente avisa.'
      );
      wrapper.unmount();
    });

    it('says how to add a photo when the channel has none', () => {
      const wrapper = montarGaveta({
        canal: { nome: 'WhatsApp do Centro', foto: '' },
        temCanal: true,
      });
      expect(document.body.textContent).toContain(
        'O canal WhatsApp do Centro ainda não tem foto. Para seus clientes verem uma foto aqui, coloque-a nas configurações da caixa de entrada.'
      );
      wrapper.unmount();
    });

    it('makes "Mudar conversando" a link inside the same sentence', () => {
      const wrapper = montarGaveta({ podeMudar: true });
      expect(document.querySelector('[data-ir-mudar]').textContent).toBe(
        'Mudar conversando'
      );
      expect(document.querySelector('[data-nota]').textContent).toContain(
        'Se você pedir outro nome em Mudar conversando, ele muda e a gente avisa.'
      );
      wrapper.unmount();
    });

    // Piloto conta 16: sobrava espaço entre o link e a vírgula. A causa era o padding horizontal que
    // o `button` ganha do _base.scss (px-2.5); o link zera o padding e cresce a área de toque pelo
    // ::after, sem empurrar a linha.
    it('glues "Mudar conversando" to the comma, with no side padding', () => {
      const wrapper = montarGaveta({ podeMudar: true });
      const link = document.querySelector('[data-ir-mudar]');
      const nota = document.querySelector('[data-nota]').textContent;
      expect(nota).toContain('Mudar conversando,');
      expect(nota).not.toContain('Mudar conversando ,');
      expect(link.classList).toContain('p-0');
      expect(link.classList).toContain('after:-inset-y-3');
      expect([...link.classList].some(c => c.startsWith('px-'))).toBe(false);
      expect([...link.classList].some(c => c.startsWith('py-'))).toBe(false);
      wrapper.unmount();
    });

    it('says what happens before the first channel, neutral with {nome}', () => {
      const wrapper = montarGaveta();
      expect(document.body.textContent).toContain(
        'Quando Bia atender num canal, a foto será a desse canal.'
      );
      wrapper.unmount();
    });

    it('keeps "Foto e nome" and "Trocar foto" for the internal agent', () => {
      const wrapper = montarGaveta({
        agente: { ...AGENTE, actuation: 'internal' },
      });
      const texto = document.body.textContent;
      expect(texto).toContain('Foto e nome');
      expect(texto).toContain('Trocar foto');
      expect(texto).not.toContain('clientes veem');
      wrapper.unmount();
    });
  });
});

describe('catálogo da página', () => {
  const chaves = (objeto, prefixo = '') =>
    Object.entries(objeto).flatMap(([chave, valor]) =>
      typeof valor === 'object'
        ? chaves(valor, `${prefixo}${chave}.`)
        : [`${prefixo}${chave}`]
    );

  it('has the same keys in en and pt_BR', () => {
    expect(chaves(en.AGENTS.JORNADA.PAGINA).sort()).toEqual(
      chaves(ptBR.AGENTS.JORNADA.PAGINA).sort()
    );
  });

  // "Ligar" é proibido para o agente (DECISOES item 9). Ferramenta não é agente: "Ligada/Desligada" e
  // "Ligar ferramenta" foram aprovados pelo Rodrigo em 11/10/2026 (#1301), só em FERRAMENTAS.
  it('never says "Ligar" nor a confidence percentage', () => {
    const { FERRAMENTAS, ...doAgente } = ptBR.AGENTS.JORNADA.PAGINA;
    const textos = JSON.stringify(doAgente);
    ['Ligar', 'Ligado', '%', 'confiança', 'certeza'].forEach(palavra =>
      expect(textos).not.toContain(palavra)
    );
    // Nas ferramentas, "para ter certeza" (protótipo F09) é sobre testar, não nota de confiança.
    ['%', 'confiança'].forEach(palavra =>
      expect(JSON.stringify(FERRAMENTAS)).not.toContain(palavra)
    );
  });
});
