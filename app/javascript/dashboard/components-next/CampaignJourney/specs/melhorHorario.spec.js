import { coberturaDoPublico } from '../melhorHorario/melhorHorario';

describe('melhorHorario (#3101)', () => {
  it('is still counting while the server has no number', () => {
    expect(coberturaDoPublico({ conhecidos: null, total: 450 }).estado).toBe(
      'CONTANDO'
    );
  });

  it('splits the audience into who has an hour and who has not', () => {
    expect(coberturaDoPublico({ conhecidos: 312, total: 450 })).toEqual({
      estado: 'PARTE',
      conhecidos: 312,
      semHora: 138,
      total: 450,
    });
  });

  it('says nobody and everybody apart', () => {
    expect(coberturaDoPublico({ conhecidos: 0, total: 80 })).toMatchObject({
      estado: 'NINGUEM',
      semHora: 80,
    });
    expect(coberturaDoPublico({ conhecidos: 80, total: 80 }).estado).toBe(
      'TODOS'
    );
  });

  it('never counts more people with an hour than the audience has', () => {
    expect(coberturaDoPublico({ conhecidos: 500, total: 450 })).toMatchObject({
      estado: 'TODOS',
      conhecidos: 450,
      semHora: 0,
    });
  });
});
