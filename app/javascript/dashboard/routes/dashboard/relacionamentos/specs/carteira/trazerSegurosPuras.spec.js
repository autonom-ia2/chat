import {
  contadoresDaLeitura,
  pessoasDosSeguros,
  totalDeSeguros,
} from '../../carteira/contagemDeSeguros';
import { ehApolice, soApolices } from '../../carteira/arquivosDeApolice';
import {
  COMO,
  PASSOS,
  comoValido,
  etapaDoTopoDe,
  passoAnterior,
  primeiroPasso,
} from '../../carteira/passosDeTrazerSeguros';
import { ETAPAS } from '../../trazer/etapas';

// As contas e os passos de "trazer seguros" (#2897, telas 8, 9, 16 e 17), em
// funções puras.
const problema = (linha, estado) => ({ linha, estado });
const planilha = estados => ({
  achei: { seguros: 168, pessoas: 120 },
  prontos: 164,
  jaEstavam: 120,
  problemas: estados.map((estado, i) => problema(i + 1, estado)),
});

describe('quantos seguros vão chegar', () => {
  it('com tudo em aberto, só os prontos; cada problema resolvido soma um', () => {
    const abertos = ['aberto', 'aberto', 'aberto', 'aberto'];
    expect(totalDeSeguros(planilha(abertos))).toBe(164);
    expect(
      totalDeSeguros(planilha(['guardado', 'guardado', 'aberto', 'deixado']))
    ).toBe(166);
    expect(totalDeSeguros(planilha(abertos.map(() => 'guardado')))).toBe(168);
  });

  it('quem entra sem telefone (Agger) conta no total', () => {
    expect(
      totalDeSeguros({ prontos: 153, semTelefone: 3, problemas: [] })
    ).toBe(156);
  });

  it('pessoa de seguro em aberto ou deixado de fora não chega', () => {
    expect(pessoasDosSeguros(planilha(['guardado', 'guardado']))).toBe(120);
    expect(pessoasDosSeguros(planilha(['aberto', 'deixado', 'guardado']))).toBe(
      118
    );
  });

  it('leitura que ainda não chegou conta zero', () => {
    expect(totalDeSeguros(null)).toBe(0);
    expect(pessoasDosSeguros(null)).toBe(0);
    expect(contadoresDaLeitura(null)).toEqual([]);
  });
});

describe('os contadores da conferência', () => {
  it('planilha: prontos, precisam de você e pessoas que já estavam aqui', () => {
    expect(contadoresDaLeitura(planilha(Array(4).fill('aberto')))).toEqual([
      { chave: 'PRONTOS', count: 164 },
      { chave: 'PRECISAM', count: 4 },
      { chave: 'JA_ESTAVAM', count: 120 },
    ]);
  });

  it('resolver sobe os prontos; deixar de fora ganha o seu contador', () => {
    expect(
      contadoresDaLeitura(planilha(['guardado', 'deixado', 'aberto', 'aberto']))
    ).toEqual([
      { chave: 'PRONTOS', count: 165 },
      { chave: 'PRECISAM', count: 2 },
      { chave: 'JA_ESTAVAM', count: 120 },
      { chave: 'DEIXADOS', count: 1 },
    ]);
  });

  it('PDFs contam o que não é apólice; o Agger, quem está sem telefone', () => {
    expect(
      contadoresDaLeitura({
        prontos: 37,
        naoEApolice: ['boleto-marco.pdf'],
        problemas: [problema(1, 'aberto'), problema(2, 'aberto')],
      })
    ).toEqual([
      { chave: 'PRONTOS', count: 37 },
      { chave: 'PRECISAM', count: 2 },
      { chave: 'NAO_E_APOLICE', count: 1 },
    ]);
    expect(
      contadoresDaLeitura({ prontos: 153, semTelefone: 3, jaEstavam: 112 })
    ).toEqual([
      { chave: 'PRONTOS', count: 153 },
      { chave: 'SEM_TELEFONE', count: 3 },
      { chave: 'JA_ESTAVAM', count: 112 },
    ]);
  });
});

describe('o que é arquivo de apólice', () => {
  it('PDF e foto de celular, pelo fim do nome', () => {
    expect(ehApolice('apolice-01.pdf')).toBe(true);
    expect(ehApolice('FOTO.JPG')).toBe(true);
    expect(ehApolice('apolice.heic')).toBe(true);
    expect(ehApolice('Carteira 2026.xlsx')).toBe(false);
    expect(ehApolice(undefined)).toBe(false);
  });

  it('de vários arquivos, ficam só os que servem', () => {
    const arquivos = [{ name: 'a.pdf' }, { name: 'b.xlsx' }, { name: 'c.png' }];
    expect(soApolices(arquivos).map(a => a.name)).toEqual(['a.pdf', 'c.png']);
    expect(soApolices(null)).toEqual([]);
  });
});

describe('os passos de cada jeito de trazer', () => {
  it('o endereço só vale com um jeito conhecido', () => {
    expect(comoValido('pdfs')).toBe(COMO.PDFS);
    expect(comoValido('fax')).toBe('');
    expect(comoValido(undefined)).toBe('');
  });

  it('sem jeito escolhido, a escolha; planilha e PDFs enviam; o Agger liga', () => {
    expect(primeiroPasso('')).toBe(PASSOS.COMO);
    expect(primeiroPasso(COMO.PLANILHA)).toBe(PASSOS.ENVIAR);
    expect(primeiroPasso(COMO.PDFS)).toBe(PASSOS.ENVIAR);
    expect(primeiroPasso(COMO.AGGER)).toBe(PASSOS.LIGAR);
  });

  it('Voltar anda uma tela para trás, até a escolha', () => {
    expect(passoAnterior(COMO.PLANILHA, PASSOS.CONFERIR)).toBe(PASSOS.PERGUNTA);
    expect(passoAnterior(COMO.PLANILHA, PASSOS.PERGUNTA)).toBe(PASSOS.ENVIAR);
    expect(passoAnterior(COMO.PLANILHA, PASSOS.ENVIAR)).toBe(PASSOS.COMO);
    expect(passoAnterior(COMO.PDFS, PASSOS.CONFERIR)).toBe(PASSOS.ENVIAR);
    expect(passoAnterior(COMO.AGGER, PASSOS.CONFERIR)).toBe(PASSOS.LIGAR);
    expect(passoAnterior(COMO.AGGER, PASSOS.LIGAR)).toBe(PASSOS.COMO);
  });

  it('as etapas do topo só aparecem depois da escolha', () => {
    expect(etapaDoTopoDe(PASSOS.COMO)).toBeNull();
    expect(etapaDoTopoDe(PASSOS.ENVIAR)).toBe(ETAPAS.ENVIAR);
    expect(etapaDoTopoDe(PASSOS.PERGUNTA)).toBe(ETAPAS.ENVIAR);
    expect(etapaDoTopoDe(PASSOS.LIGAR)).toBe(ETAPAS.ENVIAR);
    expect(etapaDoTopoDe(PASSOS.CONFERIR)).toBe(ETAPAS.CONFERIR);
    expect(etapaDoTopoDe(PASSOS.TRAZENDO)).toBe(ETAPAS.PRONTO);
    expect(etapaDoTopoDe(PASSOS.PRONTO)).toBe(ETAPAS.PRONTO);
  });
});
