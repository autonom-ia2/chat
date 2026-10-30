import ptBR from 'dashboard/i18n/locale/pt_BR/funcoesDaEquipe.json';
import en from 'dashboard/i18n/locale/en/funcoesDaEquipe.json';

// #2308, especificação seção 3: uma palavra por coisa, e linguagem neutra (revisão do #2308: ninguém é "ele", "ela" nem
// "administradora"). Lê o catálogo pt_BR de verdade: um texto novo com palavra proibida faz este spec falhar.
// ("entregue" só vale para conversa, e não casa com "entregar".)
const TRECHOS = [
  'liberar',
  'entregar',
  'quadros de vendas',
  'cargo',
  'fila',
  'funil',
  'caixa',
  '(crm)',
  'prospecção',
  'participantes',
  'etapas',
  'opcional',
  'se quiser',
  'administradora',
  // A coluna "Nunca" da tabela da seção 3.
  'perfil',
  'papel',
  'editar',
  'ativar',
  'habilitar',
  'atribuída',
  'inbox',
  'pipeline',
  'números das vendas',
];
// Palavras inteiras: "ela" não pode casar com "janela" nem com "vela"; "crm" é a sigla solta (a seção 3 diz "vendas").
const PALAVRAS = ['ele', 'ela', 'eles', 'elas', 'dele', 'dela', 'crm'];
const PONTUACAO = ['.', ',', ':', ';', '!', '?', '(', ')', '"', '…'];

const textos = valor =>
  typeof valor === 'string' ? [valor] : Object.values(valor).flatMap(textos);

const palavrasDe = texto =>
  PONTUACAO.reduce(
    (resto, sinal) => resto.replaceAll(sinal, ' '),
    texto.toLowerCase()
  )
    .split(' ')
    .filter(Boolean);

const proibidasEm = catalogo =>
  textos(catalogo).flatMap(texto => {
    const minusculo = texto.toLowerCase();
    const palavras = palavrasDe(texto);
    return [
      ...TRECHOS.filter(trecho => minusculo.includes(trecho)),
      ...PALAVRAS.filter(palavra => palavras.includes(palavra)),
    ].map(achado => `${achado}: ${texto}`);
  });

describe('vocabulário de FUNCOES_EQUIPE (pt_BR)', () => {
  it('nenhum texto do catálogo usa palavra proibida', () => {
    expect(proibidasEm(ptBR.FUNCOES_EQUIPE)).toEqual([]);
  });

  it('a verificação pega o que deve pegar, e só isso', () => {
    expect(
      proibidasEm({
        A: 'Ela é administradora.',
        B: 'O colega chama a pessoa e manda o link (dele).',
        C: 'A janela da vela fica aberta.',
        D: 'Editar o perfil no CRM.',
      })
    ).toEqual([
      'administradora: Ela é administradora.',
      'ela: Ela é administradora.',
      'dele: O colega chama a pessoa e manda o link (dele).',
      'perfil: Editar o perfil no CRM.',
      'editar: Editar o perfil no CRM.',
      'crm: Editar o perfil no CRM.',
    ]);
  });
});

// Rodada 7 (L1): o nome da área na frase (NA_FRASE) entra no meio de outras frases ("Hoje só olha …", "Ver …"): o
// parêntese do NOME ("artigos para os clientes") não vai junto, em nenhuma das duas línguas.
describe('NA_FRASE das áreas', () => {
  it.each([
    ['pt_BR', ptBR],
    ['en', en],
  ])('%s: nenhuma traz parêntese', (_, catalogo) => {
    const comParentese = Object.entries(catalogo.FUNCOES_EQUIPE.AREAS)
      .filter(([, area]) => area.NA_FRASE?.includes('('))
      .map(([chave]) => chave);
    expect(comParentese).toEqual([]);
  });
});
