// #2897 — "Como as renovações andam": as escolhas, o padrão de cada uma e as
// regras puras da tela (o que falta, o que mudou, quantos seguros entram). Todo
// ajuste já nasce respondido: a corretora não precisa responder nada para a
// renovação andar.
export const ONDE = { CRIAR: 'criar', USAR: 'usar' };
export const MENSAGENS = { MANDAR: 'mandar', NAO_MANDAR: 'nao_mandar' };
export const ALGO_MUDOU = { PERGUNTAR: 'perguntar', NAO: 'nao_perguntar' };
export const QUEM_COTA = { ROBO: 'robo', AGENTE: 'agente', NINGUEM: 'ninguem' };
export const COMO_ENVIA = { CONFERE: 'confere', SOZINHA: 'sozinha' };
export const QUEM_RESPONDE = { AGENTE: 'agente', EQUIPE: 'equipe' };
export const PALAVRAS = {
  CONFIRO: 'confiro',
  SOZINHO: 'sozinho',
  NAO_MANDAR: 'nao_mandar',
};

export const DIAS_PADRAO = 60;
const DIAS_MINIMO = 1;
export const DIAS_DAS_MENSAGENS = [30, 15, 7];

export const AJUSTES_PADRAO = Object.freeze({
  onde: ONDE.CRIAR,
  funil: '',
  etapa: '',
  dias: DIAS_PADRAO,
  mensagens: MENSAGENS.MANDAR,
  algoMudou: ALGO_MUDOU.PERGUNTAR,
  quemCota: QUEM_COTA.ROBO,
  comoEnvia: COMO_ENVIA.CONFERE,
  quemResponde: QUEM_RESPONDE.AGENTE,
  palavras: PALAVRAS.CONFIRO,
});

// Quem faz a cotação, conforme o que a conta tem: "Automático" (ROBO) só
// existe na conta que cota sem conversar, e o agente só na conta que tem
// agente. A escolha que a conta não tem cai na seguinte: o agente, o
// "Automático", a equipe.
export const quemCotaNaConta = (
  quemCota,
  { cotaSemConversa = false, agente = null } = {}
) => {
  const tem = {
    [QUEM_COTA.ROBO]: cotaSemConversa,
    [QUEM_COTA.AGENTE]: Boolean(agente),
    [QUEM_COTA.NINGUEM]: true,
  };
  if (tem[quemCota]) return quemCota;
  return [QUEM_COTA.AGENTE, QUEM_COTA.ROBO, QUEM_COTA.NINGUEM].find(
    opcao => tem[opcao]
  );
};

// O número de dias que a pessoa escreveu: inteiro a partir de 1, ou null.
export const diasDigitados = texto => {
  const numero = Number(String(texto ?? '').trim());
  return Number.isInteger(numero) && numero >= DIAS_MINIMO ? numero : null;
};

export const umDiaAMenos = dias => Math.max(DIAS_MINIMO, (dias ?? 0) - 1);
export const umDiaAMais = dias => (dias ?? 0) + 1;

// Quantos seguros entram em renovação com esse número de dias. `vencimentos`:
// em quantos dias cada seguro que ainda vale termina.
export const quantosEntram = (vencimentos = [], dias = DIAS_PADRAO) =>
  dias ? vencimentos.filter(falta => falta >= 0 && falta <= dias).length : 0;

// O que falta para guardar a escolha de onde ficam as renovações: '' = nada.
export const FALTAS = { ONDE: 'ONDE', FUNIL: 'FUNIL', DIAS: 'DIAS' };
export const faltaEmOndeFicam = ({ onde, funil, dias } = {}) => {
  if (!onde) return FALTAS.ONDE;
  if (onde === ONDE.USAR && !funil) return FALTAS.FUNIL;
  return dias ? '' : FALTAS.DIAS;
};

// Escolher o funil já escolhe a primeira etapa dele.
export const comOFunil = (ajustes, funis, nome) => ({
  ...ajustes,
  funil: nome,
  etapa: funis.find(funil => funil.nome === nome)?.etapas[0] ?? '',
});

export const ajustesMudaram = (antes = {}, agora = {}) =>
  Object.keys(AJUSTES_PADRAO).some(chave => antes[chave] !== agora[chave]);
