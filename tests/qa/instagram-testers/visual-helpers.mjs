export const MINIMUM_TEXT_CONTRAST = 4.5;

export function primaryButtonCoverage(buttons, restricted) {
  if (!buttons.length)
    throw new Error(
      'No primary solid button found; action contract cannot be checked'
    );
  const enabledContrastTargets = buttons.filter(
    button => !button.disabled
  ).length;
  if (restricted && enabledContrastTargets)
    throw new Error('Restricted screen has an enabled primary action');
  if (!restricted && !enabledContrastTargets)
    throw new Error(
      'No enabled solid button found for contrast regression; coverage cannot be skipped'
    );
  return {
    restricted,
    primaryCount: buttons.length,
    enabledContrastTargets,
    disabledCount: buttons.length - enabledContrastTargets,
  };
}

function numericChannel(value, maximum) {
  const percentage = value.endsWith('%');
  const number = Number(percentage ? value.slice(0, -1) : value);
  const channel = percentage ? (number * maximum) / 100 : number;
  if (!value || !Number.isFinite(channel) || channel < 0 || channel > maximum)
    throw new Error(`Unsupported computed color channel: ${value}`);
  return channel;
}

// Chromium serializes these repo colors as rgb()/rgba(); unknown syntax fails.
export function parseComputedColor(value) {
  const start = value.indexOf('(');
  if (!['rgb', 'rgba'].includes(value.slice(0, start)) || !value.endsWith(')'))
    throw new Error(`Unsupported computed color: ${value}`);
  const parts = value
    .slice(start + 1, -1)
    .split(',')
    .join(' ')
    .split('/')
    .join(' ')
    .split(' ')
    .filter(Boolean);
  if (parts.length !== 3 && parts.length !== 4)
    throw new Error(`Unsupported computed color: ${value}`);
  return [
    ...parts.slice(0, 3).map(part => numericChannel(part, 255)),
    parts.length === 4 ? numericChannel(parts[3], 1) : 1,
  ];
}

export function compositeColor(foreground, background) {
  const alpha = foreground[3] + background[3] * (1 - foreground[3]);
  if (!alpha) return [0, 0, 0, 0];
  return [
    ...foreground
      .slice(0, 3)
      .map(
        (channel, index) =>
          (channel * foreground[3] +
            background[index] * background[3] * (1 - foreground[3])) /
          alpha
      ),
    alpha,
  ];
}

export function brightnessColor(color, filter) {
  if (filter === 'none') return color;
  if (!filter.startsWith('brightness(') || !filter.endsWith(')'))
    throw new Error(`Unsupported computed filter: ${filter}`);
  const raw = filter.slice('brightness('.length, -1);
  const amount = raw.endsWith('%')
    ? Number(raw.slice(0, -1)) / 100
    : Number(raw);
  if (!Number.isFinite(amount) || amount < 0)
    throw new Error(`Unsupported computed filter: ${filter}`);
  return [
    ...color.slice(0, 3).map(channel => Math.min(255, channel * amount)),
    color[3],
  ];
}

function luminance(color) {
  return color.slice(0, 3).reduce((sum, channel, index) => {
    const normalized = channel / 255;
    const linear =
      normalized <= 0.04045
        ? normalized / 12.92
        : ((normalized + 0.055) / 1.055) ** 2.4;
    return sum + linear * [0.2126, 0.7152, 0.0722][index];
  }, 0);
}

export function contrastRatio(foreground, background) {
  if (foreground[3] !== 1 || background[3] !== 1)
    throw new Error(
      'Contrast requires colors composited onto an opaque surface'
    );
  const first = luminance(foreground);
  const second = luminance(background);
  return (Math.max(first, second) + 0.05) / (Math.min(first, second) + 0.05);
}

// Called inside the real page, on the element that actually renders the text.
export function computedAppearance(element, pseudoElement = null) {
  const computed = window.getComputedStyle(element, pseudoElement);
  let foreground = parseComputedColor(computed.color);
  let background = [0, 0, 0, 0];
  const layers = [];
  if (pseudoElement) {
    foreground[3] *= Number(computed.opacity);
    foreground = brightnessColor(foreground, computed.filter);
  }
  let ancestor = element;
  while (ancestor) {
    const style = window.getComputedStyle(ancestor);
    if (style.backgroundImage !== 'none')
      throw new Error(
        'Computed contrast does not support background images/gradients'
      );
    const surface = parseComputedColor(style.backgroundColor);
    foreground = compositeColor(foreground, surface);
    background = compositeColor(background, surface);
    foreground = brightnessColor(foreground, style.filter);
    background = brightnessColor(background, style.filter);
    const opacity = Number(style.opacity);
    foreground[3] *= opacity;
    background[3] *= opacity;
    layers.push({
      tag: ancestor.tagName,
      background: style.backgroundColor,
      filter: style.filter,
      opacity,
    });
    ancestor = ancestor.parentElement;
  }
  return {
    text:
      pseudoElement === '::placeholder'
        ? element.getAttribute('placeholder')
        : element.textContent.trim(),
    color: computed.color,
    ...(pseudoElement
      ? { pseudoElement, pseudoOpacity: Number(computed.opacity) }
      : {}),
    foreground,
    background,
    contrast: contrastRatio(foreground, background),
    layers,
  };
}
