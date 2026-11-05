// Automação livre (#2569): o namespace AUTOMACAO_LIVRE é montado no index a
// partir de um arquivo por área. O spread do index sobrescreve sem avisar uma
// chave que estiver em dois arquivos; aqui isso reprova.
import en from '../locale/en';
import pt from '../locale/pt_BR';

const areas = import.meta.glob('../locale/{en,pt_BR}/automacaoLivre*.json', {
  eager: true,
  import: 'default',
});

const doIdioma = idioma =>
  Object.entries(areas)
    .filter(([caminho]) => caminho.includes(`/${idioma}/`))
    .map(([caminho, catalogo]) => [caminho, catalogo.AUTOMACAO_LIVRE]);

it('cada arquivo de área tem os mesmos blocos em en e pt_BR', () => {
  const blocos = idioma =>
    Object.fromEntries(
      doIdioma(idioma).map(([caminho, bloco]) => [
        caminho.split('/').at(-1),
        Object.keys(bloco).sort(),
      ])
    );
  expect(blocos('pt_BR')).toEqual(blocos('en'));
});

describe.each([
  ['en', en],
  ['pt_BR', pt],
])('AUTOMACAO_LIVRE em %s', (idioma, mensagens) => {
  const arquivos = doIdioma(idioma);

  it('tem os cinco arquivos de área', () => {
    expect(arquivos).toHaveLength(5);
  });

  it('não repete chave entre os arquivos de área', () => {
    const donos = {};
    arquivos.forEach(([caminho, bloco]) =>
      Object.keys(bloco).forEach(chave => {
        donos[chave] = [...(donos[chave] || []), caminho];
      })
    );
    const repetidas = Object.entries(donos).filter(
      ([, lista]) => lista.length > 1
    );
    expect(repetidas).toEqual([]);
  });

  it('o index junta todas as áreas no mesmo namespace', () => {
    const juntas = Object.assign({}, ...arquivos.map(([, bloco]) => bloco));
    expect(mensagens.AUTOMACAO_LIVRE).toEqual(juntas);
  });
});
