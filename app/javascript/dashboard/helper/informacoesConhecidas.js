// #3176 — informação gravada no contato sem definição de campo, com chave que a
// plataforma conhece: ganha nome em português (i18n) e aparece igual na ficha
// (relacionamentos/ficha/atributos.js, como campo solto) e no painel da
// conversa (conversation/customAttributes/CustomAttributes.vue). Sem isso a
// ficha mostrava "Job title" e o painel não mostrava nada.
//  - `job_title`: o cargo, que o cadastro do card e o Decisor gravam;
//  - a nota e o número de avaliações no Google, que a Prospecção grava.
// Chave com definição na conta segue a definição (nome e tipo que a conta deu).
// Lista explícita: chave fora dela não ganha nome daqui.
export const INFORMACOES_CONHECIDAS = Object.freeze({
  job_title: 'RELACIONAMENTOS_FICHA.CAMPOS.CONHECIDOS.CARGO',
  autonomia_prospecting_rating:
    'RELACIONAMENTOS_FICHA.CAMPOS.CONHECIDOS.NOTA_NO_GOOGLE',
  autonomia_prospecting_reviews_count:
    'RELACIONAMENTOS_FICHA.CAMPOS.CONHECIDOS.AVALIACOES_NO_GOOGLE',
});

// A chave i18n do nome da informação, ou undefined quando a chave não é
// conhecida.
export const rotuloConhecido = chave =>
  Object.hasOwn(INFORMACOES_CONHECIDAS, chave)
    ? INFORMACOES_CONHECIDAS[chave]
    : undefined;

const temValor = valor => valor !== undefined && valor !== null && valor !== '';

// As informações conhecidas que o contato tem e a conta não definiu como campo,
// na ordem da lista: [{ chave, rotulo (chave i18n), valor }]. `definidas`: as
// chaves com definição na conta.
export const informacoesConhecidas = (valores = {}, definidas = []) =>
  Object.entries(INFORMACOES_CONHECIDAS)
    .filter(
      ([chave]) => !definidas.includes(chave) && temValor(valores?.[chave])
    )
    .map(([chave, rotulo]) => ({ chave, rotulo, valor: valores[chave] }));
