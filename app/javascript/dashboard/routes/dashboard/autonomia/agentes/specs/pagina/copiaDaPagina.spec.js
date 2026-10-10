import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import AgenteSemana from '../../components/pagina/AgenteSemana.vue';
import PaginaBlocos from '../../components/pagina/PaginaBlocos.vue';
import PaginaHeroi from '../../components/pagina/PaginaHeroi.vue';
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
  return { useMapGetter: () => computed(() => undefined) };
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
    expect(respondidas.text()).toContain(
      'Esta semana, Bia respondeu 1.234 conversas e passou 87 para a equipe.'
    );
    expect(passadas.text()).toContain('passadas para a equipe');
    expect(passadas.text()).toContain('Quando não soube responder.');
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
    expect(texto).toContain('Bia sabe o que você contou na conversa.');
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

  it('never says "Ligar" nor a confidence percentage', () => {
    const textos = JSON.stringify(ptBR.AGENTS.JORNADA.PAGINA);
    ['Ligar', 'Ligado', '%', 'confiança', 'certeza'].forEach(palavra =>
      expect(textos).not.toContain(palavra)
    );
  });
});
