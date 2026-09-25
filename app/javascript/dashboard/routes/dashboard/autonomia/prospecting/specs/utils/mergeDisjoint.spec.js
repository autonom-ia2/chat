import { mergeDisjoint } from '../../utils/mergeDisjoint';

describe('mergeDisjoint', () => {
  it('junta objetos com chaves diferentes, na ordem recebida', () => {
    expect(mergeDisjoint({ a: 1 }, { b: 2 }, { c: 3 })).toEqual({
      a: 1,
      b: 2,
      c: 3,
    });
    expect(Object.keys(mergeDisjoint({ b: 1 }, { a: 2 }))).toEqual(['b', 'a']);
  });

  it('quebra na hora quando duas partes trazem a mesma chave', () => {
    expect(() => mergeDisjoint({ mode: 'a' }, { x: 1 }, { mode: 'b' })).toThrow(
      'mergeDisjoint: chave repetida "mode"'
    );
  });

  it('não confunde chave repetida com propriedade herdada do Object', () => {
    expect(mergeDisjoint({ a: 1 }, { toString: 'x' })).toEqual({
      a: 1,
      toString: 'x',
    });
  });

  it('sem partes devolve objeto vazio', () => {
    expect(mergeDisjoint()).toEqual({});
  });
});
