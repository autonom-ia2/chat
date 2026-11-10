import {
  alvoDaLista,
  alvoDoRamo,
  fraseDoOutroRegistro,
  listaDoPasso,
  passosDaExecucao,
} from '../outroRegistro';
import { doAlvoDoGatilho, novoPasso } from '../catalogo';
import { fraseDoValor } from '../frases';
import { opcoesDosValores } from '../texto';
import { falta, galhosDe, inserirPasso } from '../receita';

// G18 (#2671) — o "em outro registro" na tela: em que registro o ramo roda (é
// ele que diz quais dados os passos de dentro usam), a frase e o "pronto".
const t = (chave, valores) =>
  valores ? `${chave}(${Object.values(valores).join(',')})` : chave;

const DO_CAMPO = {
  de: 'contato_do_campo',
  campo: { $valor: 'card.atributos.indicado_por' },
  usar: 'conversa',
};
const outro = (registro, passos = []) => ({
  id: 'p2',
  tipo: 'em_outro_registro',
  registro,
  passos,
});
const mensagem = id => ({ id, tipo: 'mensagem', texto: ['Oi'] });

describe('alvoDoRamo e alvoDaLista', () => {
  it('diz em que registro o ramo roda, como o servidor', () => {
    expect(alvoDoRamo(outro({ de: 'cards_do_contato' }))).toBe('Crm::Card');
    expect(alvoDoRamo(outro(DO_CAMPO))).toBe('Conversation');
    expect(alvoDoRamo(outro({ ...DO_CAMPO, usar: 'contato' }))).toBe('Contact');
  });

  it('a lista de fora é a do gatilho; a de dentro, mesmo dentro de um "se", a do registro', () => {
    const se = {
      id: 'p4',
      tipo: 'se',
      condicao: {},
      entao: [mensagem('p5')],
    };
    const passos = [
      mensagem('p1'),
      outro({ de: 'cards_do_contato' }, [mensagem('p3'), se]),
    ];

    expect(alvoDaLista(passos, 'raiz')).toBeNull();
    expect(listaDoPasso(passos, 'p3')).toBe('p2:passos');
    expect(alvoDaLista(passos, 'p2:passos')).toBe('Crm::Card');
    expect(listaDoPasso(passos, 'p5')).toBe('p4:entao');
    expect(alvoDaLista(passos, 'p4:entao')).toBe('Crm::Card');
  });
});

describe('a árvore do editor', () => {
  it('mostra os passos de dentro como um galho e insere dentro dele', () => {
    const passos = inserirPasso(
      [outro(DO_CAMPO)],
      'p2:passos',
      0,
      mensagem('p3')
    );

    expect(galhosDe(passos[0]).map(galho => galho.ramo)).toEqual(['passos']);
    expect(passos[0].passos).toEqual([mensagem('p3')]);
  });

  it('nasce sem ligação e sem passo dentro, e a receita só fica pronta com os dois', () => {
    const novo = novoPasso({ tipo: 'em_outro_registro' }, 'p2', t);
    const gatilho = { tipo: 'card.ganho' };

    expect(novo).toEqual(outro({}));
    expect(falta({ gatilho, passos: [novo] })).toBe('COMPLETAR');
    expect(falta({ gatilho, passos: [outro(DO_CAMPO)] })).toBe('COMPLETAR');
    expect(
      falta({
        gatilho,
        passos: [
          outro({ de: 'contato_do_campo', usar: 'conversa' }, [mensagem('p3')]),
        ],
      })
    ).toBe('COMPLETAR');
    expect(
      falta({ gatilho, passos: [outro(DO_CAMPO, [mensagem('p3')])] })
    ).toBeNull();
  });
});

describe('fraseDoOutroRegistro', () => {
  it('diz onde roda, com o campo e os filtros dos cards', () => {
    const O = 'AUTOMACAO_LIVRE.OUTRO_REGISTRO';

    expect(fraseDoOutroRegistro(outro(DO_CAMPO), t, 'Indicado por')).toBe(
      `${O}.FRASE.CONVERSA(Indicado por)`
    );
    expect(
      fraseDoOutroRegistro(
        outro({
          de: 'cards_do_contato',
          situacao: ['lost'],
          mais_recente: true,
          funil_id: 3,
        }),
        t
      )
    ).toBe(
      `${O}.FRASE.CARD_MAIS_RECENTE · ${O}.SITUACOES.LOST · ${O}.FRASE.NO_FUNIL`
    );
    expect(fraseDoOutroRegistro(outro({}), t)).toBe(`${O}.FRASE.SEM_LIGACAO`);
  });
});

describe('doAlvoDoGatilho dentro do ramo', () => {
  const CATALOGO = {
    gatilhos: [{ tipo: 'mensagem.criada', alvo: 'Conversation' }],
    alvos: {
      Conversation: ['conversa', 'contato'],
      'Crm::Card': ['card', 'conversa', 'contato', 'reuniao'],
    },
    valores: [
      { caminho: 'conversa.status', base: 'conversa' },
      { caminho: 'card.motivo_da_perda', base: 'card' },
      {
        caminho: 'reuniao.inicio',
        base: 'reuniao',
        so_nos_gatilhos: ['card.reuniao_marcada'],
      },
    ],
  };

  it('oferece os valores do registro do ramo, sem a reunião do gatilho', () => {
    const doRamo = doAlvoDoGatilho(
      CATALOGO,
      'mensagem.criada',
      false,
      false,
      'Crm::Card'
    );

    expect(doRamo.alvo).toBe('Crm::Card');
    expect(doRamo.valores.map(item => item.caminho)).toEqual([
      'conversa.status',
      'card.motivo_da_perda',
    ]);
    expect(
      doAlvoDoGatilho(CATALOGO, 'mensagem.criada').valores.map(
        item => item.caminho
      )
    ).toEqual(['conversa.status']);
  });
});

