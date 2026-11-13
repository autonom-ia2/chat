import {
  detalheDoHistorico,
  linhaDoEnsaioReal,
  resumoDaPesquisa,
} from '../frasesDosNovos';
import { RAMOS_QUE_SALVAM, emTeste } from '../passosNovos';
import { linhasDoEnsaio } from '../../ensaio';

// #2931, #2935 e #2936 — o que a tela diz da aprovação, da reunião e da
// pesquisa de verdade: a linha do ensaio que vem da API, a linha do histórico
// e o resumo da pesquisa na lista.
const t = (chave, valores, n) =>
  `${chave}${valores ? `(${Object.values(valores).join(',')})` : ''}${n === undefined ? '' : `#${n}`}`;
const hora = iso => `hora:${iso}`;
const P = 'AUTOMACAO_LIVRE.PASSOS_NOVOS';

describe('os passos que salvam', () => {
  it('nenhum dos seis segue em teste; os galhos dos três que esperam são conhecidos', () => {
    expect(emTeste({ tipo: 'pedir_aprovacao' })).toBe(false);
    expect(emTeste({ tipo: 'usar_bloco' })).toBe(false);
    expect(emTeste({ tipo: 'parar' })).toBe(false);
    expect(RAMOS_QUE_SALVAM).toEqual([
      'aprovado',
      'recusado',
      'ninguem_respondeu',
      'outro_horario',
      'nao_respondeu',
      'nota_baixa',
      'nota_media',
      'nota_alta',
    ]);
  });
});

describe('linha do ensaio de verdade', () => {
  it('a aprovação diz a quem o pedido iria', () => {
    const no = { faria: 'pedir_aprovacao', dados: { para: ['Ana'] } };

    expect(linhaDoEnsaioReal(no, t).destaque).toBe(
      `${P}.APROVACAO.ENSAIO_PARA(Ana)`
    );
  });

  it('a reunião numera os horários sem botão e mostra o modelo da janela fechada', () => {
    const no = {
      faria: 'marcar_reuniao',
      dados: {
        convite: 'Posso ligar?',
        horarios: ['Qui 13/11 10:00', 'Qui 13/11 15:00'],
        botoes: false,
        modelo: 'retomar_contato',
      },
    };

    const linha = linhaDoEnsaioReal(no, t);

    expect(linha.balao).toBe(
      'Posso ligar?\n1. Qui 13/11 10:00\n2. Qui 13/11 15:00'
    );
    expect(linha.aviso).toBe(
      'AUTOMACAO_LIVRE.ENSAIO.MODELO_FORA_DA_JANELA(retomar_contato)'
    );
  });

  it('com botões, os horários vão sem número', () => {
    const no = {
      faria: 'marcar_reuniao',
      dados: { convite: 'Oi', horarios: ['Seg 10:00'], botoes: true },
    };

    expect(linhaDoEnsaioReal(no, t).balao).toBe('Oi\nSeg 10:00');
  });

  it('os porquês de pular viram aviso; o que não é deles fica para a linha de sempre', () => {
    ['sem_quem_aprove', 'sem_horario', 'pesquisa_recente'].forEach(faria => {
      expect(linhaDoEnsaioReal({ faria }, t).aviso).toBeTruthy();
    });
    expect(linhaDoEnsaioReal({ faria: 'pararia', dados: {} }, t)).toBeNull();
  });

  it('entra nas linhas do ensaio com o galho fixo pelo nome', () => {
    const nos = [
      {
        id: 'p1',
        tipo: 'pesquisa_nota',
        faria: 'pesquisa_nota',
        dados: { pergunta: 'Nota?', espera: { valor: 2, unidade: 'dias' } },
        ramos: [{ chave: 'nota_alta', fixo: true, passos: [] }],
      },
    ];

    const linhas = linhasDoEnsaio(nos, () => 'frase', t);

    expect(linhas[0].balao).toBe('Nota?');
    expect(linhas[1].texto).toBe(
      `${P}.CAMINHO_NO_ENSAIO(AUTOMACAO_LIVRE.RAMOS.NOTA_ALTA)`
    );
  });
});

describe('linha do histórico de verdade', () => {
  it('quem recusou e o motivo', () => {
    expect(
      detalheDoHistorico(
        { ramo: 'recusado', por_nome: 'Ana', motivo_da_recusa: 'Caro' },
        t,
        hora
      )
    ).toEqual([
      `${P}.APROVACAO.HISTORICO_RECUSOU(Ana)`,
      `${P}.APROVACAO.HISTORICO_MOTIVO_DITO(Caro)`,
    ]);
  });

  it('o horário marcado e a nota, com o comentário quando veio', () => {
    expect(
      detalheDoHistorico({ horario: '2026-11-13T13:00:00Z' }, t, hora)
    ).toEqual([`${P}.REUNIAO.HISTORICO(hora:2026-11-13T13:00:00Z)`]);
    expect(detalheDoHistorico({ nota: 0 }, t, hora)).toEqual([
      `${P}.PESQUISA.HISTORICO_NOTA(0)`,
    ]);
    expect(
      detalheDoHistorico({ nota: 9, comentario: 'Gostei' }, t, hora)
    ).toEqual([`${P}.PESQUISA.HISTORICO_NOTA_COMENTARIO(9,Gostei)`]);
  });

  it('o passo de hoje não ganha linha nova', () => {
    expect(detalheDoHistorico({ ramo: 'entao' }, t, hora)).toEqual([]);
  });
});

describe('o resumo da pesquisa na lista', () => {
  it('média no formato do idioma, com o plural pelas respostas', () => {
    expect(resumoDaPesquisa({ media: 8.6, respostas: 37 }, t, 'pt_BR')).toBe(
      `${P}.PESQUISA.RESUMO(8,6,37)#37`
    );
  });

  it('sem resposta ainda, diz que não houve; sem pesquisa, nada', () => {
    expect(resumoDaPesquisa({ media: null, respostas: 0 }, t, 'pt_BR')).toBe(
      `${P}.PESQUISA.RESUMO_VAZIO`
    );
    expect(resumoDaPesquisa(undefined, t, 'pt_BR')).toBe('');
  });
});
