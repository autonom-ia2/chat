// Mensagem que o atendente mandou pelo app do celular (#1941, item 3). Volta como eco,
// com a marca `external_echo`, nos três WhatsApp: WAHA comum, híbrido e oficial com
// coexistência. Regra do Rodrigo:
// - o texto vem sem o prefixo que o conector WAHA põe ("*📱 Enviado do WhatsApp*");
// - um 📱 pequeno fica ao lado da hora;
// - o nome é o de quem estava atribuído quando a mensagem chegou (`c2y_phone_author_id`,
//   congelado no servidor). Sem atribuição, nenhum nome. Nunca o remetente: no WAHA é o
//   dono da chave de conexão.
// Mensagem sem a marca não muda. Vale para objetos em camelCase (balão) e snake_case
// (prévia da lista).

export const PREFIXO_DO_CELULAR = '*📱 Enviado do WhatsApp*';
const QUEBRAS = ['\r\n', '\n'];
const quebraNoComeco = texto => QUEBRAS.find(q => texto.startsWith(q));

export const ehEcoDoCelular = atributos =>
  Boolean(atributos?.externalEcho ?? atributos?.external_echo);

export const idDoAutorDoEco = atributos => {
  if (!ehEcoDoCelular(atributos)) return null;
  return atributos.c2yPhoneAuthorId ?? atributos.c2y_phone_author_id ?? null;
};

// Tira o prefixo e as quebras de linha logo depois dele; o resto do texto fica igual.
export const semPrefixoDoCelular = texto => {
  if (typeof texto !== 'string' || !texto.startsWith(PREFIXO_DO_CELULAR)) {
    return texto;
  }
  let resto = texto.slice(PREFIXO_DO_CELULAR.length);
  let quebra = quebraNoComeco(resto);
  while (quebra) {
    resto = resto.slice(quebra.length);
    quebra = quebraNoComeco(resto);
  }
  return resto;
};

export const textoDaMensagem = (texto, atributos) =>
  ehEcoDoCelular(atributos) ? semPrefixoDoCelular(texto) : texto;

// Quem estava atribuído, pelo store de agentes da conta (`agents/getAgentById`, que
// devolve {} quando não acha). Agente que saiu da conta, ou id vazio = ninguém.
export const autorDoEco = (atributos, agentePorId) => {
  const id = idDoAutorDoEco(atributos);
  if (id === null || id === undefined || id === '') return null;
  const agente = agentePorId(id);
  return agente?.id ? agente : null;
};

export const nomeDoAgente = agente =>
  agente ? agente.available_name || agente.name || '' : '';
