// Image file before upload (#2908): reduced to e-mail size and converted to a format every e-mail
// program shows. Done in the browser, before the upload: a 4000 px phone photo of many MB never travels,
// and the browser already decodes what the person can see (WebP, BMP everywhere; HEIC and TIFF where the
// browser opens them, e.g. Safari). What it cannot open is refused with a plain message.
// Errors carry the same codes as the server (AssetsController), so one message table serves both.

export const MAX_IMAGE_WIDTH = 1200;
export const MAX_IMAGE_BYTES = 10 * 1024 * 1024;
export const TOO_LARGE = 'email_campaign.asset_too_large';
export const UNSUPPORTED = 'email_campaign.asset_unsupported_type';
export const UNREADABLE = 'email_campaign.asset_unreadable_image';
const JPEG_QUALITY = 0.85;

// Sent as they are when small enough: every e-mail program shows them.
const EMAIL_TYPES = new Set(['image/png', 'image/jpeg', 'image/gif']);
// Some systems hand these over without a type.
const IMAGE_EXTENSIONS = new Set([
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'bmp',
  'tif',
  'tiff',
  'heic',
  'heif',
  'avif',
]);

export class ImageFileError extends Error {
  constructor(code) {
    super(code);
    this.code = code;
  }
}

const extensionOf = name => {
  const dot = String(name || '').lastIndexOf('.');
  return dot === -1 ? '' : name.slice(dot + 1).toLowerCase();
};

const baseName = name => {
  const text = String(name || '');
  const dot = text.lastIndexOf('.');
  return dot > 0 ? text.slice(0, dot) : text;
};

export const isImageFile = file =>
  String(file?.type || '').startsWith('image/') ||
  IMAGE_EXTENSIONS.has(extensionOf(file?.name));

// Description of the image block: the file name without extension.
export const altFromFileName = name => baseName(name).trim() || 'Imagem';

// What to do with an image of this type and size: keep, or redraw as png/jpeg at a width.
export const planImage = ({ type, width, height, size }) => {
  if (type === 'image/gif') return { keep: size <= MAX_IMAGE_BYTES };
  const fits = width <= MAX_IMAGE_WIDTH;
  if (EMAIL_TYPES.has(type) && fits && size <= MAX_IMAGE_BYTES) {
    return { keep: true };
  }
  const scale = fits ? 1 : MAX_IMAGE_WIDTH / width;
  return {
    keep: false,
    width: Math.round(width * scale),
    height: Math.max(1, Math.round(height * scale)),
    // PNG keeps the transparency of a logo; anything else becomes a photo-sized JPEG.
    type: type === 'image/png' ? 'image/png' : 'image/jpeg',
  };
};

const decodeImage = async file => {
  try {
    return await createImageBitmap(file);
  } catch {
    throw new ImageFileError(UNREADABLE);
  }
};

const drawImage = (bitmap, { width, height, type }) => {
  const canvas = document.createElement('canvas');
  canvas.width = width;
  canvas.height = height;
  const context = canvas.getContext('2d');
  if (type === 'image/jpeg') {
    // JPEG has no transparency: a transparent area would turn black.
    context.fillStyle = '#ffffff';
    context.fillRect(0, 0, width, height);
  }
  context.drawImage(bitmap, 0, 0, width, height);
  return new Promise((resolve, reject) => {
    canvas.toBlob(
      blob => (blob ? resolve(blob) : reject(new ImageFileError(UNREADABLE))),
      type,
      JPEG_QUALITY
    );
  });
};

// -> File ready for EmailCampaignAssetsAPI.upload; throws ImageFileError.
export const prepareImageFile = async (
  file,
  { decode = decodeImage, draw = drawImage } = {}
) => {
  if (!isImageFile(file)) throw new ImageFileError(UNSUPPORTED);
  if (file.type === 'image/gif') {
    if (file.size > MAX_IMAGE_BYTES) throw new ImageFileError(TOO_LARGE);
    return file;
  }
  const bitmap = await decode(file);
  const plan = planImage({
    type: file.type,
    width: bitmap.width,
    height: bitmap.height,
    size: file.size,
  });
  if (plan.keep) {
    bitmap.close?.();
    return file;
  }
  const blob = await draw(bitmap, plan);
  bitmap.close?.();
  if (blob.size > MAX_IMAGE_BYTES) throw new ImageFileError(TOO_LARGE);
  const extension = plan.type === 'image/png' ? 'png' : 'jpg';
  return new File([blob], `${baseName(file.name) || 'imagem'}.${extension}`, {
    type: plan.type,
  });
};
