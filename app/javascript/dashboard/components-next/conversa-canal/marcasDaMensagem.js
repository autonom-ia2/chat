// Marcas que o servidor grava em content_attributes e a pele do WhatsApp desenha (#1702).
// Aqui só se lê o que veio (a lista de mensagens já converteu as chaves para camelCase).
// Contrato acertado com o chat do WhatsApp Híbrido em 16/10/2026; vale para Cloud e WAHA.
import { MESSAGE_TYPES } from '../message/constants';
import { ehReacaoDoAgente } from './reacoes';

// Apagada pelo cliente: o conteúdo continua guardado e à vista da equipe (decisão de
// negócio: o atendimento guarda o que o cliente mandou). `deleted` é a apagada pela
// equipe, do Chatwoot, e segue como sempre.
export const apagadaPeloCliente = atributos =>
  Boolean(atributos?.deletedByContactAt);

// Editada: `content` já é o texto novo; `editHistory` traz as versões anteriores, da
// mais antiga para a mais nova.
export const foiEditada = atributos => Boolean(atributos?.editedAt);

export const versoesAnteriores = atributos => {
  const lista = atributos?.editHistory;
  if (!Array.isArray(lista)) return [];
  return lista.filter(versao => versao && typeof versao.content === 'string');
};

// Encaminhada (≤5 vezes) ou encaminhada com frequência (>5), como o WhatsApp marca.
export const ENCAMINHADA = { SIMPLES: 'simples', FREQUENTE: 'frequente' };

export const encaminhamento = atributos => {
  if (atributos?.frequentlyForwarded) return ENCAMINHADA.FREQUENTE;
  if (atributos?.forwarded) return ENCAMINHADA.SIMPLES;
  return null;
};

// Tipos que o WhatsApp não deixa ver aqui (chegam como `unsupported`), cada um com o
// seu aviso. Tipo fora da lista fica com o aviso genérico de sempre.
export const TIPOS_NAO_SUPORTADOS = [
  'poll',
  'gif',
  'pinned',
  'edit',
  'view_once',
  'unknown',
];

// O aviso de visualização única que o aparelho vinculado não abre (#1709, WAHA) usa o
// mesmo balão do tipo `view_once`.
export const tipoNaoSuportado = atributos => {
  if (atributos?.viewOnceUnavailable === true) return 'view_once';
  if (!atributos?.isUnsupported) return null;
  const tipo = atributos.unsupportedKind;
  return TIPOS_NAO_SUPORTADOS.includes(tipo) ? tipo : null;
};

// Mensagem absorvida pela apresentação nova: com a pele, fica fora da lista. O voto
// da enquete já aparece na enquete (c2y_hidden); a reação que o agente da Autonomia
// recebe como mensagem do cliente já aparece no selo da mensagem reagida. Mensagem
// nossa (saída) nunca se esconde: mesma regra do #1709 (MessageList, isHidden).
const ESCONDIVEIS = [MESSAGE_TYPES.INCOMING, MESSAGE_TYPES.ACTIVITY];
export const ocultaNaPele = mensagem =>
  (ESCONDIVEIS.includes(mensagem?.messageType) &&
    mensagem?.contentAttributes?.c2yHidden === true) ||
  ehReacaoDoAgente(mensagem);

// A 1ª não lida que aparece na lista. `todas` vem do servidor (snake_case, na ordem
// da conversa); `visiveis`, já sem as escondidas. Se a 1ª não lida foi escondida, a
// faixa vai para a próxima visível; sem nenhuma depois dela, não há faixa.
export const primeiraNaoLidaVisivel = (todas, visiveis, primeiraNaoLida) => {
  if (!primeiraNaoLida) return null;
  const idsVisiveis = new Set(visiveis.map(mensagem => mensagem.id));
  if (idsVisiveis.has(primeiraNaoLida)) return primeiraNaoLida;
  const inicio = todas.findIndex(mensagem => mensagem.id === primeiraNaoLida);
  if (inicio < 0) return null;
  const proxima = todas
    .slice(inicio + 1)
    .find(mensagem => idsVisiveis.has(mensagem.id));
  return proxima ? proxima.id : null;
};

// Áudio que o cliente já ouviu: o microfone da mensagem enviada fica azul.
export const audioOuvido = atributos => Boolean(atributos?.playedAt);

// Mídia do cliente que não baixou (#1709): { kind, reason: 'download_failed', at }.
// Tipo fora da lista vira documento, como o servidor faz. O texto da mensagem é a
// legenda ou o aviso do servidor; `hasCaption: false` (quando vier) esconde o aviso
// repetido.
export const TIPOS_DE_MIDIA_INDISPONIVEL = [
  'voice',
  'audio',
  'image',
  'video',
  'document',
  'sticker',
];

export const midiaIndisponivel = atributos => {
  const marca = atributos?.mediaUnavailable;
  if (!marca || typeof marca !== 'object') return null;
  return {
    tipo: TIPOS_DE_MIDIA_INDISPONIVEL.includes(marca.kind)
      ? marca.kind
      : 'document',
    mostrarTexto: marca.hasCaption !== false,
  };
};

// Áudio de voz (PTT): `meta.is_voice_message` no anexo que chega (WAHA e o que o
// painel grava) ou `isVoiceMessage` no anexo ainda na caixa de resposta.
export const audioDeVoz = anexo =>
  Boolean(anexo?.meta?.isVoiceMessage || anexo?.isVoiceMessage);

// Áudio que veio como ARQUIVO, não gravado na hora: só com o "não" explícito do
// conector (#1709, `is_voice_message: false`). Sem marca, continua voz.
export const audioArquivo = anexo =>
  (anexo?.meta?.isVoiceMessage ?? anexo?.isVoiceMessage) === false;
