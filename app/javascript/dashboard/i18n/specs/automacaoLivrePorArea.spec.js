// Automação livre (#2569): o namespace AUTOMACAO_LIVRE é montado no index a
// partir de um arquivo por área. O spread do index sobrescreve sem avisar uma
// chave que estiver em dois arquivos; aqui isso reprova.
import en from '../locale/en';
import pt from '../locale/pt_BR';

const areas = import.meta.glob('../locale/{en,pt_BR}/automacaoLivre*.json', {
  eager: true,
  import: 'default',
});

// Onde cada bloco de topo mora. Bloco novo entra aqui, no arquivo da sua frente
// (docs/automacao/regerar-e-textos-por-area.md). Sem a lista, um bloco de área
// posto no automacaoLivre.json passaria sem aviso no arquivo errado.
const BLOCOS_POR_ARQUIVO = {
  'automacaoLivre.json': [
    'GRUPOS',
    'OPERADORES',
    'UNIDADES',
    'VALORES',
    'PASSOS',
    'ESCOLHER',
    'CAMPOS',
    'OPCOES',
    'LIGADA',
    'DESLIGADA',
    'LIGOU',
    'DESLIGOU',
    'VOLTAR_LISTA',
    'ALTERAR',
    'ALTERAR_ROTULO',
    'MUDOU',
    'FALHOU',
    'LISTA',
    'EDITOR',
    'CONFIRA',
    'FRASES',
    'RAMOS',
    'SELETOR',
    'ALTERAR_PAINEL',
    'LIGAR',
  ],
  'automacaoLivreGatilhos.json': [
    'GATILHOS',
    'ORIGEM',
    'VALOR_DA_MENSAGEM',
    'OPERADOR_DA_MENSAGEM',
    'PARAMETROS_DO_GATILHO',
    'GRUPOS_DO_GATILHO',
    'GATILHO_COM',
    'GATILHO_NO_FUNIL',
    'GATILHO_NAO_DISPARA',
    'GATILHO_DO_CARD',
    'GATILHO_NO_DIA',
    'GATILHO_TODO_ANO',
    'REPETE_DA_DATA',
    'QUANDO_DA_DATA',
    'GATILHO_DE_TEMPO',
    'GATILHO_RECORRENTE',
    'SELECAO',
    'MUDANCA',
  ],
  'automacaoLivreIa.json': ['IA'],
  'automacaoLivreReceitas.json': ['RECEITAS'],
  'automacaoLivreEnsaio.json': ['ENSAIO', 'HISTORICO'],
  'automacaoLivreCampanha.json': ['CAMPANHA'],
  'automacaoLivreRetorno.json': ['RETORNO'],
};

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

  it('tem os arquivos de área da lista', () => {
    const nomes = arquivos.map(([caminho]) => caminho.split('/').at(-1));
    expect(nomes.sort()).toEqual(Object.keys(BLOCOS_POR_ARQUIVO).sort());
  });

  it('cada bloco está no arquivo que a lista diz', () => {
    const foraDaLista = arquivos.flatMap(([caminho, bloco]) => {
      const nome = caminho.split('/').at(-1);
      const permitidos = BLOCOS_POR_ARQUIVO[nome] || [];
      return Object.keys(bloco)
        .filter(chave => !permitidos.includes(chave))
        .map(
          chave =>
            `${idioma}/${nome}: ${chave} — diga em qual arquivo ele mora e adicione na lista BLOCOS_POR_ARQUIVO`
        );
    });
    expect(foraDaLista).toEqual([]);
  });

  it('cada bloco da lista existe no seu arquivo', () => {
    const presentes = Object.fromEntries(
      arquivos.map(([caminho, bloco]) => [
        caminho.split('/').at(-1),
        Object.keys(bloco),
      ])
    );
    const sumidos = Object.entries(BLOCOS_POR_ARQUIVO).flatMap(
      ([nome, blocos]) =>
        blocos
          .filter(chave => !(presentes[nome] || []).includes(chave))
          .map(
            chave =>
              `${idioma}/${nome}: ${chave} está na lista mas não no arquivo — tire da lista ou devolva o bloco`
          )
    );
    expect(sumidos).toEqual([]);
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
