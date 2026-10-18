// Álbum anunciado pelo WAHA (#1831). O conector do WhatsApp Híbrido cria, antes das
// fotos, uma mensagem-marcador recebida com content_attributes.waha_album =
// { expected_images, expected_videos }. Com a flag do #1741 o marcador é uma atividade
// escondida (c2y_hidden); sem ela, uma mensagem recebida comum. Nos dois formatos ele
// abre o álbum como o marcador da Cloud, com uma diferença: diz quantas fotos e vídeos
// virão, e a grade já nasce do tamanho certo. A caixa híbrida que recebe pela Cloud
// segue a regra da Cloud (sem contagem).
import { MESSAGE_TYPES } from '../../message/constants';

const TIPOS_DO_MARCADOR = [MESSAGE_TYPES.INCOMING, MESSAGE_TYPES.ACTIVITY];

// Álbum é de 2 em diante (o mesmo mínimo do agrupamento).
const MINIMO_ANUNCIADO = 2;

const quantos = valor => (Number.isInteger(valor) && valor > 0 ? valor : 0);

// Quantas fotos e vídeos o marcador anuncia, ou null quando não é marcador do WAHA.
export const contagemDoWaha = mensagem => {
  const album = mensagem?.contentAttributes?.wahaAlbum;
  if (!album) return null;
  const total = quantos(album.expectedImages) + quantos(album.expectedVideos);
  return total >= MINIMO_ANUNCIADO ? total : null;
};

export const eMarcadorDoWaha = mensagem =>
  TIPOS_DO_MARCADOR.includes(mensagem?.messageType) &&
  !mensagem.private &&
  contagemDoWaha(mensagem) !== null;

// Na tela, o marcador do WAHA que aparece (álbum chegando sem foto, ou janela fechada
// sem foto) é desenhado como o da Cloud: balão do cliente com o aviso honesto de
// mensagem que não carregou. A atividade não tem remetente: vira do contato da
// conversa, do lado do cliente. As outras mensagens passam como vieram. O `type` do
// remetente vai como nas mensagens do contato ('contact'): a sequência compara os dois.
const REMETENTE_CONTATO = 'contact';

export const paraOBalao = (mensagem, contato) => {
  if (!eMarcadorDoWaha(mensagem)) return mensagem;
  const semRemetente = !mensagem.senderId && !mensagem.sender;
  const remetente = { ...contato, type: REMETENTE_CONTATO };
  return {
    ...mensagem,
    ...(semRemetente && contato
      ? { sender: remetente, senderId: contato.id, senderType: 'Contact' }
      : {}),
    messageType: MESSAGE_TYPES.INCOMING,
    contentAttributes: {
      ...mensagem.contentAttributes,
      isUnsupported: true,
      unsupportedKind: 'unknown',
    },
  };
};
