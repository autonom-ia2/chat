import { agruparPorFamilia, FAMILIA_OUTROS } from '../helpers/assuntos';

const capitulo = (id, artigos, titulo = `Capítulo ${id}`) => ({
  id,
  titulo,
  artigos,
});
const artigo = (id, extra = {}) => ({
  id,
  ref: id.replace('.', '-'),
  ...extra,
});

describe('agruparPorFamilia', () => {
  it('agrupa os capítulos nas famílias, na ordem da tela', () => {
    const familias = agruparPorFamilia([
      capitulo('11', [artigo('11.01')]),
      capitulo('08', [artigo('08.01')]),
      capitulo('07', [artigo('07.01')]),
      capitulo('00', [artigo('00.01')]),
    ]);

    expect(familias.map(familia => familia.id)).toEqual([
      'ATENDER',
      'AUTOMATIZAR',
      'CONTA',
    ]);
    expect(familias[0].assuntos.map(assunto => assunto.id)).toEqual([
      '07',
      '08',
    ]);
    expect(familias[0].assuntos[0].nome).toBe('CANAIS');
  });

  it('põe o capítulo desconhecido em "Outros assuntos", com o título da API', () => {
    const familias = agruparPorFamilia([
      capitulo('07', [artigo('07.01')]),
      capitulo('19', [artigo('19.01')], 'Assunto novo'),
    ]);

    const outros = familias.at(-1);
    expect(outros.id).toBe(FAMILIA_OUTROS);
    expect(outros.assuntos).toEqual([
      expect.objectContaining({ id: '19', titulo: 'Assunto novo', nome: null }),
    ]);
  });

  it('esconde o assunto sem artigo e a família que ficou vazia', () => {
    const familias = agruparPorFamilia([
      capitulo('07', [artigo('07.01')]),
      capitulo('10', []),
      capitulo('13', []),
    ]);

    expect(familias.map(familia => familia.id)).toEqual(['ATENDER']);
  });

  it('conta só os artigos com vídeo e trata a falta do campo como sem vídeo', () => {
    const [familia] = agruparPorFamilia([
      capitulo('07', [
        artigo('07.01', { video: true }),
        artigo('07.02', { video: false }),
        artigo('07.03'),
      ]),
    ]);

    expect(familia.assuntos[0].artigos).toHaveLength(3);
    expect(familia.assuntos[0].videos).toBe(1);
  });
});
