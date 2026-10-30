// #2202 — quem disse a última mensagem da lista (linha 2). Sai dos campos da mensagem,
// nunca do texto. Usa as mesmas chaves do eco do celular (#1941):
// - cliente (incoming): sem prefixo;
// - eu: "Você:"; outra pessoa da equipe: o primeiro nome ("Ana:");
// - eco do celular: o autor congelado (c2y_phone_author_id) — eu, outra pessoa ou, sem
//   autor, "Equipe:" (decisão 4);
// - robô (AgentBot ou Captain::Assistant): o nome do robô + o selo "IA" (decisão 3);
// - nota privada: "Nota:";
// - modelo, automação ou campanha sem remetente: "Equipe:".
import {
  autorDoEco,
  ehEcoDoCelular,
  nomeDoAgente,
} from 'dashboard/components-next/conversa-canal/ecoDoCelular';

export const REMETENTE = {
  CLIENTE: 'cliente',
  VOCE: 'voce',
  PESSOA: 'pessoa',
  ROBO: 'robo',
  NOTA: 'nota',
  EQUIPE: 'equipe',
  NENHUM: 'nenhum',
};

const TIPO_DA_MENSAGEM = { INCOMING: 0, OUTGOING: 1, ACTIVITY: 2, TEMPLATE: 3 };
const ROBOS = ['AgentBot', 'Captain::Assistant'];
// Responsável ou remetente que é robô (AgentBot ou Captain::Assistant), pelo tipo do servidor.
export const ehTipoDeRobo = tipo => ROBOS.includes(tipo);
const ROBOS_NO_SENDER = ['agent_bot', 'captain_assistant'];

export const primeiroNome = nome =>
  String(nome || '')
    .trim()
    .split(' ')
    .filter(Boolean)[0] || '';

const ehRobo = mensagem =>
  ROBOS.includes(mensagem.sender_type) ||
  ROBOS_NO_SENDER.includes(mensagem.sender?.type);

const ehPessoaDaEquipe = mensagem =>
  mensagem.sender_type === 'User' || mensagem.sender?.type === 'user';

const daPessoa = (pessoa, euId) => {
  if (Number(pessoa.id) === Number(euId)) return { tipo: REMETENTE.VOCE };
  const nome = primeiroNome(nomeDoAgente(pessoa));
  return nome
    ? { tipo: REMETENTE.PESSOA, nome, id: pessoa.id }
    : { tipo: REMETENTE.EQUIPE };
};

const nossa = (mensagem, { euId, agentePorId }) => {
  const atributos = mensagem.content_attributes;
  if (ehEcoDoCelular(atributos)) {
    const autor = autorDoEco(atributos, agentePorId);
    return autor ? daPessoa(autor, euId) : { tipo: REMETENTE.EQUIPE };
  }
  if (ehRobo(mensagem)) {
    const nome = String(mensagem.sender?.name || '').trim();
    return nome ? { tipo: REMETENTE.ROBO, nome } : { tipo: REMETENTE.EQUIPE };
  }
  if (ehPessoaDaEquipe(mensagem) && mensagem.sender) {
    return daPessoa(mensagem.sender, euId);
  }
  return { tipo: REMETENTE.EQUIPE };
};

export const prefixoDoRemetente = (mensagem, contexto) => {
  if (!mensagem) return { tipo: REMETENTE.NENHUM };
  if (mensagem.private) return { tipo: REMETENTE.NOTA };
  const tipo = Number(mensagem.message_type);
  if (tipo === TIPO_DA_MENSAGEM.INCOMING) return { tipo: REMETENTE.CLIENTE };
  if (tipo === TIPO_DA_MENSAGEM.ACTIVITY) return { tipo: REMETENTE.NENHUM };
  return nossa(mensagem, contexto);
};

// A mensagem é uma resposta nossa, de uma pessoa (não robô, não nota): o "respondeu sem pegar".
export const ehRespostaDePessoa = prefixo =>
  [REMETENTE.VOCE, REMETENTE.PESSOA].includes(prefixo?.tipo);
