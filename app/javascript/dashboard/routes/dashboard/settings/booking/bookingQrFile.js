import QRCode from 'qrcode';
import slugify from '@sindresorhus/slugify';

// QR code para baixar (#1290): o da tela serve para a câmera de quem está na
// frente; este vai para cartaz, cardápio, vitrine e post. Por isso é maior, com
// margem de silêncio de 4 módulos e correção de erro Q (25%), que aguenta
// impressão ruim e dobra de papel sem deixar o desenho denso demais.
export const QR_PRINT_SIZE = 1024;
const QR_PRINT_OPTIONS = {
  margin: 4,
  errorCorrectionLevel: 'Q',
  color: { dark: '#000000', light: '#ffffff' },
};
const FALLBACK_NAME = 'code';

// `qr-<nome da página em minúsculas com hífens>.<ext>`. Nome vazio ou só com
// símbolos vira `qr-code`.
export const qrFileName = (name, extension) =>
  `qr-${slugify(name || '') || FALLBACK_NAME}.${extension}`;

export const qrPngBlob = async url => {
  const canvas = await QRCode.toCanvas(url, {
    ...QR_PRINT_OPTIONS,
    width: QR_PRINT_SIZE,
  });
  const blob = await new Promise(resolve => {
    canvas.toBlob(resolve, 'image/png');
  });
  if (!blob) throw new Error('qr_png_empty');
  return blob;
};

// Vetor: a gráfica amplia sem perder nitidez.
export const qrSvgBlob = async url => {
  const svg = await QRCode.toString(url, { ...QR_PRINT_OPTIONS, type: 'svg' });
  return new Blob([svg], { type: 'image/svg+xml' });
};

export const QR_FORMATS = {
  png: { extension: 'png', build: qrPngBlob },
  svg: { extension: 'svg', build: qrSvgBlob },
};

// Navegador sem o atributo `download` (alguns navegadores dentro de aplicativo)
// abriria a imagem por cima do painel em vez de baixar.
const canDownloadFiles = () => 'download' in document.createElement('a');

const downloadBlobUrl = (blobUrl, fileName) => {
  const link = document.createElement('a');
  link.href = blobUrl;
  link.download = fileName;
  link.rel = 'noopener';
  document.body.appendChild(link);
  try {
    link.click();
  } finally {
    link.remove();
  }
};

// Devolve se o navegador aceitou o pedido de download. Quando não aceita, quem
// chamou mostra o link para abrir a imagem e salvar por lá.
export const saveBlobUrl = (blobUrl, fileName) => {
  if (!canDownloadFiles()) return false;
  try {
    downloadBlobUrl(blobUrl, fileName);
    return true;
  } catch {
    return false;
  }
};
