// #2896, Fatia 2 — qual cartão cada linha aberta ganha (components/trazer/
// ProblemaDaLinha.vue) e o campo que ele conserta. É só uma tabela dos tipos
// que o servidor manda: nenhum texto de pessoa é interpretado.
//   - telefone: o campo de telefone;
//   - e-mail, nome e a linha sem telefone nem e-mail (um campo só, que aceita
//     os dois): um campo de texto;
//   - repetida, com as duas linhas para comparar: a escolha de qual fica;
//   - o resto (a fórmula numa célula que a tela não conserta, a repetida sem a
//     outra linha, tipo que a tela não conhece) e toda linha quando a planilha
//     já foi apagada: sem conserto, só "Deixar de fora".
export const CAMPO_CONTATO = 'contato';

const CAMPO_DO_TIPO = new Map([
  ['telefone', 'telefone'],
  ['email', 'email'],
  ['nome', 'nome'],
  ['sem_contato', CAMPO_CONTATO],
]);
const TIPO_REPETIDA = 'duplicada';

export const CARTOES = {
  TELEFONE: 'telefone',
  TEXTO: 'texto',
  REPETIDA: 'repetida',
  SEM_CONSERTO: 'sem_conserto',
};

export const campoDoProblema = problema =>
  CAMPO_DO_TIPO.get(problema.tipo) ?? '';

export const ehRepetida = problema => problema.tipo === TIPO_REPETIDA;

// A linha repetida só pergunta "Qual fica?" quando há as duas para escolher.
export const temAsDuasLinhas = problema =>
  ehRepetida(problema) && Boolean(problema.outraLinha);

export const cartaoDoProblema = (problema, semConserto) => {
  if (semConserto) return CARTOES.SEM_CONSERTO;
  const campo = campoDoProblema(problema);
  if (campo === 'telefone') return CARTOES.TELEFONE;
  if (campo) return CARTOES.TEXTO;
  return temAsDuasLinhas(problema) ? CARTOES.REPETIDA : CARTOES.SEM_CONSERTO;
};
