// Qual balão do Instagram Direct desenha cada mensagem (#2079), só com o que já chega
// gravado: anexos, `image_type` das mensagens compartilhadas e a marca de apagada.
// Devolve null quando o caso não tem balão próprio: a mensagem segue no balão de sempre.
import {
  ATTACHMENT_TYPES as A,
  CONTENT_TYPES,
} from 'dashboard/components-next/message/constants';

export const BALOES = {
  TEXTO: 'texto',
  MIDIA: 'midia',
  ALBUM: 'album',
  VOZ: 'voz',
  FIGURINHA: 'figurinha',
  REEL: 'reel',
  POST: 'post',
  STORY: 'story',
  APAGADA: 'apagada',
};

// Os tipos que o recebimento do Instagram grava em `content_attributes.image_type`.
const COMPARTILHADOS = {
  [A.IG_POST]: BALOES.POST,
  [A.STORY_MENTION]: BALOES.STORY,
  [A.IG_STORY]: BALOES.STORY,
  [A.IG_STORY_REPLY]: BALOES.STORY,
};
const MIDIAS = [A.IMAGE, A.VIDEO];

// Figurinha e GIF chegam como imagem servida pelo Giphy (o app os desenha soltos, sem balão).
// A mídia é servida da nossa cópia (#2113): o endereço de origem vem em `externalUrl`.
const HOSTS_DE_FIGURINHA = ['giphy.com'];
const ehFigurinha = anexo => {
  try {
    const { hostname } = new URL(anexo.externalUrl || anexo.dataUrl);
    return HOSTS_DE_FIGURINHA.some(
      host => hostname === host || hostname.endsWith(`.${host}`)
    );
  } catch {
    return false;
  }
};

export const balaoDoInstagram = mensagem => {
  const atributos = mensagem.contentAttributes || {};
  // Pesquisa de satisfação, opções e formulário de robô, chamada de vídeo: balão próprio de sempre.
  if (mensagem.contentType && mensagem.contentType !== CONTENT_TYPES.TEXT) {
    return null;
  }
  if (atributos.type === 'dyte') return null;
  // Mensagem rica (botão, opções…): o balão de sempre mostra o texto que o cliente recebeu.
  if (atributos.richMessage) return null;
  if (atributos.deleted) return BALOES.APAGADA;
  if (atributos.isUnsupported) return null;
  const compartilhado = COMPARTILHADOS[atributos.imageType];
  if (compartilhado) return compartilhado;

  const anexos = mensagem.attachments || [];
  if (!anexos.length) return mensagem.content ? BALOES.TEXTO : null;
  if (anexos.length > 1) {
    return anexos.every(anexo => MIDIAS.includes(anexo.fileType))
      ? BALOES.ALBUM
      : null;
  }
  const [anexo] = anexos;
  if (anexo.fileType === A.AUDIO) return BALOES.VOZ;
  if (anexo.fileType === A.IG_REEL) return BALOES.REEL;
  if (anexo.fileType === A.IMAGE && ehFigurinha(anexo)) return BALOES.FIGURINHA;
  if (MIDIAS.includes(anexo.fileType)) return BALOES.MIDIA;
  return null;
};
