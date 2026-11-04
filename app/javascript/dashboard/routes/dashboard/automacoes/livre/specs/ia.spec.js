import { caminhosProntos, chaveDoNome, problemaDoCaminho } from '../ia';

// #2500 F7 — a chave do caminho sai do nome, e o painel avisa em frase o que a
// Receita recusaria no servidor.
const caminho = nome => ({
  nome,
  chave: chaveDoNome(nome),
  descricao: 'x',
  passos: [],
});

describe('chaveDoNome', () => {
  it('minúscula, sem acento, palavras com _', () => {
    expect(chaveDoNome('Cotação')).toBe('cotacao');
    expect(chaveDoNome('  Pós-venda  já ')).toBe('posvenda_ja');
    expect(chaveDoNome('Seguro de Vida 2')).toBe('seguro_de_vida_2');
  });

  it('fica vazia quando o nome não tem letra nem dígito', () => {
    expect(chaveDoNome('!!!')).toBe('');
  });
});

describe('problemaDoCaminho', () => {
  it('nome sem letra: "!!!" e "123"', () => {
    const lista = [caminho('Sinistro'), caminho('!!!'), caminho('123')];
    expect(problemaDoCaminho(lista, 1)).toBe('SEM_LETRA');
    expect(problemaDoCaminho(lista, 2)).toBe('SEM_LETRA');
  });

  it('"Nenhum" é o caminho de quando nada se aplica', () => {
    expect(problemaDoCaminho([caminho('Sinistro'), caminho('Nenhum')], 1)).toBe(
      'RESERVADO'
    );
  });

  it('mesmo nome ou mesma chave é repetido', () => {
    const lista = [
      caminho('Cotação'),
      caminho('cotacao'),
      caminho(' cotação '),
    ];
    expect(problemaDoCaminho(lista, 1)).toBe('REPETIDO');
    expect(problemaDoCaminho(lista, 2)).toBe('REPETIDO');
  });

  it('sem nome ainda não é problema; certo devolve null', () => {
    const lista = [caminho(''), caminho('Sinistro')];
    expect(problemaDoCaminho(lista, 0)).toBeNull();
    expect(problemaDoCaminho(lista, 1)).toBeNull();
  });
});

describe('caminhosProntos', () => {
  it('pede dois caminhos com nome, descrição e sem problema', () => {
    expect(caminhosProntos([caminho('Sinistro'), caminho('Cotação')])).toBe(
      true
    );
    expect(caminhosProntos([caminho('Sinistro'), caminho('Nenhum')])).toBe(
      false
    );
    expect(caminhosProntos([caminho('Sinistro')])).toBe(false);
  });
});
