// #2414 G24 (#2771) — o passo "para cada item": a IA acha uma lista na conversa
// (os funcionários novos que o RH mandou) e cada item vira um card na etapa
// escolhida, com o contato achado pelo telefone ou criado. A régua é a do
// servidor (Autonomia::Automacao::PassoParaCada e ProblemasDoParaCada): o campo
// "nome" sempre, de 1 a 50 itens, etapa de um funil que quem salva vê.

// O teto técnico: o tamanho de uma resposta da IA (PassoParaCada::MAXIMO).
export const MAXIMO_DE_ITENS = 50;
// O contato e o card nascem do nome; o telefone é por onde o contato é achado.
export const CHAVE_DO_NOME = 'nome';
export const CHAVE_DO_TELEFONE = 'telefone';
// Os dados que o passo deixa para os seguintes: `ia.<id>.quantos` e `.nomes`.
export const VALORES_DO_PARA_CADA = ['quantos', 'nomes'];

export const novoParaCada = id => ({
  id,
  tipo: 'para_cada',
  le: ['mensagens_recentes'],
  descricao: '',
  campos: [{ chave: CHAVE_DO_NOME, descricao: '' }],
  etapa_id: null,
  maximo: 20,
});

export const maximoServe = maximo =>
  Number.isInteger(maximo) && maximo >= 1 && maximo <= MAXIMO_DE_ITENS;

const escrito = texto => Boolean((texto || '').trim());

export const paraCadaPronto = passo => {
  const campos = passo?.campos || [];
  return (
    escrito(passo?.descricao) &&
    campos.some(campo => campo.chave === CHAVE_DO_NOME) &&
    campos.every(campo => escrito(campo.chave) && escrito(campo.descricao)) &&
    Number.isInteger(passo.etapa_id) &&
    maximoServe(passo.maximo)
  );
};

const P = 'AUTOMACAO_LIVRE.PARA_CADA';
const CABE_NA_LINHA = 60;

// A frase da linha do passo, com o que quem montou escreveu.
export const fraseDoParaCada = (passo, t) => {
  const letras = Array.from((passo.descricao || '').trim());
  const item =
    letras.length > CABE_NA_LINHA
      ? `${letras.slice(0, CABE_NA_LINHA).join('').trimEnd()}…`
      : letras.join('');
  return item ? t(`${P}.FRASE`, { item }) : t(`${P}.FRASE_SEM_ITEM`);
};

// Os dados do passo no "Pôr um dado" dos passos seguintes.
export const valoresDoParaCada = (passo, t) =>
  VALORES_DO_PARA_CADA.map(valor => ({
    caminho: `ia.${passo.id}.${valor}`,
    chave: `${passo.id}.${valor}`,
    rotulo: t(`${P}.VALOR_${valor.toUpperCase()}`),
  }));
