import { ref } from 'vue';
import { mount } from '@vue/test-utils';
import LivrePassos from '../components/LivrePassos.vue';
import LivreIaTestar from '../components/LivreIaTestar.vue';
import {
  A_CADA,
  galhosDe,
  idDaLista,
  inserirPasso,
  noGalhoACada,
  todosOsPassos,
} from '../receita';
import { custoPorMensagem } from '../custoDaIa';
import { linhasDoEnsaio } from '../ensaio';

// G63 (#2830) — o galho "A cada mensagem do cliente enquanto espera" do
// "Esperar até": entra na travessia única, mostra que volta a esperar no fim,
// avisa o custo da IA por mensagem e aparece no ensaio com a volta.
const t = (chave, valores) =>
  valores ? `${chave} ${JSON.stringify(valores)}` : chave;

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t, locale: { value: 'pt_BR' } }),
}));
vi.mock('dashboard/api/autonomia/automacoes', () => ({
  default: { testarPasso: vi.fn() },
}));
vi.mock('dashboard/composables/useCanManage', () => ({
  useCanManage: () => ref(false),
}));

const CATALOGO = {
  gatilhos: [],
  operadores: [],
  unidades: [],
  valores: [],
  passos: [],
};

const RESUMIR = { id: 'r1', tipo: 'resumir', destino: 'nota' };
const ESPERA = {
  id: 'p1',
  tipo: 'esperar_ate',
  prazo: 'sem_prazo',
  conferir_as: 8,
  [A_CADA]: [
    {
      id: 'p2',
      tipo: 'esperar_ate',
      prazo: { valor: 2, unidade: 'horas' },
      se_vencer: [RESUMIR],
    },
  ],
};
const RECEITA = {
  gatilho: { tipo: 'card.responsavel_mudou' },
  passos: [ESPERA, { id: 'r2', tipo: 'resumir', destino: 'nota' }],
};

describe('o galho a cada mensagem na receita', () => {
  it('é um galho do "esperar até", também sem prazo', () => {
    expect(galhosDe(ESPERA).map(galho => galho.ramo)).toEqual([A_CADA]);
  });

  it('a travessia anda por dentro dele e insere passos nele', () => {
    expect(todosOsPassos(RECEITA.passos).map(passo => passo.id)).toEqual([
      'p1',
      'p2',
      'r1',
      'r2',
    ]);
    const novo = inserirPasso(RECEITA.passos, idDaLista('p1', A_CADA), 1, {
      id: 'p9',
      tipo: 'parar',
    });
    expect(novo[0][A_CADA].map(passo => passo.id)).toEqual(['p2', 'p9']);
    expect(RECEITA.passos[0][A_CADA]).toHaveLength(1);
  });

  it('sabe quais passos rodam a cada mensagem, em qualquer nível', () => {
    expect(noGalhoACada(RECEITA.passos, 'r1')).toBe(true);
    expect(noGalhoACada(RECEITA.passos, 'r2')).toBe(false);
  });
});

describe('o custo da IA no galho', () => {
  it('o passo de IA dentro do galho custa por mensagem; fora, não', () => {
    expect(custoPorMensagem(RECEITA, 'r1')).toBe(true);
    expect(custoPorMensagem(RECEITA, 'r2')).toBe(false);
    expect(custoPorMensagem(null, 'r1')).toBe(false);
  });

  it('o painel da IA avisa, para todos, que cada mensagem é uma ida paga', () => {
    const montar = porMensagem =>
      mount(LivreIaTestar, {
        props: { passo: RESUMIR, receita: RECEITA, porMensagem },
        global: { mocks: { $t: t } },
      });

    expect(montar(true).find('[data-ia-por-mensagem]').text()).toBe(
      'AUTOMACAO_LIVRE.IA.CUSTO.POR_MENSAGEM'
    );
    expect(montar(false).find('[data-ia-por-mensagem]').exists()).toBe(false);
  });
});

describe('o galho no Confira', () => {
  const montar = passos =>
    mount(LivrePassos, {
      props: { passos, listaId: 'raiz', catalogo: CATALOGO, podeMudar: true },
      global: { mocks: { $t: chave => chave }, stubs: { Button: true } },
    });

  it('mostra o galho pelo nome e, no fim dele, que volta a esperar', () => {
    const wrapper = montar([ESPERA]);

    const rotulos = wrapper.findAll('[data-galho]').map(galho => galho.text());
    expect(rotulos[0]).toContain('AUTOMACAO_LIVRE.RAMOS.A_CADA_MENSAGEM');
    expect(wrapper.find('[data-galho-volta]').text()).toBe(
      'AUTOMACAO_LIVRE.CONFIRA.VOLTA_A_ESPERAR'
    );
  });

  it('o galho vazio não diz que volta: não há o que rodar', () => {
    const wrapper = montar([{ ...ESPERA, [A_CADA]: [] }]);

    expect(wrapper.find('[data-galho-volta]').exists()).toBe(false);
  });
});

describe('o galho no ensaio', () => {
  it('rotula o caminho e termina com a volta à espera', () => {
    const nos = [
      {
        id: 'p1',
        tipo: 'esperar_ate',
        faria: 'esperar_ate',
        ramos: [
          { chave: 'chegou', passos: [] },
          {
            chave: A_CADA,
            volta: 'p1',
            passos: [{ id: 'p2', tipo: 'esperar_ate', faria: 'esperar_ate' }],
          },
        ],
      },
    ];

    const textos = linhasDoEnsaio(nos, id => `frase ${id}`, t).map(
      linha => linha.texto
    );

    expect(textos).toEqual([
      'frase p1',
      'AUTOMACAO_LIVRE.ENSAIO.SE_CHEGAR',
      'AUTOMACAO_LIVRE.ENSAIO.A_CADA_MENSAGEM',
      'frase p2',
      'AUTOMACAO_LIVRE.ENSAIO.VOLTA {"passo":"frase p1"}',
    ]);
  });
});
