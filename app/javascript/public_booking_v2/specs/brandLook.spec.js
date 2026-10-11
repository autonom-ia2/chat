import { mount } from '@vue/test-utils';
import ActionButton from '../components/ActionButton.vue';
import BrandHeader from '../components/BrandHeader.vue';
import {
  DARK_CARD,
  DARK_SURFACE,
  DARK_TEXT,
  DEFAULT_BRAND_COLOR,
  LIGHT_SURFACE,
  LIGHT_TEXT,
  LOGO_DARK_MODES,
  MIN_BUTTON_CONTRAST,
  applyBrandColor,
  brandTokens,
  contrastBetween,
  contrastWithWhite,
  logoAlignOf,
  logoDarkModeOf,
  readableBrandColorDark,
  textOnColor,
} from '../helpers/brand';

// Cor livre, contraste e logo da página pública (#1289), nos dois temas (#1295).
const AA = 4.5;
// As superfícies escuras em que a cor da marca vira texto ou borda: cartão, campo e caixa (assets/_booking-theme.scss;
// o theme.spec.js confere que DARK_SURFACE é a mais clara delas).
const DARK_SURFACES = [DARK_CARD, '#1e2127', '#21242b', DARK_SURFACE];
// As claras: cartão e campo (brancos) e o fundo do botão secundário com o mouse em cima.
const LIGHT_CARD = '#ffffff';
const LIGHT_SURFACES = [LIGHT_CARD, LIGHT_SURFACE];

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

  it('qualquer cor tem contraste AA no botão e na borda, no tema claro e no escuro', () => {
    const failures = GRID.filter(color => {
      const { fill, on, ink, inkDark, fillDark, onDark } = brandTokens(color);
      return (
        contrastBetween(fill, on) < AA ||
        contrastBetween(fillDark, onDark) < AA ||
        LIGHT_SURFACES.some(surface => contrastBetween(ink, surface) < AA) ||
        DARK_SURFACES.some(surface => contrastBetween(inkDark, surface) < AA)
      );
    });
    expect(GRID).toHaveLength(4096);
    expect(failures).toEqual([]);
  });

  // O botão principal é o elemento mais forte da tela. No escuro, o próprio fundo se separa do cartão por 3:1 ou
  // mais, em qualquer cor (cor escura é clareada).
  it('tema escuro: em qualquer cor, o fundo do botão principal tem 3:1 ou mais contra o cartão', () => {
    const failures = GRID.filter(
      color =>
        contrastBetween(brandTokens(color).fillDark, DARK_CARD) <
        MIN_BUTTON_CONTRAST
    );
    expect(failures).toEqual([]);
    // A regra age de verdade: muitas cores da grade são escuras demais como vieram.
    const lifted = GRID.filter(
      color => brandTokens(color).fillDark !== brandTokens(color).fill
    );
    expect(lifted.length).toBeGreaterThan(500);
    lifted.forEach(color =>
      expect(contrastBetween(color, DARK_CARD)).toBeLessThan(
        MIN_BUTTON_CONTRAST
      )
    );
  });

  // No claro, o fundo é sempre a cor que a pessoa escolheu. Cor clara (amarelo) não chega a 3:1 contra o cartão
  // branco: quem separa o botão do cartão, nesses casos, é o contorno na versão legível da cor. O teste confere as
  // duas coisas em separado: que o contorno existe no botão e que, toda vez que o fundo não basta, o contorno basta.
  it('tema claro: o fundo é a cor escolhida, e quando ela é clara o contorno separa o botão do cartão', () => {
    const needsRing = GRID.filter(
      color => contrastBetween(color, LIGHT_CARD) < MIN_BUTTON_CONTRAST
    );
    expect(needsRing.length).toBeGreaterThan(500);
    expect(needsRing).toContain('#ffff66');
    GRID.forEach(color => expect(brandTokens(color).fill).toBe(color));
    const failures = needsRing.filter(
      color =>
        contrastBetween(brandTokens(color).ink, LIGHT_CARD) <
        MIN_BUTTON_CONTRAST
    );
    expect(failures).toEqual([]);
    // O contorno é parte do botão principal, na cor legível do tema.
    expect(
      mount(ActionButton, { slots: { default: 'Confirmar' } }).classes()
    ).toEqual(
      expect.arrayContaining(['ring-1', 'ring-inset', 'ring-[var(--brand)]'])
    );
  });

  it('no escuro, cor escura vira um fundo mais claro do mesmo tom, com o texto que dá leitura', () => {
    const navy = brandTokens('#0D2344');
    expect(navy.fill).toBe('#0d2344');
    expect(navy.fillDark).not.toBe('#0d2344');
    expect(contrastBetween('#0d2344', DARK_CARD)).toBeLessThan(
      MIN_BUTTON_CONTRAST
    );
    expect(contrastBetween(navy.fillDark, DARK_CARD)).toBeGreaterThanOrEqual(
      MIN_BUTTON_CONTRAST
    );
    expect(contrastBetween(navy.fillDark, navy.onDark)).toBeGreaterThanOrEqual(
      AA
    );
    // Continua azul.
    const [r, g, b] = [1, 3, 5].map(at =>
      parseInt(navy.fillDark.slice(at, at + 2), 16)
    );
    expect(b).toBeGreaterThan(g);
    expect(g).toBeGreaterThan(r);

    // Cor que já se destaca do cartão escuro fica como a pessoa escolheu.
    expect(brandTokens('#FFE066')).toMatchObject({
      fillDark: '#ffe066',
      onDark: DARK_TEXT,
    });
    expect(brandTokens('#0B7A5A')).toMatchObject({
      fillDark: '#0b7a5a',
      onDark: LIGHT_TEXT,
    });
    // Preto: cinza com texto legível, nunca botão invisível.
    const black = brandTokens('#000000');
    expect(contrastBetween(black.fillDark, DARK_CARD)).toBeGreaterThanOrEqual(
      MIN_BUTTON_CONTRAST
    );
    expect(
      contrastBetween(black.fillDark, black.onDark)
    ).toBeGreaterThanOrEqual(AA);
  });

  it('no escuro a cor escura é clareada sem perder o tom; a clara fica como é', () => {
    const navy = readableBrandColorDark('#0D2344');
    expect(navy).not.toBe('#0d2344');
    expect(contrastBetween(navy, DARK_SURFACE)).toBeGreaterThanOrEqual(AA);
    // Continua azul: o canal azul segue o maior e o vermelho o menor.
    const [r, g, b] = [1, 3, 5].map(at => parseInt(navy.slice(at, at + 2), 16));
    expect(b).toBeGreaterThan(g);
    expect(g).toBeGreaterThan(r);

    expect(readableBrandColorDark('#FFE066')).toBe('#ffe066');
    expect(readableBrandColorDark('#000000')).not.toBe('#000000');
    expect(
      contrastBetween(readableBrandColorDark('#000000'), DARK_SURFACE)
    ).toBeGreaterThanOrEqual(AA);
  });

  it('o fundo é a cor que a pessoa escolheu, sem escurecer', () => {
    const tokens = brandTokens('#FFE066');
    expect(tokens.fill).toBe('#ffe066');
    expect(tokens.on).toBe(DARK_TEXT);
    expect(tokens.ink).not.toBe('#ffe066');
    expect(contrastWithWhite(tokens.ink)).toBeGreaterThanOrEqual(AA);
  });

  it('cor escura fica igual no fundo e na borda', () => {
    expect(brandTokens('#0B7A5A')).toMatchObject({
      fill: '#0b7a5a',
      ink: '#0b7a5a',
      on: LIGHT_TEXT,
    });
  });

  it('cor inválida usa a cor padrão em todos os valores', () => {
    const tokens = brandTokens('red; background: url(x)');
    expect(tokens).toEqual({
      fill: DEFAULT_BRAND_COLOR,
      ink: DEFAULT_BRAND_COLOR,
      inkDark: readableBrandColorDark(DEFAULT_BRAND_COLOR),
      on: LIGHT_TEXT,
      fillDark: brandTokens(DEFAULT_BRAND_COLOR).fillDark,
      onDark: LIGHT_TEXT,
    });
    expect(
      contrastBetween(tokens.inkDark, DARK_SURFACE)
    ).toBeGreaterThanOrEqual(AA);
  });

  it('aplica no elemento o fundo, o texto por cima e as duas versões legíveis; quem escolhe entre elas é o CSS', () => {
    const root = document.createElement('div');
    applyBrandColor('#FFE066', root);
    expect(root.style.getPropertyValue('--brand-fill-light')).toBe('#ffe066');
    expect(root.style.getPropertyValue('--brand-on-light')).toBe(DARK_TEXT);
    expect(root.style.getPropertyValue('--brand-fill-dark')).toBe('#ffe066');
    expect(root.style.getPropertyValue('--brand-on-dark')).toBe(DARK_TEXT);
    expect(
      contrastWithWhite(root.style.getPropertyValue('--brand-ink-light'))
    ).toBeGreaterThanOrEqual(AA);
    expect(root.style.getPropertyValue('--brand-ink-dark')).toBe('#ffe066');
    // `--brand`, `--brand-fill` e `--brand-on` não são gravados por script: vêm do tema
    // (assets/_booking-theme.scss).
    ['--brand', '--brand-fill', '--brand-on'].forEach(name =>
      expect(root.style.getPropertyValue(name)).toBe('')
    );

    applyBrandColor('#0D2344', root);
    expect(root.style.getPropertyValue('--brand-fill-light')).toBe('#0d2344');
    expect(root.style.getPropertyValue('--brand-fill-dark')).toBe(
      brandTokens('#0D2344').fillDark
    );
    expect(root.style.getPropertyValue('--brand-on-dark')).toBe(LIGHT_TEXT);
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

describe('logo por tema (#1295)', () => {
  const LOGO = 'https://cdn.exemplo.com/logo.png';
  const LOGO_DARK = 'https://cdn.exemplo.com/logo-escura.png';
  const LIGHT_ONLY = '[display:var(--bk-light-only,block)]';
  const DARK_ONLY = '[display:var(--bk-dark-only,none)]';
  const PLATE = ['bg-[var(--bk-plate)]', 'p-[var(--bk-plate-pad)]'];

  const header = brand =>
    mount(BrandHeader, {
      props: {
        page: {
          title: 'Conversa',
          agent_name: 'Camila',
          duration_minutes: 30,
          brand: { logo_url: LOGO, ...brand },
        },
      },
    });
  const logos = wrapper => wrapper.findAll('[data-logo-box] img');

  it('o modo sai do que o servidor manda; o que a página não conhece vira placa', () => {
    expect(logoDarkModeOf({ darkUrl: LOGO_DARK, source: 'generated' })).toBe(
      LOGO_DARK_MODES.OWN
    );
    expect(logoDarkModeOf({ darkUrl: LOGO_DARK, source: 'uploaded' })).toBe(
      LOGO_DARK_MODES.OWN
    );
    expect(logoDarkModeOf({ darkUrl: null, source: 'same' })).toBe(
      LOGO_DARK_MODES.SAME
    );
    [undefined, null, 'plate', 'generated', 'uploaded', 'qualquer'].forEach(
      source =>
        expect(logoDarkModeOf({ darkUrl: null, source })).toBe(
          LOGO_DARK_MODES.PLATE
        )
    );
  });

  it.each(['uploaded', 'generated'])(
    'com logo para o escuro (%s): as duas imagens, cada uma só no seu tema, sem placa',
    source => {
      const wrapper = header({
        logo_dark_url: LOGO_DARK,
        logo_dark_source: source,
      });
      const [light, dark] = logos(wrapper);

      expect(logos(wrapper)).toHaveLength(2);
      expect(light.attributes('src')).toBe(LOGO);
      expect(light.classes()).toContain(LIGHT_ONLY);
      expect(light.classes()).not.toContain(DARK_ONLY);
      expect(dark.attributes('src')).toBe(LOGO_DARK);
      expect(dark.classes()).toContain(DARK_ONLY);
      expect(dark.classes()).not.toContain(LIGHT_ONLY);
      [light, dark].forEach(image => {
        expect(image.classes()).toEqual(
          expect.arrayContaining(['object-contain', 'max-h-full'])
        );
        expect(image.classes()).not.toEqual(expect.arrayContaining(PLATE));
        expect(image.attributes('alt')).toBe(light.attributes('alt'));
      });
      expect(wrapper.find('[data-logo-box]').attributes('data-logo-dark')).toBe(
        'own'
      );
    }
  );

  it('logo que já se lê no escuro: uma imagem só, sempre à mostra, sem placa', () => {
    const wrapper = header({ logo_dark_source: 'same' });
    const [only] = logos(wrapper);

    expect(logos(wrapper)).toHaveLength(1);
    expect(only.attributes('src')).toBe(LOGO);
    expect(only.classes()).toContain('block');
    expect(only.classes()).not.toEqual(expect.arrayContaining(PLATE));
    expect(only.classes()).not.toContain(LIGHT_ONLY);
    expect(wrapper.find('[data-logo-box]').attributes('data-logo-dark')).toBe(
      'same'
    );
  });

  it.each([['plate'], [undefined], ['qualquer']])(
    'sem versão para o escuro (%s): a logo de sempre com a placa do tema',
    source => {
      const wrapper = header({ logo_dark_source: source });
      const [only] = logos(wrapper);

      expect(logos(wrapper)).toHaveLength(1);
      expect(only.attributes('src')).toBe(LOGO);
      expect(only.classes()).toEqual(
        expect.arrayContaining(['block', 'rounded-lg', ...PLATE])
      );
      expect(only.classes()).toEqual(
        expect.arrayContaining(['object-contain', 'max-h-full'])
      );
      expect(wrapper.find('[data-logo-box]').attributes('data-logo-dark')).toBe(
        'plate'
      );
    }
  );

  it('a imagem do escuro não carregou: cai na placa, nunca logo invisível', async () => {
    const wrapper = header({
      logo_dark_url: LOGO_DARK,
      logo_dark_source: 'generated',
    });
    await wrapper.find('[data-logo-for-dark]').trigger('error');

    expect(logos(wrapper)).toHaveLength(1);
    expect(logos(wrapper)[0].classes()).toEqual(expect.arrayContaining(PLATE));
    expect(wrapper.find('[data-logo-box]').exists()).toBe(true);

    // Trocaram a imagem: a nova ganha a chance de carregar.
    await wrapper.setProps({
      page: {
        title: 'Conversa',
        agent_name: 'Camila',
        brand: {
          logo_url: LOGO,
          logo_dark_url: 'https://cdn.exemplo.com/outra.png',
          logo_dark_source: 'uploaded',
        },
      },
    });
    expect(logos(wrapper)).toHaveLength(2);
  });

  it('endereço perigoso na logo do escuro é ignorado', () => {
    const wrapper = header({
      // eslint-disable-next-line no-script-url
      logo_dark_url: 'javascript:alert(1)',
      logo_dark_source: 'generated',
    });
    expect(logos(wrapper)).toHaveLength(1);
    expect(logos(wrapper)[0].classes()).toEqual(expect.arrayContaining(PLATE));
  });
});
