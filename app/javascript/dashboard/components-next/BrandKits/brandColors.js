// Color math of the visual identity screens (#1076): WCAG contrast for the warnings and the live
// preview of a color change. The server (BrandKits::EmailPalettes / BrandKits::Color) proposes and
// validates the palettes; this file only redraws what the person is changing. Plain string math.
export const WHITE = '#ffffff';
export const FALLBACK_STACK = 'Arial, Helvetica, sans-serif';
export const MODES = ['light', 'dark'];
const LIGHT_TINT = 0.12;
const DARK_TINT = 0.16;
const NON_TEXT_CONTRAST = 3;

const channels = hex =>
  [1, 3, 5].map(index => parseInt(hex.slice(index, index + 2), 16));

export const isHex = value =>
  typeof value === 'string' &&
  value.length === 7 &&
  value.startsWith('#') &&
  [...value.slice(1).toLowerCase()].every(char =>
    '0123456789abcdef'.includes(char)
  );

// '#abc' or 'abc' or '#AABBCC' → '#aabbcc'; anything else → null.
export const normalizeHex = value => {
  const digits = String(value || '')
    .trim()
    .replace('#', '')
    .toLowerCase();
  const full =
    digits.length === 3 ? [...digits].map(c => c + c).join('') : digits;
  const hex = `#${full}`;
  return isHex(hex) ? hex : null;
};

export const luminance = hex => {
  const [red, green, blue] = channels(hex).map(channel => {
    const value = channel / 255;
    return value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * red + 0.7152 * green + 0.0722 * blue;
};

export const contrast = (first, second) => {
  const [light, dark] = [luminance(first), luminance(second)].sort(
    (a, b) => b - a
  );
  return (light + 0.05) / (dark + 0.05);
};

// White text or a white logo gets lost on the top band below 3:1.
export const isLightBand = band =>
  isHex(band) && contrast(WHITE, band) < NON_TEXT_CONTRAST;

export const textOn = background =>
  contrast(WHITE, background) >= 4.5 ? WHITE : '#0a1628';

export const composite = (front, back, alpha) => {
  const backChannels = channels(back);
  const mixed = channels(front).map((channel, index) =>
    Math.round(channel * alpha + backChannels[index] * (1 - alpha))
  );
  return `#${mixed.map(channel => channel.toString(16).padStart(2, '0')).join('')}`;
};

// A color change redraws the roles that follow it: the soft tint follows the buttons and the
// background (surface), and "Fundo" is both the e-mail and the section background.
export const withColor = (palette, mode, role, hex) => {
  const next = { ...palette, [role]: hex };
  if (role === 'background') next.surface = hex;
  if (['primary', 'background'].includes(role)) {
    next.tint = composite(
      next.primary,
      next.surface,
      mode === 'dark' ? DARK_TINT : LIGHT_TINT
    );
  }
  return next;
};

export const fontStack = family =>
  family ? `'${family}', ${FALLBACK_STACK}` : FALLBACK_STACK;

// Preview only: the Google Fonts stylesheet for the families being shown (the server stores the
// link it fills from the same catalog when the kit is saved).
export const previewFontHref = families => {
  const names = [...new Set(families.filter(Boolean))];
  if (!names.length) return '';
  const query = names
    .map(name => `family=${name.split(' ').join('+')}`)
    .join('&');
  return `https://fonts.googleapis.com/css2?${query}&display=swap`;
};

// 'light' when the opaque pixels of the logo are mostly light (a white logo), 'dark' otherwise,
// null when the image cannot be read (another host without CORS, still loading).
export const logoTone = url =>
  new Promise(resolve => {
    if (!url) {
      resolve(null);
      return;
    }
    const image = new Image();
    image.crossOrigin = 'anonymous';
    image.onerror = () => resolve(null);
    image.onload = () => {
      try {
        const size = 32;
        const canvas = document.createElement('canvas');
        canvas.width = size;
        canvas.height = size;
        const context = canvas.getContext('2d');
        context.drawImage(image, 0, 0, size, size);
        const { data } = context.getImageData(0, 0, size, size);
        let sum = 0;
        let count = 0;
        let seeThrough = 0;
        for (let index = 0; index < data.length; index += 4) {
          if (data[index + 3] <= 128) seeThrough += 1;
          else {
            sum += (data[index] + data[index + 1] + data[index + 2]) / 3;
            count += 1;
          }
        }
        // An opaque logo brings its own background: readable on any band.
        if (!count || !seeThrough) resolve(null);
        else resolve(sum / count > 200 ? 'light' : 'dark');
      } catch {
        resolve(null);
      }
    };
    image.src = url;
  });
