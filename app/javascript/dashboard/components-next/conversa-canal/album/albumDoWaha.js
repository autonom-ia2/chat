// Álbum anunciado pelo WAHA (#1831). O conector do WhatsApp Híbrido cria, antes das
// fotos, uma mensagem-marcador recebida com content_attributes.waha_album =
// { expected_images, expected_videos }. Com a flag do #1741 o marcador é uma atividade
// escondida (c2y_hidden); sem ela, uma mensagem recebida comum. Nos dois formatos ele
// abre o álbum como o marcador da Cloud, com uma diferença: diz quantas fotos e vídeos
// virão, e a grade já nasce do tamanho certo. A caixa híbrida que recebe pela Cloud
// segue a regra da Cloud (sem contagem).
import { MESSAGE_TYPES } from '../../message/constants';

const TIPOS_DO_MARCADOR = [MESSAGE_TYPES.INCOMING, MESSAGE_TYPES.ACTIVITY];

// Teto de cada contagem, igual ao do conector do Híbrido (album.rb): inteiro de 0 a 100.
export const MAXIMO_DO_ALBUM = 100;

// Contagem ausente vale 0; fora de inteiro de 0 a 100 (texto, fração, negativa, acima do
// teto) invalida o anúncio inteiro.
const contagemValida = valor => {
  if (valor === undefined || valor === null) return 0;
  return Number.isInteger(valor) && valor >= 0 && valor <= MAXIMO_DO_ALBUM
    ? valor
    : null;
};

const anuncioDe = mensagem => {
  const album = mensagem?.contentAttributes?.wahaAlbum;
  return album && typeof album === 'object' ? album : null;
};

// Quantas fotos e vídeos o marcador anuncia, ou null quando não há álbum: sem a chave,
// contagem inválida ou soma 0.
export const contagemDoWaha = mensagem => {
  const album = anuncioDe(mensagem);
  if (!album) return null;
  const fotos = contagemValida(album.expectedImages);
  const videos = contagemValida(album.expectedVideos);
  if (fotos === null || videos === null) return null;
  const total = fotos + videos;
  return total > 0 ? total : null;
};

// Tem a marca do WAHA (waha_album), válida ou não. Quando não abre álbum, some mesmo
// assim: é só sinal do conector.
export const temMarcaDoWaha = mensagem =>
  TIPOS_DO_MARCADOR.includes(mensagem?.messageType) &&
  !mensagem.private &&
  anuncioDe(mensagem) !== null;

export const eMarcadorDoWaha = mensagem =>
  temMarcaDoWaha(mensagem) && contagemDoWaha(mensagem) !== null;

// O marcador precisa de remetente para a sequência saber de quem são as fotos. O
// Híbrido garante que ele vem; sem ele, não há álbum (por segurança).
export const temRemetente = mensagem =>
  Boolean(mensagem?.senderId || mensagem?.sender);

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
