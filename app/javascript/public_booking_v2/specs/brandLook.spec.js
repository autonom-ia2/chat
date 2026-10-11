import { mount } from '@vue/test-utils';
import ActionButton from '../components/ActionButton.vue';
import BrandHeader from '../components/BrandHeader.vue';
import {
  DARK_TEXT,
  DEFAULT_BRAND_COLOR,
  LIGHT_TEXT,
  applyBrandColor,
  brandTokens,
  contrastBetween,
  contrastWithWhite,
  logoAlignOf,
  textOnColor,
} from '../helpers/brand';

// Cor livre, contraste e logo da página pública (#1289).
const AA = 4.5;
const WHITE = '#ffffff';

// Uma grade de cores espalhada pelo cubo RGB inteiro (4.096 cores).
const STEPS = Array.from({ length: 16 }, (_, index) => index * 17);
const hex = value => value.toString(16).padStart(2, '0');
const GRID = STEPS.flatMap(r =>
  STEPS.flatMap(g => STEPS.map(b => `#${hex(r)}${hex(g)}${hex(b)}`))
);

describe('cor livre: texto claro ou escuro por cima da cor', () => {
  it('cor escura recebe texto branco; cor clara, texto preto', () => {
    expect(textOnColor('#0d2344')).toBe(LIGHT_TEXT);
    expect(textOnColor('#5b3fa8')).toBe(LIGHT_TEXT);
    expect(textOnColor('#ffe066')).toBe(DARK_TEXT);
    expect(textOnColor('#ffffff')).toBe(DARK_TEXT);
  });

  it('qualquer cor tem contraste AA no botão e na borda', () => {
    const failures = GRID.filter(color => {
      const { fill, on, ink } = brandTokens(color);
      return contrastBetween(fill, on) < AA || contrastBetween(ink, WHITE) < AA;
    });
    expect(GRID).toHaveLength(4096);
    expect(failures).toEqual([]);
  });

  it('o fundo é a cor que a pessoa escolheu, sem escurecer', () => {
    const tokens = brandTokens('#FFE066');
    expect(tokens.fill).toBe('#ffe066');
    expect(tokens.on).toBe(DARK_TEXT);
    expect(tokens.ink).not.toBe('#ffe066');
    expect(contrastWithWhite(tokens.ink)).toBeGreaterThanOrEqual(AA);
  });

  it('cor escura fica igual no fundo e na borda', () => {
    expect(brandTokens('#0B7A5A')).toEqual({
      fill: '#0b7a5a',
      ink: '#0b7a5a',
      on: LIGHT_TEXT,
    });
  });

  it('cor inválida usa a cor padrão nos três valores', () => {
    expect(brandTokens('red; background: url(x)')).toEqual({
      fill: DEFAULT_BRAND_COLOR,
      ink: DEFAULT_BRAND_COLOR,
      on: LIGHT_TEXT,
    });
  });

  it('aplica os três valores no elemento', () => {
    const root = document.createElement('div');
    applyBrandColor('#FFE066', root);
    expect(root.style.getPropertyValue('--brand-fill')).toBe('#ffe066');
    expect(root.style.getPropertyValue('--brand-on')).toBe(DARK_TEXT);
    expect(
      contrastWithWhite(root.style.getPropertyValue('--brand'))
    ).toBeGreaterThanOrEqual(AA);
  });

  it('o botão principal usa o fundo, o texto por cima e o contorno legível', () => {
    const classes = mount(ActionButton, {
      slots: { default: 'Confirmar' },
    }).classes();
    expect(classes).toEqual(
      expect.arrayContaining([
        'bg-[var(--brand-fill)]',
        'text-[var(--brand-on)]',
        'ring-[var(--brand)]',
      ])
    );
    expect(classes).not.toContain('text-white');
  });
});

describe('logo: lado e formato', () => {
  const header = brand =>
    mount(BrandHeader, {
      props: {
        page: {
          title: 'Conversa',
          agent_name: 'Camila',
          duration_minutes: 30,
          brand: { logo_url: 'https://cdn.exemplo.com/logo.png', ...brand },
        },
      },
    });

  it('valor desconhecido ou vazio cai na esquerda', () => {
    expect(logoAlignOf('center')).toBe('center');
    expect(logoAlignOf(undefined)).toBe('left');
    expect(logoAlignOf('top; x')).toBe('left');
  });

  it.each([
    [undefined, 'justify-start'],
    ['left', 'justify-start'],
    ['center', 'justify-center'],
    ['right', 'justify-end'],
    ['qualquer', 'justify-start'],
  ])('logo_align %s alinha com %s', (align, expected) => {
    const box = header({ logo_align: align }).find('[data-logo-box]');
    expect(box.classes()).toContain(expected);
  });

  it('a caixa limita altura e largura e a imagem cabe inteira, sem esticar nem cortar', () => {
    const wrapper = header({});
    const box = wrapper.find('[data-logo-box]');
    const image = box.find('img');
    // Limites: 56 px de altura e 192 px de largura. Uma logo deitada 4:1 fica com 48 px de altura, 20% a mais
    // que os 40 px de antes (#1289).
    expect(box.classes()).toEqual(expect.arrayContaining(['h-14', 'w-full']));
    expect(image.classes()).toEqual(
      expect.arrayContaining([
        'object-contain',
        'max-h-full',
        'max-w-[min(12rem,100%)]',
        'h-auto',
        'w-auto',
      ])
    );
    expect(image.classes()).not.toContain('object-cover');
  });

  it('sem logo não sobra caixa vazia; logo quebrada some', async () => {
    expect(header({ logo_url: null }).find('[data-logo-box]').exists()).toBe(
      false
    );
    const wrapper = header({});
    await wrapper.find('[data-logo-box] img').trigger('error');
    expect(wrapper.find('[data-logo-box]').exists()).toBe(false);
  });

  it('sem foto, a inicial usa a cor escolhida com o texto por cima', () => {
    const initial = header({}).find('span[aria-hidden="true"]');
    expect(initial.text()).toBe('C');
    expect(initial.classes()).toEqual(
      expect.arrayContaining([
        'bg-[var(--brand-fill)]',
        'text-[var(--brand-on)]',
      ])
    );
  });
});
