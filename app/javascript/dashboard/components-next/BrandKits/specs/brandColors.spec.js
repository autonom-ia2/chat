import {
  contrast,
  isLightBand,
  normalizeHex,
  previewFontHref,
  textOn,
  withColor,
  fontStack,
} from '../brandColors';

describe('identity colors (#1076)', () => {
  it('measures WCAG contrast', () => {
    expect(contrast('#ffffff', '#000000')).toBeCloseTo(21, 1);
    expect(contrast('#4b5563', '#f4f4f4')).toBeGreaterThan(4.5);
  });

  it('warns when white (text or logo) gets lost on the top band', () => {
    expect(isLightBand('#0b243f')).toBe(false);
    expect(isLightBand('#f1eefe')).toBe(true);
    expect(isLightBand('')).toBe(false);
  });

  it('reads color codes the person types', () => {
    expect(normalizeHex('#ABC')).toBe('#aabbcc');
    expect(normalizeHex('0b243f')).toBe('#0b243f');
    expect(normalizeHex('azul')).toBeNull();
  });

  it('writes white on dark buttons and dark text on light ones', () => {
    expect(textOn('#c8102e')).toBe('#ffffff');
    expect(textOn('#ffe066')).toBe('#0a1628');
  });

  it('redraws the soft tint and the section background with the color they follow', () => {
    const light = {
      primary: '#c8102e',
      surface: '#ffffff',
      background: '#ffffff',
      tint: '#fae7ea',
    };

    const next = withColor(light, 'light', 'background', '#f4f6f8');

    expect(next).toMatchObject({ background: '#f4f6f8', surface: '#f4f6f8' });
    expect(next.tint).not.toBe(light.tint);
    expect(light.background).toBe('#ffffff');
  });

  it('keeps Arial behind the site font', () => {
    expect(fontStack('Roboto')).toBe("'Roboto', Arial, Helvetica, sans-serif");
    expect(fontStack(null)).toBe('Arial, Helvetica, sans-serif');
    expect(previewFontHref(['Open Sans', 'Open Sans', null])).toBe(
      'https://fonts.googleapis.com/css2?family=Open+Sans&display=swap'
    );
  });
});
