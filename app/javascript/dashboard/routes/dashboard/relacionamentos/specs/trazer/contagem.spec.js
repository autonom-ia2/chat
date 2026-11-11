import { ehPlanilha } from '../../trazer/arquivo';
import {
  SITUACAO_DO_PROBLEMA,
  contarProblemas,
  nomeValido,
  partesDaFrase,
  resumoAoVivo,
  totalATrazer,
  totalDaLeitura,
} from '../../trazer/contagem';
import {
  PRAZO,
  SITUACOES_DA_LISTA,
  formatarDia,
  prazoParaDesfazer,
  situacaoDoPrazo,
} from '../../trazer/prazo';

const DIA = 24 * 60 * 60 * 1000;
const leituraCom = estados => ({
  resumo: { total: 200, novas: 180, completadas: 15, comProblema: 5 },
  problemas: estados.map((estado, i) => ({ linha: i + 1, estado })),
});
const { ABERTO, GUARDADO, DEIXADO } = SITUACAO_DO_PROBLEMA;

describe('totalATrazer', () => {
  it('é novas + completadas + consertadas − deixadas de fora', () => {
    expect(
      totalATrazer({
        novas: 180,
        completadas: 15,
        consertadas: 5,
        deixadasDeFora: 2,
      })
    ).toBe(198);
  });

  it('sem conserto é só novas + completadas', () => {
    expect(totalATrazer({ novas: 180, completadas: 15 })).toBe(195);
  });

  it('nunca fica abaixo de zero', () => {
    expect(totalATrazer({ deixadasDeFora: 3 })).toBe(0);
  });
});

describe('totalDaLeitura', () => {
  it('começa em 195 com as 5 linhas abertas', () => {
    expect(
      totalDaLeitura(leituraCom([ABERTO, ABERTO, ABERTO, ABERTO, ABERTO]))
    ).toBe(195);
  });

  it('sobe 1 para cada linha guardada', () => {
    expect(
      totalDaLeitura(leituraCom([GUARDADO, GUARDADO, ABERTO, ABERTO, ABERTO]))
    ).toBe(197);
  });

  it('linha deixada de fora não entra', () => {
    expect(
      totalDaLeitura(leituraCom([GUARDADO, DEIXADO, ABERTO, ABERTO, ABERTO]))
    ).toBe(196);
  });

  it('todas guardadas dão 200', () => {
    expect(
      totalDaLeitura(
        leituraCom([GUARDADO, GUARDADO, GUARDADO, GUARDADO, GUARDADO])
      )
    ).toBe(200);
  });

  it('leitura vazia dá zero', () => {
    expect(totalDaLeitura(null)).toBe(0);
  });
});

describe('resumoAoVivo e partesDaFrase', () => {
  it('conserto vira "nova" e diminui os que precisam de você', () => {
    const resumo = resumoAoVivo(
      leituraCom([GUARDADO, ABERTO, ABERTO, ABERTO, ABERTO])
    );
    expect(resumo).toEqual({
      total: 200,
      novas: 181,
      completadas: 15,
      precisamDeVoce: 4,
      deixadas: 0,
    });
  });

  it('a frase tem as quatro partes quando todas existem', () => {
    const resumo = resumoAoVivo(
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
    const resumo = resumoAoVivo(
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
});

describe('campos de conserto', () => {
  it('nomeValido pede alguma letra', () => {
    expect(nomeValido('Ana')).toBe(true);
    expect(nomeValido('   ')).toBe(false);
    expect(nomeValido(null)).toBe(false);
  });
});

describe('ehPlanilha', () => {
  it.each(['lista.xlsx', 'LISTA.XLS', 'contatos.csv', ' clientes 2025.CSV '])(
    'aceita %s',
    nome => expect(ehPlanilha(nome)).toBe(true)
  );

  it.each([
    'foto.png',
    'documento.pdf',
    'csv',
    'lista.xlsx.exe',
    '',
    undefined,
  ])('recusa %s', nome => expect(ehPlanilha(nome)).toBe(false));
});

describe('prazo para desfazer', () => {
  const quando = Date.UTC(2026, 10, 8, 12);

  it('é 7 dias depois de trazer', () => {
    expect(prazoParaDesfazer(quando)).toBe(quando + 7 * DIA);
  });

  it('lista pronta dentro dos 7 dias está aberta', () => {
    const lista = { situacao: SITUACOES_DA_LISTA.PRONTO, quando };
    expect(situacaoDoPrazo(lista, quando + 3 * DIA)).toBe(PRAZO.ABERTO);
    expect(situacaoDoPrazo(lista, quando + 7 * DIA)).toBe(PRAZO.ABERTO);
  });

  it('passado o prazo acaba', () => {
    const lista = { situacao: SITUACOES_DA_LISTA.PRONTO, quando };
    expect(situacaoDoPrazo(lista, quando + 7 * DIA + 1)).toBe(PRAZO.ACABOU);
  });

  it('lista trazendo ou desfeita não tem prazo', () => {
    const agora = quando + DIA;
    expect(
      situacaoDoPrazo({ situacao: SITUACOES_DA_LISTA.TRAZENDO, quando }, agora)
    ).toBe(PRAZO.NAO_SE_APLICA);
    expect(
      situacaoDoPrazo({ situacao: SITUACOES_DA_LISTA.DESFEITO, quando }, agora)
    ).toBe(PRAZO.NAO_SE_APLICA);
  });

  it('escreve o dia como dia/mês no Brasil', () => {
    expect(formatarDia(Date.UTC(2026, 10, 18, 15), 'pt_BR')).toBe('18/11');
  });
});
