// WCAG 2.x relative luminance and contrast ratio for #rrggbb colors (#1081).
const channel = hex => {
  const value = parseInt(hex, 16) / 255;
  return value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
};

const luminance = color => {
  const hex = color.slice(1);
  const [r, g, b] = [0, 2, 4].map(start =>
    channel(hex.slice(start, start + 2))
  );
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
};

export const contrast = (a, b) => {
  const [light, dark] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (light + 0.05) / (dark + 0.05);
};
