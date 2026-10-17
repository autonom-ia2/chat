// Álbum de fotos e vídeos (#1702). A Cloud API entrega uma mensagem por foto; no app,
// fotos e vídeos mandados juntos pela mesma pessoa viram um balão-mosaico. Desde 2025 o
// app agrupa também com legenda: a legenda fica embaixo do mosaico (AlbumDoWhatsapp).
// A regra exata do WhatsApp não é pública: o app já exigiu 4 itens e desde dez/2024
// agrupa a partir de 2 (WABetaInfo, iOS 24.25.80). Ficamos com o observado em 2026.
import { ATTACHMENT_TYPES, MESSAGE_STATUS } from '../../message/constants';
import { continuaASequencia } from '../useSequenciaDaConversa';
import { eFigurinha } from '../figurinha';

// Itens a partir dos quais a sequência vira álbum.
export const MINIMO_DO_ALBUM = 2;
// Espera máxima entre um item e o seguinte. Itens mandados de uma vez chegam no
// mesmo segundo ou quase; vídeo grande demora um pouco mais para subir.
export const JANELA_DO_ALBUM_EM_SEGUNDOS = 30;
// Quantos quadros o mosaico mostra; o resto vira "+N" sobre o último.
export const QUADROS_DO_MOSAICO = 4;

const TIPOS_DO_ALBUM = [ATTACHMENT_TYPES.IMAGE, ATTACHMENT_TYPES.VIDEO];

// Só foto ou vídeo sozinho (com ou sem legenda), sem resposta citada, que não falhou.
// Apagada pelo cliente fica solta, com o selo dela.
export const podeEntrarNoAlbum = mensagem => {
  const anexos = mensagem.attachments || [];
  const atributos = mensagem.contentAttributes || {};
  if (anexos.length !== 1) return false;
  if (!TIPOS_DO_ALBUM.includes(anexos[0].fileType)) return false;
  // Figurinha fica sempre solta, como no app (é foto só no tipo do anexo).
  if (eFigurinha(anexos[0])) return false;
  if (mensagem.private || mensagem.status === MESSAGE_STATUS.FAILED) {
    return false;
  }
  return !(
    atributos.inReplyTo ||
    atributos.deleted ||
    atributos.deletedByContactAt ||
    atributos.isUnsupported ||
    atributos.imageType
  );
};

const seguidas = (anterior, atual, fuso) => {
  if (!podeEntrarNoAlbum(anterior) || !podeEntrarNoAlbum(atual)) return false;
  const espera = atual.createdAt - anterior.createdAt;
  if (espera < 0 || espera > JANELA_DO_ALBUM_EM_SEGUNDOS) return false;
  // Mesmo lado, mesma pessoa e mesmo dia: a regra de sequência da pele.
  return continuaASequencia(anterior, atual, fuso);
};

// Devolve um Map: id do 1º item -> mensagens do álbum, na ordem da conversa.
// `abreBloco` (opcional) diz quem não pode ficar escondido dentro do álbum anterior,
// como a 1ª não lida, que leva a etiqueta "não lidas" acima dela.
export const agruparAlbuns = (
  lista,
  { fuso, abreBloco = () => false } = {}
) => {
  const albuns = new Map();
  let bloco = [];
  const fechar = () => {
    if (bloco.length >= MINIMO_DO_ALBUM) albuns.set(bloco[0].id, bloco);
    bloco = [];
  };
  lista.forEach((mensagem, i) => {
    const anterior = lista[i - 1];
    const junta =
      anterior && !abreBloco(mensagem) && seguidas(anterior, mensagem, fuso);
    if (!junta) fechar();
    if (podeEntrarNoAlbum(mensagem)) bloco.push(mensagem);
  });
  fechar();
  return albuns;
};

// Do menos para o mais adiantado: o álbum mostra o tique do item mais atrasado.
const ORDEM_DOS_TIQUES = [
  MESSAGE_STATUS.PROGRESS,
  MESSAGE_STATUS.SENT,
  MESSAGE_STATUS.DELIVERED,
  MESSAGE_STATUS.READ,
];

export const tiqueDoAlbum = itens =>
  itens
    .map(item => item.status)
    .reduce(
      (menor, status) =>
        ORDEM_DOS_TIQUES.indexOf(status) < ORDEM_DOS_TIQUES.indexOf(menor)
          ? status
          : menor,
      itens[0]?.status
    );

// Legendas do álbum, na ordem dos itens (normalmente só uma).
export const legendasDoAlbum = itens =>
  itens
    .filter(item => item.content?.trim())
    .map(item => ({ id: item.id, texto: item.content }));

// Reações de todos os itens juntas, para o selo do álbum.
export const atributosDoAlbum = itens => ({
  ...(itens[0]?.contentAttributes || {}),
  reactions: itens.flatMap(item =>
    Array.isArray(item.contentAttributes?.reactions)
      ? item.contentAttributes.reactions
      : []
  ),
});

// Quadros visíveis e quantos ficam escondidos atrás do "+N" do último.
export const quadrosDoMosaico = itens => {
  const quadros = itens.slice(0, QUADROS_DO_MOSAICO);
  const escondidos =
    itens.length > QUADROS_DO_MOSAICO
      ? itens.length - (QUADROS_DO_MOSAICO - 1)
      : 0;
  return { quadros, escondidos };
};
