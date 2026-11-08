import { TIPOS, tipoDeMensagem } from './novaConversa';

// #1505 — continuar a conversa que o contato já tem na caixa, em funções
// puras. O servidor manda em `conversationToContinue` a conversa em que a
// mensagem entraria pela regra da caixa (ou null), e se a regra é "Reabrir a
// mesma conversa" (`locked`): aí não há escolha. `visible` falso: a conversa
// existe, mas a pessoa não pode vê-la (acesso por funil). Só vem com
// "Reabrir", e aí o envio segue pela criação, que entra nela sozinha.

export const DESTINOS = Object.freeze({
  CONTINUAR: 'continuar',
  NOVA: 'nova',
});

// A conversa que o servidor achou para este canal, ou null.
export const conversaDoCanal = canal => canal?.conversationToContinue || null;

// A conversa existe, mas a pessoa não pode abri-la.
export const conversaOculta = canal => {
  const conversa = conversaDoCanal(canal);
  return Boolean(conversa && !conversa.visible);
};

// Em que conversa a mensagem vai entrar pela API de mensagem; null = envia
// pela criação de conversa (nova, ou a oculta, em que a criação entra sem
// reabrir: ela continua resolvida ou adiada até o cliente responder).
export const conversaDeDestino = ({ canal, destino }) => {
  const conversa = conversaDoCanal(canal);
  if (!conversa || !conversa.visible) return null;
  if (conversa.locked) return conversa;
  return destino === DESTINOS.CONTINUAR ? conversa : null;
};

// #2216 — começar conversa na conversa visível de uma caixa com "Reabrir a
// mesma conversa" leva o sinal `reabrir_ao_escrever`: o servidor reabre a
// resolvida ou adiada sem mudar quem cuida. A oculta (a pessoa não pode vê-la)
// vai pela criação e não reabre; "Continuar" em caixa que cria conversas novas
// e conversa nova não levam o sinal. `conversa` é a de conversaDeDestino.
export const reabreAoEscrever = conversa =>
  Boolean(conversa?.visible && conversa.locked);

// O que dá para mandar dentro de uma conversa que já existe: quem decide é o
// servidor (`can_reply`, que já conta a janela de 24 h e o WhatsApp Híbrido).
// Pode responder: texto livre. Não pode: só mensagem pronta, no WhatsApp.
export const tipoAoContinuar = ({ canal, podeResponder }) => {
  const tipo = tipoDeMensagem(canal);
  if (tipo === TIPOS.WHATSAPP_LIVRE || tipo === TIPOS.WHATSAPP_PRONTA) {
    return podeResponder ? TIPOS.WHATSAPP_LIVRE : TIPOS.WHATSAPP_PRONTA;
  }
  if (tipo === TIPOS.WHATSAPP_TWILIO && podeResponder) return TIPOS.TEXTO;
  return tipo;
};

// A situação da conversa como a pessoa fala (chave do catálogo).
const SITUACOES = Object.freeze({
  open: 'ABERTA',
  pending: 'PENDENTE',
  snoozed: 'ADIADA',
  resolved: 'RESOLVIDA',
});

export const chaveDaSituacao = status => SITUACOES[status] || SITUACOES.open;

// O que identifica o momento da escolha: trocar de contato, de canal ou de
// conversa encontrada zera a escolha e pergunta de novo ao servidor.
export const chaveDaEscolha = ({ contato, canal }) =>
  [contato?.id ?? '', canal?.id ?? '', conversaDoCanal(canal)?.displayId ?? '']
    .map(String)
    .join('|');
