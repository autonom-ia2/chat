import {
  segundaVersaoPronta,
  semModeloSobrando,
  temDuasVersoes,
  versoesIguais,
} from '../versoesDoPasso';
import { motivoIncompleto } from '../receita';

// #3099 — a versão 2 do passo "mensagem": pronta, diferente da 1 e com modelo
// só quando a versão 1 tem modelo.
const regra = { criterio: 'respostas', divisao: 50, espera: 4 };
const modelo = (nome, variaveis = []) => ({ nome, idioma: 'pt_BR', variaveis });
const passo = (versoes, extra = {}) => ({
  id: 'p1',
  tipo: 'mensagem',
  texto: ['Oi, ', { $valor: 'contato.nome' }],
  ...extra,
  ...(versoes ? { versoes: { ...regra, modelo: null, ...versoes } } : {}),
});

describe('versoesDoPasso', () => {
  it('sem as duas versões, o passo está pronto e nada muda', () => {
    const semVersoes = passo(null);
    expect(temDuasVersoes(semVersoes)).toBe(false);
    expect(segundaVersaoPronta(semVersoes)).toBe(true);
    expect(semModeloSobrando(semVersoes)).toBe(semVersoes);
    expect(motivoIncompleto(semVersoes)).toBeNull();
  });

  it('a versão 2 vazia ou só com espaço não está pronta', () => {
    expect(segundaVersaoPronta(passo({ texto: [] }))).toBe(false);
    expect(segundaVersaoPronta(passo({ texto: ['  '] }))).toBe(false);
    expect(motivoIncompleto(passo({ texto: [] }))).toBe('VERSAO_2');
    expect(segundaVersaoPronta(passo({ texto: ['Olá!'] }))).toBe(true);
    expect(motivoIncompleto(passo({ texto: ['Olá!'] }))).toBeNull();
  });

  it('a versão 2 igual à 1 não está pronta, mesmo com as chaves em outra ordem', () => {
    const igual = passo(
      {
        texto: ['Oi, ', { $valor: 'contato.nome' }],
        modelo: { variaveis: [], idioma: 'pt_BR', nome: 'oi' },
      },
      { modelo: modelo('oi') }
    );
    expect(versoesIguais(igual)).toBe(true);
    expect(segundaVersaoPronta(igual)).toBe(false);
  });

  it('com modelo na versão 1, a versão 2 precisa do dela, com cada variável', () => {
    const comModelo = { modelo: modelo('oi', [['Ana']]) };
    expect(segundaVersaoPronta(passo({ texto: ['Olá'] }, comModelo))).toBe(
      false
    );
    expect(
      segundaVersaoPronta(
        passo({ texto: ['Olá'], modelo: modelo('ola', [[' ']]) }, comModelo)
      )
    ).toBe(false);
    expect(
      segundaVersaoPronta(
        passo({ texto: ['Olá'], modelo: modelo('ola', [['Ana']]) }, comModelo)
      )
    ).toBe(true);
  });

  it('tirado o modelo da versão 1, o da versão 2 sai junto', () => {
    const sobrando = passo({ texto: ['Olá'], modelo: modelo('ola') });
    expect(semModeloSobrando(sobrando).versoes.modelo).toBeNull();
    expect(semModeloSobrando(sobrando).versoes.texto).toEqual(['Olá']);
    const comOs2 = passo(
      { texto: ['Olá'], modelo: modelo('ola') },
      { modelo: modelo('oi') }
    );
    expect(semModeloSobrando(comOs2)).toBe(comOs2);
  });
});
