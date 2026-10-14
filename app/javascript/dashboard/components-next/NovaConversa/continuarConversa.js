import { TIPOS, tipoDeMensagem } from './novaConversa';

// #1505 — continuar a conversa que o contato já tem na caixa, em funções
// puras. O servidor manda em `conversationToContinue` a conversa em que a
// mensagem entraria pela regra da caixa (ou null), e se a regra é "Reabrir a
// mesma conversa" (`locked`): aí não há escolha.

export const DESTINOS = Object.freeze({
  CONTINUAR: 'continuar',
  NOVA: 'nova',
});

// A conversa que o servidor achou para este canal, ou null.
export const conversaDoCanal = canal => canal?.conversationToContinue || null;

// Pergunta "continuar ou começar outra"? Só quando há conversa e a caixa
// deixa criar conversas novas.
export const temEscolha = canal => {
  const conversa = conversaDoCanal(canal);
  return Boolean(conversa && !conversa.locked);
};

// Em que conversa a mensagem vai entrar; null = cria conversa nova.
export const conversaDeDestino = ({ canal, destino }) => {
  const conversa = conversaDoCanal(canal);
  if (!conversa) return null;
  if (conversa.locked) return conversa;
  return destino === DESTINOS.CONTINUAR ? conversa : null;
};

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
