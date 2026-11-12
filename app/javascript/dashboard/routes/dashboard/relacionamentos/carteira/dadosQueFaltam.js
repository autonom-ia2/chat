// #2897 — os dados que faltam para cotar, quando quem preenche é a pessoa da
// corretora: um campo por dado. Funções puras: nada do que chega é alterado.
// Dado de resposta fechada é escolha única: aqui fica só a chave curta de cada
// opção, na ordem em que aparece; o rótulo é do catálogo
// (RENOVACAO.COTACAO.OPCAO.<DADO>.<CHAVE>). Os outros dados são escritos: a
// data de nascimento num campo de data, o resto em texto livre.
const OPCOES = {
  estado_civil: ['solteiro', 'casado', 'separado', 'divorciado', 'viuvo'],
  quem_dirige: [
    'a_propria_pessoa',
    'marido_ou_esposa',
    'filho_ou_filha',
    'pai_ou_mae',
    'irmao_ou_irma',
    'funcionario',
    'outra_pessoa',
  ],
  onde_dorme: [
    'garagem_portao_automatico',
    'garagem_portao_manual',
    'sem_garagem',
  ],
  quanto_roda: ['ate_500', 'ate_800', 'ate_1500', 'mais_de_1500'],
  tipo_do_imovel: ['casa', 'casa_em_condominio', 'apartamento', 'outro'],
};
// No seguro de uma empresa, quem dirige nunca é "a própria pessoa".
const SO_DE_PESSOA = ['a_propria_pessoa'];
// Dado que pode ficar sem resposta: a cotação sai sem ele.
const OPCIONAIS = ['quem_dirige'];
// Dado escrito que é uma data: o campo é o de data, como os do seguro.
const DATAS = ['nascimento'];

// As opções de um dado de resposta fechada (`null` = o dado é texto livre).
export const opcoesDoDado = (dado, { deEmpresa = false } = {}) => {
  const opcoes = OPCOES[dado];
  if (!opcoes) return null;
  return deEmpresa
    ? opcoes.filter(opcao => !SO_DE_PESSOA.includes(opcao))
    : opcoes;
};

export const dadoOpcional = dado => OPCIONAIS.includes(dado);

// O tipo do campo de um dado escrito: 'date' ou 'text'.
export const tipoDoCampo = dado => (DATAS.includes(dado) ? 'date' : 'text');

const escrito = (escritos, dado) => String(escritos?.[dado] ?? '').trim();

// O primeiro dado obrigatório ainda vazio, na ordem da lista (`null` = nenhum).
export const primeiroDadoQueFalta = (faltou = [], escritos = {}) =>
  faltou.find(dado => !dadoOpcional(dado) && !escrito(escritos, dado)) ?? null;

// Só os dados que faltavam, sem espaço sobrando.
export const dadosEscritos = (faltou = [], escritos = {}) =>
  Object.fromEntries(faltou.map(dado => [dado, escrito(escritos, dado)]));