// G65 (#2842): dentro do ramo, os valores do registro de origem (o alvo do
// gatilho), com o prefixo e a marca no nome; fora dele, nada de origem.
describe('valores do registro de origem', () => {
  const CATALOGO = {
    gatilhos: [{ tipo: 'card.ganho', alvo: 'Crm::Card' }],
    alvos: {
      Contact: ['contato'],
      Conversation: ['conversa', 'contato'],
      'Crm::Card': ['card', 'conversa', 'contato', 'reuniao'],
    },
    valores: [
      {
        caminho: 'contato.nome',
        base: 'contato',
        frase: 'NOME',
        na_origem: true,
      },
      {
        caminho: 'card.valor',
        base: 'card',
        frase: 'VALOR',
        na_origem: true,
        sem_permissao: true,
      },
      { caminho: 'card.link_da_agenda', base: 'card', frase: 'AGENDA' },
      {
        caminho: 'card.atributos',
        base: 'card',
        frase: 'CAMPO_DO_CARD',
        atributos: 'card_attribute',
        na_origem: true,
      },
    ],
  };

  it('no ramo, oferece origem.* do alvo do gatilho, com a permissão do valor', () => {
    const doRamo = doAlvoDoGatilho(
      CATALOGO,
      'card.ganho',
      false,
      false,
      'Contact'
    );
    const opcoes = opcoesDosValores(
      doRamo,
      () => [{ attribute_key: 'pet', attribute_display_name: 'Pet' }],
      t
    );

    expect(opcoes).toEqual([
      { value: 'contato.nome', label: 'NOME' },
      {
        value: 'origem.contato.nome',
        label: 'AUTOMACAO_LIVRE.OUTRO_REGISTRO.DA_ORIGEM(NOME)',
      },
      {
        value: 'origem.card.atributos.pet',
        label:
          'AUTOMACAO_LIVRE.FRASES.ATRIBUTO(AUTOMACAO_LIVRE.OUTRO_REGISTRO.DA_ORIGEM(CAMPO_DO_CARD),Pet)',
      },
    ]);
    expect(fraseDoValor('origem.contato.nome', doRamo, t)).toBe(
      'AUTOMACAO_LIVRE.OUTRO_REGISTRO.DA_ORIGEM(NOME)'
    );
  });

  // Decisão 19: a origem que é conversa lê o card dela só para ler, e só com a
  // chave de funis, como fora do ramo.
  it('origem conversa: origem.card.* só com a chave de funis', () => {
    const daConversa = {
      ...CATALOGO,
      gatilhos: [{ tipo: 'mensagem.criada', alvo: 'Conversation' }],
      alvos: {
        ...CATALOGO.alvos,
        Conversation: ['conversa', 'contato', 'card'],
      },
    };
    const daOrigem = podeLerCard =>
      doAlvoDoGatilho(
        daConversa,
        'mensagem.criada',
        false,
        podeLerCard,
        'Crm::Card'
      )
        .valores.map(item => item.caminho)
        .filter(caminho => caminho.startsWith('origem.'));

    expect(daOrigem(true)).toEqual([
      'origem.contato.nome',
      'origem.card.valor',
      'origem.card.atributos',
    ]);
    expect(daOrigem(false)).toEqual(['origem.contato.nome']);
  });

  it('fora do ramo, nenhum valor de origem', () => {
    const caminhos = doAlvoDoGatilho(CATALOGO, 'card.ganho').valores.map(
      item => item.caminho
    );

    expect(caminhos.some(caminho => caminho.startsWith('origem.'))).toBe(false);
  });
});

// #2679 × G18: o texto da IA só passa entre passos da mesma execução.
describe('passosDaExecucao', () => {
  const escrever = id => ({ id, tipo: 'escrever', destino: 'guardar' });
  const se = (id, entao) => ({ id, tipo: 'se', entao });
  const receita = [
    escrever('p1'),
    outro(DO_CAMPO, [escrever('p3'), se('p4', [mensagem('p5')])]),
    mensagem('p6'),
  ];
  const ids = passos => passos.map(passo => passo.id);

  it('fora do ramo, a receita sem os passos de dentro dele', () => {
    expect(ids(passosDaExecucao(receita, 'raiz'))).toEqual(['p1', 'p2', 'p6']);
  });

  it('dentro do ramo, mesmo dentro de um "se", só os passos do ramo', () => {
    expect(ids(passosDaExecucao(receita, 'p4:entao'))).toEqual([
      'p3',
      'p4',
      'p5',
    ]);
    expect(ids(passosDaExecucao(receita, 'p2:passos'))).toEqual([
      'p3',
      'p4',
      'p5',
    ]);
  });
});
