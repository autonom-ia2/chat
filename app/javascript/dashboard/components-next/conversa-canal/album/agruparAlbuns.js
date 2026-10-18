// Álbum de fotos e vídeos (#1702). A Cloud API entrega uma mensagem por foto; no app,
// fotos e vídeos mandados juntos viram um balão-mosaico, com a legenda embaixo
// (AlbumDoWhatsapp). Só o álbum de verdade junta: foto mandada uma a uma fica solta.
// - Recebido: a Cloud entrega o "pai" do álbum como não suportada (unsupported_kind
//   'unknown') logo antes das fotos (22 de 22 em produção, out/2026, seguidos de 2+
//   mídias em até 30 s). O álbum começa nesse marcador, junta as fotos/vídeos do mesmo
//   cliente que vêm logo depois, até 30 s do marcador, e para no 1º que não entra. O
//   marcador some da lista. Sem marcador, cada foto fica solta.
// - Recebido pelo WAHA (#1709): o conector cria antes das mídias um marcador com
//   content_attributes.waha_album = { expected_images, expected_videos }. Com a flag
//   `whatsapp_rich_native` ele chega como atividade escondida (que guarda a chave);
//   sem ela, como recebida comum ("Mensagem de Álbum Recebida"). Nos dois casos o
//   marcador some e junta até a quantidade anunciada, do mesmo cliente, na mesma janela
//   de 30 s. Em grupo não junta: toda recebida vem com o contato do grupo, e a foto de
//   outro participante entraria no álbum (`whatsapp_api_group` da conversa, #1741).
// - Enviado pela plataforma: várias fotos do mesmo envio são criadas quase juntas
//   (até 3 s entre uma e outra) e seguem em álbum, como o app faz para quem manda junto.
import {
  ATTACHMENT_TYPES,
  MESSAGE_STATUS,
  MESSAGE_TYPES,
} from '../../message/constants';
import { continuaASequencia } from '../useSequenciaDaConversa';
import { eFigurinha } from '../figurinha';
import { eVisualizacaoUnica } from '../visualizacaoUnica';
import { deModeloOuCampanha } from '../encaminhar/selecaoParaEncaminhar';

// Itens a partir dos quais a sequência vira álbum.
export const MINIMO_DO_ALBUM = 2;
// Recebido: até quanto depois do marcador um item ainda é do álbum.
export const JANELA_DO_ALBUM_EM_SEGUNDOS = 30;
// Enviado: itens do mesmo envio nascem no mesmo segundo ou quase.
export const JANELA_DO_ENVIO_EM_SEGUNDOS = 3;
// Quantos quadros o mosaico mostra; o resto vira "+N" sobre o último.
export const QUADROS_DO_MOSAICO = 4;

const TIPOS_DO_ALBUM = [ATTACHMENT_TYPES.IMAGE, ATTACHMENT_TYPES.VIDEO];

const LADOS_DO_ALBUM = [MESSAGE_TYPES.INCOMING, MESSAGE_TYPES.OUTGOING];

