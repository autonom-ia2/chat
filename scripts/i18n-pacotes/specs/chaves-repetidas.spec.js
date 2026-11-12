// @vitest-environment node
// #2858 — chave repetida no mesmo objeto de um catálogo i18n passa no JSON.parse (a última vence) e apaga o texto da
// primeira em silêncio: no merge da F7 com a F5, `AGENTS.VITRINE.CAMPOS.POR_TIPO` virou "Tipos de crime" nas placas
// solares. O checador lê o arquivo como texto e acusa cada repetida pelo caminho, sem regex.
import fs from 'fs';
import { chavesRepetidas } from '../chaves-repetidas.mjs';

const REGISTRO = JSON.parse(fs.readFileSync('config/fork_i18n.json', 'utf8'));
const RAIZ = 'app/javascript/dashboard/i18n/locale';

describe('chavesRepetidas', () => {
  it('finds a repeated key in the same object, by its path', () => {
    const texto =
      '{"A": {"CAMPOS": {"POR_TIPO": "x", "OUTRO": 1, "POR_TIPO": "y"}}}';
    expect(chavesRepetidas(texto)).toEqual(['A.CAMPOS.POR_TIPO']);
  });

  it('the same key in different objects, in lists or as a value is not a repetition', () => {
    const texto = JSON.stringify({
      A: { NOME: 'a', LISTA: [{ NOME: 'b' }, { NOME: 'c' }] },
      B: { NOME: 'NOME', TEXTO: '{"NOME": 1, "NOME": 2}' },
    });
    expect(chavesRepetidas(texto)).toEqual([]);
  });

  it('reads escaped quotes inside strings without losing the place', () => {
    const texto = '{"A": "diz \\"B\\": 1", "B": 2, "C": {"B": 3}, "B": 4}';
    expect(chavesRepetidas(texto)).toEqual(['B']);
  });

  it('no fork catalog in en or pt_BR has a repeated key', () => {
    const repetidas = REGISTRO.catalogs.flatMap(({ file }) =>
      REGISTRO.requiredLocales.flatMap(idioma =>
        chavesRepetidas(
          fs.readFileSync(`${RAIZ}/${idioma}/${file}`, 'utf8')
        ).map(caminho => `${idioma}/${file}: ${caminho}`)
      )
    );
    expect(repetidas).toEqual([]);
  });
});
