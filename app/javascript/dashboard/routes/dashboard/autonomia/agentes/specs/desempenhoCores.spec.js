import {
  BORDA_DE_CIMA,
  COR,
  COR_DA_FRENTE,
  COR_DA_QUALIDADE,
  COR_DO_GRUPO,
  SERIES,
  TONS_DO_MAPA,
  corDe,
  degrauDoMapa,
  tomDoMapa,
} from '../utils/desempenhoCores';
import {
  ALTURA,
  LARGURA,
  degrauDaBolha,
  escalaRedonda,
  indiceDoPico,
  indicesDoEixo,
  picoDoMapa,
  tracoDaArea,
  tracoDaLinha,
  xDoIndice,
  yDoValor,
} from '../utils/desempenhoGrafico';

// #2226 v2 — as cores por série (mesma cor em todo o painel e na exportação) e as contas dos
// gráficos SVG (escala redonda, posição, traço, eixo X, pico e bolha).
describe('desempenhoCores', () => {
  it('gives every series the same set of token classes', () => {
    SERIES.forEach(serie => {
      expect(Object.keys(COR[serie])).toEqual(Object.keys(COR.volume));
      Object.values(COR[serie]).forEach(classe => {
        expect(classe).toContain('-n-');
        expect(classe).not.toContain('#');
      });
    });
  });

  it('maps groups, fronts and quality only to known series', () => {
    [COR_DO_GRUPO, COR_DA_FRENTE, COR_DA_QUALIDADE].forEach(mapa =>
      Object.values(mapa).forEach(serie => expect(SERIES).toContain(serie))
    );
    expect(Object.keys(BORDA_DE_CIMA).sort()).toEqual([...SERIES].sort());
  });

  it('falls back to neutral for an unknown series', () => {
    expect(corDe('inventada')).toBe(COR.neutro);
    expect(corDe('resultado')).toBe(COR.resultado);
  });

  it('uses 6 steps in the heat map, zero with its own tone', () => {
    expect(TONS_DO_MAPA).toHaveLength(6);
    expect(degrauDoMapa(0, 10)).toBe(0);
    expect(degrauDoMapa(1, 100)).toBe(1);
    expect(degrauDoMapa(50, 100)).toBe(3);
    expect(degrauDoMapa(100, 100)).toBe(5);
    expect(degrauDoMapa(5, 0)).toBe(0);
    expect(tomDoMapa(0, 10)).toBe(TONS_DO_MAPA[0]);
    expect(tomDoMapa(10, 10)).toBe(TONS_DO_MAPA[5]);
  });
});

describe('desempenhoGrafico', () => {
  it('rounds the Y scale to round numbers', () => {
    expect(escalaRedonda(13)).toEqual({ topo: 20, marcas: [20, 15, 10, 5, 0] });
    expect(escalaRedonda(267).topo).toBe(400);
    expect(escalaRedonda(80)).toEqual({
      topo: 80,
      marcas: [80, 60, 40, 20, 0],
    });
    expect(escalaRedonda(0).marcas).toHaveLength(5);
  });

  it('places each point in the middle of its column', () => {
    expect(xDoIndice(0, 2)).toBe(LARGURA / 4);
    expect(xDoIndice(1, 2)).toBe((LARGURA * 3) / 4);
    expect(yDoValor(0, 10)).toBe(ALTURA);
    expect(yDoValor(10, 10)).toBe(0);
  });

  it('draws the line between the given points and closes the area', () => {
    expect(tracoDaLinha([1, 2, 3], 4)).toBe(
      'M 166.7 225.0 L 500.0 150.0 L 833.3 75.0'
    );
    expect(tracoDaLinha([1, 2, 3], 4, 1, 2)).toBe('M 500.0 150.0 L 833.3 75.0');
    expect(tracoDaLinha([1], 4)).toBe('');
    expect(tracoDaArea([1, 2], 4).endsWith('Z')).toBe(true);
  });

  it('labels at most 7 dates, always the first and the last', () => {
    expect(indicesDoEixo(5)).toEqual([0, 1, 2, 3, 4]);
    const trinta = indicesDoEixo(30);
    expect(trinta).toHaveLength(7);
    expect(trinta[0]).toBe(0);
    expect(trinta.at(-1)).toBe(29);
    expect(indicesDoEixo(0)).toEqual([]);
  });

  it('finds the peak of the line and of the heat map', () => {
    expect(indiceDoPico([3, 9, 9, 1])).toBe(1);
    expect(indiceDoPico([])).toBe(-1);
    const mapa = Array.from({ length: 7 }, () => Array(24).fill(0));
    mapa[4][16] = 7;
    expect(picoDoMapa(mapa)).toEqual({ dia: 4, hora: 16, valor: 7 });
    expect(picoDoMapa([[0, 0]]).dia).toBe(-1);
  });

  it('grows the event bubble with the square root, in 5 steps', () => {
    expect(degrauDaBolha(0, 9)).toBe(0);
    expect(degrauDaBolha(9, 9)).toBe(5);
    expect(degrauDaBolha(1, 100)).toBe(1);
    expect(degrauDaBolha(25, 100)).toBe(3);
  });
});