// Só foto ou vídeo sozinho (com ou sem legenda), do cliente ou da empresa, sem resposta
// citada, que não falhou. Apagada pelo cliente fica solta, com o selo dela.
export const podeEntrarNoAlbum = mensagem => {
  const anexos = mensagem.attachments || [];
  const atributos = mensagem.contentAttributes || {};
  if (!LADOS_DO_ALBUM.includes(mensagem.messageType)) return false;
  if (anexos.length !== 1) return false;
  if (!TIPOS_DO_ALBUM.includes(anexos[0].fileType)) return false;
  // Figurinha fica sempre solta, como no app (é foto só no tipo do anexo).
  if (eFigurinha(anexos[0])) return false;
  // Visualização única e modelo/campanha ficam soltos, com o rótulo e as regras deles
  // (não se encaminham; no mosaico iriam junto).
  if (eVisualizacaoUnica(anexos[0]) || deModeloOuCampanha(mensagem)) {
    return false;
  }
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

// O "pai" do álbum que a Cloud entrega como não suportada, do cliente.
const eMarcadorDaCloud = mensagem =>
  mensagem?.messageType === MESSAGE_TYPES.INCOMING &&
  !mensagem.private &&
  mensagem.contentAttributes?.isUnsupported === true &&
  mensagem.contentAttributes?.unsupportedKind === 'unknown';

// O marcador do WAHA: recebida (sem a flag) ou atividade escondida (com ela).
const LADOS_DO_MARCADOR_DO_WAHA = [
  MESSAGE_TYPES.INCOMING,
  MESSAGE_TYPES.ACTIVITY,
];
const albumDoWaha = mensagem => {
  const album = mensagem?.contentAttributes?.wahaAlbum;
  return album && typeof album === 'object' ? album : null;
};

export const eMarcadorDoWaha = mensagem =>
  Boolean(albumDoWaha(mensagem)) &&
  !mensagem.private &&
  LADOS_DO_MARCADOR_DO_WAHA.includes(mensagem.messageType);

export const eMarcadorDeAlbum = mensagem =>
  eMarcadorDaCloud(mensagem) || eMarcadorDoWaha(mensagem);

// Quantas mídias o marcador do WAHA anuncia; 0 quando não diz (sem teto).
export const itensAnunciados = mensagem => {
  const album = albumDoWaha(mensagem) || {};
  const total =
    Number(album.expectedImages || 0) + Number(album.expectedVideos || 0);
  return Number.isFinite(total) && total > 0 ? total : 0;
};

// Com quem o item é comparado para seguir a sequência: o próprio marcador, ou, se ele
// é a atividade do WAHA (não tem lado de cliente), o 1º item, que precisa ser recebido.
const referenciaDoItem = (marcador, itens) =>
  marcador.messageType === MESSAGE_TYPES.ACTIVITY ? itens[0] : marcador;

const segueOMarcador = (marcador, itens, atual, fuso) => {
  const referencia = referenciaDoItem(marcador, itens);
  if (!referencia) return atual.messageType === MESSAGE_TYPES.INCOMING;
  return continuaASequencia(referencia, atual, fuso);
};

const dentroDaJanela = (desde, atual, janela) => {
  const espera = atual.createdAt - desde.createdAt;
  return espera >= 0 && espera <= janela;
};

// Recebido: do marcador em diante, enquanto o item entra, é da mesma pessoa e chega
// até 30 s depois do marcador. O do WAHA para na quantidade que anunciou.
const itensDoMarcador = (lista, inicio, { fuso, abreBloco }) => {
  const marcador = lista[inicio];
  const teto = itensAnunciados(marcador);
  const itens = [];
  for (let i = inicio + 1; i < lista.length; i += 1) {
    if (teto && itens.length >= teto) break;
    const atual = lista[i];
    const entra =
      podeEntrarNoAlbum(atual) &&
      !(itens.length && abreBloco(atual)) &&
      dentroDaJanela(marcador, atual, JANELA_DO_ALBUM_EM_SEGUNDOS) &&
      segueOMarcador(marcador, itens, atual, fuso);
    if (!entra) break;
    itens.push(atual);
  }
  return itens;
};

// Enviado: itens nossos seguidos, criados até 3 s um do outro, pela mesma pessoa.
const itensDoEnvio = (lista, inicio, { fuso, abreBloco }) => {
  const itens = [lista[inicio]];
  for (let i = inicio + 1; i < lista.length; i += 1) {
    const anterior = itens.at(-1);
    const atual = lista[i];
    const entra =
      atual.messageType === MESSAGE_TYPES.OUTGOING &&
      podeEntrarNoAlbum(atual) &&
      !abreBloco(atual) &&
      dentroDaJanela(anterior, atual, JANELA_DO_ENVIO_EM_SEGUNDOS) &&
      continuaASequencia(anterior, atual, fuso);
    if (!entra) break;
    itens.push(atual);
  }
  return itens;
};

const abreEnvio = mensagem =>
  mensagem.messageType === MESSAGE_TYPES.OUTGOING &&
  podeEntrarNoAlbum(mensagem);

// Devolve os álbuns (Map: id do 1º item -> mensagens, na ordem da conversa) e os ids
// dos marcadores que abriram álbum (somem da lista). `abreBloco` (opcional) diz quem
// não pode ficar escondido dentro do álbum anterior, como a 1ª não lida, que leva a
// etiqueta "não lidas" acima dela. `grupo`: conversa de grupo do WAHA, o marcador dele
// só some (não abre álbum).
const abreAlbum = (mensagem, grupo) =>
  grupo ? eMarcadorDaCloud(mensagem) : eMarcadorDeAlbum(mensagem);

export const agruparDaConversa = (
  lista,
  { fuso, abreBloco = () => false, grupo = false } = {}
) => {
  const albuns = new Map();
  const marcadores = new Set();
  const opcoes = { fuso, abreBloco };
  let i = 0;
  while (i < lista.length) {
    const mensagem = lista[i];
    let itens = [];
    if (abreAlbum(mensagem, grupo)) itens = itensDoMarcador(lista, i, opcoes);
    else if (abreEnvio(mensagem)) itens = itensDoEnvio(lista, i, opcoes);
    // Os itens vêm logo depois do marcador (ou a partir do próprio envio).
    const doMarcador = itens[0] !== mensagem;
    if (itens.length >= MINIMO_DO_ALBUM) {
      albuns.set(itens[0].id, itens);
      if (doMarcador) marcadores.add(mensagem.id);
      i += itens.length + (doMarcador ? 1 : 0);
    } else {
      // O marcador do WAHA é só sinal: some mesmo quando o álbum não se forma.
      if (eMarcadorDoWaha(mensagem)) marcadores.add(mensagem.id);
      i += 1;
    }
  }
  return { albuns, marcadores };
};

export const agruparAlbuns = (lista, opcoes) =>
  agruparDaConversa(lista, opcoes).albuns;

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
