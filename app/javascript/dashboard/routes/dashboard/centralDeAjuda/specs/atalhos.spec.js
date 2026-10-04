import {
  MAIS_PROCURADOS,
  SINTOMAS,
  atalhosVisiveis,
  refDoArtigo,
} from '../helpers/atalhos';

const capitulos = ids => [
  {
    id: 'x',
    titulo: 'X',
    artigos: ids.map(id => ({ id, ref: refDoArtigo(id) })),
  },
];

describe('atalhosVisiveis', () => {
  it('mostra o atalho com o ref do artigo quando a API devolveu o artigo', () => {
    const visiveis = atalhosVisiveis(MAIS_PROCURADOS, capitulos(['07.01']));

    expect(visiveis).toEqual([
      { rotulo: 'WHATSAPP', artigo: '07.01', ref: '07-01' },
    ]);
  });

  it('esconde o atalho cujo artigo não veio para a conta', () => {
    const todos = [...MAIS_PROCURADOS, ...SINTOMAS].map(
      atalho => atalho.artigo
    );
    const semUm = todos.filter(id => id !== '07.11');

    const visiveis = atalhosVisiveis(SINTOMAS, capitulos(semUm));

    expect(visiveis.map(atalho => atalho.rotulo)).not.toContain('CSAT_VAZIO');
    expect(visiveis).toHaveLength(SINTOMAS.length - 1);
  });

  it('não mostra nada quando a lista veio vazia', () => {
    expect(atalhosVisiveis(MAIS_PROCURADOS, [])).toEqual([]);
  });
});

describe('refDoArtigo', () => {
  it('troca o ponto do id por hífen', () => {
    expect(refDoArtigo('00.04')).toBe('00-04');
  });
});
