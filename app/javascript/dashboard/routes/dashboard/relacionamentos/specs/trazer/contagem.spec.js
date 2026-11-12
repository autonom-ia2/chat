import { ehPlanilha } from '../../trazer/arquivo';
import {
  SITUACAO_DO_PROBLEMA,
  contarProblemas,
  partesDaFrase,
  problemasPorCarregar,
  resumoDaTela,
} from '../../trazer/contagem';
import { formatarDia } from '../../trazer/prazo';

// Quantas pessoas entram quem diz é o servidor (`resumo.entram`): a tela só
// conta as linhas que ela mesma mostra (quantasEntram.spec.js tem o resto).
const leituraCom = (estados, extra = {}) => ({
  resumo: {
    total: 200,
    novas: 180,
    completadas: 15,
    comProblema: 5,
    entram: 195,
  },
  problemas: estados.map((estado, i) => ({ linha: i + 1, estado })),
  problemasTotal: estados.length,
  ...extra,
});
const { ABERTO, GUARDADO, DEIXADO } = SITUACAO_DO_PROBLEMA;

describe('resumoDaTela e partesDaFrase', () => {
  it('o conserto diminui os que precisam de você, sem virar "nova"', () => {
    const resumo = resumoDaTela(
      leituraCom([GUARDADO, ABERTO, ABERTO, ABERTO, ABERTO])
    );
    expect(resumo).toEqual({
      total: 200,
      novas: 180,
      completadas: 15,
      precisamDeVoce: 4,
      deixadas: 0,
      juntadas: 0,
      entram: 195,
    });
  });

  it('a frase tem as quatro partes quando todas existem', () => {
    const resumo = resumoDaTela(
      leituraCom([DEIXADO, ABERTO, ABERTO, ABERTO, ABERTO])
    );
    expect(partesDaFrase(resumo)).toEqual([
      { chave: 'NOVAS', count: 180 },
      { chave: 'COMPLETADAS', count: 15 },
      { chave: 'PRECISAM', count: 4 },
      { chave: 'DEIXADAS', count: 1 },
    ]);
  });

  it('parte zerada some da frase', () => {
    const resumo = resumoDaTela(
      leituraCom([GUARDADO, GUARDADO, GUARDADO, GUARDADO, GUARDADO])
    );
    expect(partesDaFrase(resumo).map(parte => parte.chave)).toEqual([
      'NOVAS',
      'COMPLETADAS',
    ]);
  });

  it('conta os problemas por situação', () => {
    expect(
      contarProblemas(leituraCom([GUARDADO, DEIXADO, ABERTO]).problemas)
    ).toEqual({
      abertos: 1,
      guardados: 1,
      deixados: 1,
    });
  });

  it('leitura vazia dá zero em tudo', () => {
    expect(resumoDaTela(null).entram).toBe(0);
    expect(partesDaFrase(resumoDaTela(null))).toEqual([]);
  });
});

describe('problemasPorCarregar', () => {
  it('é o que o servidor tem a mais do que a tela já mostra', () => {
    expect(
      problemasPorCarregar(leituraCom([ABERTO, ABERTO], { problemasTotal: 5 }))
    ).toBe(3);
  });

  it('nunca fica abaixo de zero, nem sem leitura', () => {
    expect(
      problemasPorCarregar(leituraCom([ABERTO, ABERTO], { problemasTotal: 1 }))
    ).toBe(0);
    expect(problemasPorCarregar(null)).toBe(0);
  });
});

describe('ehPlanilha', () => {
  it.each(['lista.xlsx', 'LISTA.XLSX', 'contatos.csv', ' clientes 2025.CSV '])(
    'aceita %s',
    nome => expect(ehPlanilha(nome)).toBe(true)
  );

  // O Excel antigo (.xls) saiu (#2896): o servidor só lê .xlsx e .csv.
  it.each([
    'lista.xls',
    'LISTA.XLS',
    'foto.png',
    'documento.pdf',
    'csv',
    'lista.xlsx.exe',
    '',
    undefined,
  ])('recusa %s', nome => expect(ehPlanilha(nome)).toBe(false));
});

describe('formatarDia', () => {
  it('escreve o dia como dia/mês no Brasil', () => {
    expect(formatarDia(Date.UTC(2026, 10, 18, 15), 'pt_BR')).toBe('18/11');
  });
});
