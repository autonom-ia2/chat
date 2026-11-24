import { compararVersoes, deCadaCem } from '../vencedora';

// #3099 — quem foi melhor entre as duas versões, com a régua de palavras da comparação com o grupo de controle.
const versao = (receberam, responderam, compraram = 0) => ({
  receberam,
  responderam,
  compraram,
});

describe('compararVersoes', () => {
  it('cedo demais com poucas respostas somadas', () => {
    expect(compararVersoes(versao(100, 3), versao(100, 6))).toEqual({
      chave: 'POUCOS',
      melhor: null,
    });
  });

  it('o dobro de respostas pela taxa redonda', () => {
    expect(
      compararVersoes(versao(100, 8), versao(100, 16), 'respostas')
    ).toEqual({ chave: 'DOBRO', melhor: 2 });
  });

  it('compara pela taxa, não pelo total, quando a divisão é 70 e 30', () => {
    // 21 de 234 (9 em 100) contra 18 de 100 (18 em 100): a versão 2 dobra mesmo com menos respostas.
    expect(compararVersoes(versao(234, 21), versao(100, 18))).toEqual({
      chave: 'DOBRO',
      melhor: 2,
    });
  });

  it('quase igual vira empate', () => {
    expect(compararVersoes(versao(200, 20), versao(200, 21))).toEqual({
      chave: 'EMPATE',
      melhor: null,
    });
  });

  it('só uma teve resultado', () => {
    expect(compararVersoes(versao(100, 12), versao(100, 0))).toEqual({
      chave: 'SO_UMA',
      melhor: 1,
    });
  });

  it('pelas compras olha o campo compraram', () => {
    expect(
      compararVersoes(versao(300, 40, 3), versao(300, 20, 12), 'compras')
    ).toEqual({ chave: 'MAIS', melhor: 2, vezes: 4 });
  });

  it('eu escolho compara pelas respostas', () => {
    expect(
      compararVersoes(versao(100, 30, 0), versao(100, 10, 9), 'eu_escolho')
    ).toEqual({ chave: 'TRIPLO', melhor: 1 });
  });
});

describe('deCadaCem', () => {
  it('passa para de cada mil quando a taxa é menor que 1 em 100', () => {
    expect(
      deCadaCem(versao(2000, 0, 10), versao(2000, 0, 30), 'compras')
    ).toEqual({ escala: 1000, 1: 5, 2: 15 });
  });
});
