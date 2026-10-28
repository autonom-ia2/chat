// Anúncios da Meta (#2198): foto e vídeo do anúncio. O que o painel aceita do celular e o formato de cada mídia,
// para a prévia mostrar como ela fica em cada lugar (feed, Stories e Reels).

const MB = 1024 * 1024;

// Tipos e tamanhos aceitos na hora de escolher. A Meta aceita mais; aqui fica o que o celular gera e o que cabe no
// envio pelo painel.
export const MEDIA_LIMITS = {
  image: {
    types: ['image/jpeg', 'image/png'],
    maxBytes: 30 * MB,
    maxLabel: '30 MB',
  },
  video: {
    types: ['video/mp4', 'video/quicktime'],
    maxBytes: 1024 * MB,
    maxLabel: '1 GB',
    maxSeconds: 60,
  },
};

// Largura ÷ altura. Vertical (9:16) preenche Stories e Reels; 4:5 é o feed alto; quadrada (1:1) é o feed comum.
export const formatoDaMidia = ({ width, height }) => {
  if (!width || !height) return 'SQUARE';
  const ratio = width / height;
  if (ratio < 0.7) return 'VERTICAL';
  if (ratio < 0.9) return 'PORTRAIT';
  if (ratio <= 1.1) return 'SQUARE';
  return 'LANDSCAPE';
};

export const MEDIA_ACCEPT = [
  ...MEDIA_LIMITS.image.types,
  ...MEDIA_LIMITS.video.types,
].join(',');

// Carrossel: de 2 a 10 cartões (child_attachments). Só no anúncio que leva ao WhatsApp ou ao site: com Messenger e
// Instagram Direct a doc da Meta não confirma.
export const CAROUSEL_MAX = 10;
export const CAROUSEL_DESTINATIONS = ['WHATSAPP', 'WEBSITE'];

// Largura, altura e duração lidas do próprio arquivo, no navegador, antes de qualquer envio.
const readImage = url =>
  new Promise((resolve, reject) => {
    const image = new Image();
    image.onload = () =>
      resolve({ width: image.naturalWidth, height: image.naturalHeight });
    image.onerror = reject;
    image.src = url;
  });

// Vídeo: lê as medidas e tira a capa (o quadro de 0,1 s) num canvas.
const POSTER_AT = 0.1;
const posterOf = video => {
  const canvas = document.createElement('canvas');
  canvas.width = video.videoWidth;
  canvas.height = video.videoHeight;
  canvas.getContext('2d').drawImage(video, 0, 0);
  return canvas.toDataURL('image/jpeg', 0.8);
};
const readVideo = url =>
  new Promise((resolve, reject) => {
    const video = document.createElement('video');
    video.preload = 'auto';
    video.muted = true;
    video.playsInline = true;
    video.onloadedmetadata = () => {
      video.currentTime = Math.min(POSTER_AT, video.duration || 0);
    };
    video.onseeked = () =>
      resolve({
        width: video.videoWidth,
        height: video.videoHeight,
        duration: video.duration,
        poster: posterOf(video),
      });
    video.onerror = reject;
    video.src = url;
  });

const kindOf = file => {
  if (MEDIA_LIMITS.image.types.includes(file.type)) return 'image';
  if (MEDIA_LIMITS.video.types.includes(file.type)) return 'video';
  return null;
};

// O arquivo escolhido vira a mídia do anúncio: { kind, url, poster, width, height, duration, source: 'upload',
// file_name }. Recusa com o motivo em `error.code` (TYPE, IMAGE_SIZE, VIDEO_SIZE, VIDEO_LONG, READ) e `error.max`.
const refuse = (code, max) => Object.assign(new Error(code), { code, max });
export const lerMidia = async file => {
  const kind = kindOf(file);
  if (!kind) throw refuse('TYPE');
  const limits = MEDIA_LIMITS[kind];
  if (file.size > limits.maxBytes) {
    throw refuse(
      kind === 'image' ? 'IMAGE_SIZE' : 'VIDEO_SIZE',
      limits.maxLabel
    );
  }
  const url = URL.createObjectURL(file);
  let size;
  try {
    size = await (kind === 'image' ? readImage(url) : readVideo(url));
  } catch {
    URL.revokeObjectURL(url);
    throw refuse('READ');
  }
  if (kind === 'video' && size.duration > limits.maxSeconds) {
    URL.revokeObjectURL(url);
    throw refuse('VIDEO_LONG');
  }
  return { kind, url, ...size, source: 'upload', file_name: file.name };
};

// A capa do vídeo (o data URL JPEG que a tela tirou) como arquivo, para subir junto com o vídeo.
export const capaEmArquivo = poster => {
  const [, base64 = ''] = String(poster || '').split(',');
  const binary = atob(base64);
  const bytes = Uint8Array.from(binary, char => char.charCodeAt(0));
  return new File([bytes], 'capa.jpg', { type: 'image/jpeg' });
};

// A URL local de uma mídia mandada do celular deixa de valer quando ela sai da tela.
export const soltarMidia = media => {
  if (media?.source === 'upload') URL.revokeObjectURL(media.url);
};
