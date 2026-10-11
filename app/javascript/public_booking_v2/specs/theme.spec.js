import { readFileSync, readdirSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';
import { colors } from '../../../../theme/colors';
import { DARK_SURFACE, LIGHT_SURFACE, contrastBetween } from '../helpers/brand';

// Tema claro e escuro da página pública (#1295): as cores ficam num arquivo só, o tema vem do aparelho por CSS (sem
// script) e a prévia do painel força um tema com `data-booking-theme`. Este teste lê os arquivos de verdade.
const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const repo = join(root, '..', '..', '..');
const read = (...parts) => readFileSync(join(...parts), 'utf8');

const themeSheet = read(root, 'assets', '_booking-theme.scss');
const pageSheet = read(root, 'assets', 'tailwind.scss');
const panelSheet = read(
  root,
  '..',
  'dashboard',
  'assets',
  'scss',
  '_woot.scss'
);
const layout = read(
  repo,
  'app',
  'views',
  'public_booking',
  'pages',
  'show_v2.html.erb'
);

// As variáveis de um `@mixin` do arquivo de cores: { '--bk-card': '255 255 255', ... }.
const mixin = name => {
  const lines = themeSheet.split('\n');
  const start = lines.indexOf(`@mixin ${name} {`);
  const end = lines.indexOf('}', start);
  return Object.fromEntries(
    lines
      .slice(start + 1, end)
      .map(line => line.trim())
      .filter(line => line.startsWith('--'))
      .map(line => {
        const [key, ...value] = line.split(':');
        return [key, value.join(':').trim().replace(';', '')];
      })
  );
};

const LIGHT = mixin('booking-light');
const DARK = mixin('booking-dark');
const toHex = triple =>
  `#${triple
    .split(' ')
    .map(value => Number(value).toString(16).padStart(2, '0'))
    .join('')}`;
const hexOf = (theme, token) => toHex(theme[`--bk-${token}`]);

const SURFACES = ['card', 'field', 'inset'];
const TEXTS = ['strong', 'body', 'medium', 'soft'];
const AA = 4.5;

const vueFiles = [
  'App.vue',
  ...readdirSync(join(root, 'components'))
    .filter(name => name.endsWith('.vue'))
    .map(name => `components/${name}`),
];
const FIXED_COLORS = [
  'slate-',
  'gray-',
  'yellow-',
  'red-',
  'green-',
  'amber-',
  'blue-',
  'bg-white',
  'text-white',
  'bg-black',
  'text-black',
];

describe('cores da página: um arquivo, dois temas', () => {
  it('os dois temas têm exatamente as mesmas variáveis', () => {
    expect(Object.keys(DARK).sort()).toEqual(Object.keys(LIGHT).sort());
    expect(Object.keys(LIGHT).length).toBeGreaterThan(20);
  });

  it('toda classe `bk-*` do Tailwind tem valor nos dois temas, e vice-versa', () => {
    const tokens = Object.keys(colors.bk).map(key => `--bk-${key}`);
    tokens.forEach(token => {
      expect(LIGHT[token], token).toBeTruthy();
      expect(DARK[token], token).toBeTruthy();
      expect(colors.bk[token.replace('--bk-', '')]).toBe(
        `rgb(var(${token}) / <alpha-value>)`
      );
    });
    const colorVars = Object.keys(LIGHT).filter(
      key => LIGHT[key].split(' ').length === 3
    );
    expect(colorVars.sort()).toEqual(tokens.sort());
  });

  it('o tema claro continua com as cores que a página já tinha', () => {
    expect(hexOf(LIGHT, 'page')).toBe('#e0e1e6');
    expect(hexOf(LIGHT, 'card')).toBe('#ffffff');
    expect(hexOf(LIGHT, 'inset')).toBe('#f0f0f3');
    expect(hexOf(LIGHT, 'strong')).toBe('#111113');
    expect(hexOf(LIGHT, 'body')).toBe('#272a2d');
    expect(hexOf(LIGHT, 'medium')).toBe('#5a6169');
    expect(hexOf(LIGHT, 'soft')).toBe('#60646c');
    expect(hexOf(LIGHT, 'line')).toBe('#cdced6');
    expect(hexOf(LIGHT, 'warn')).toBe('#fffab8');
    expect(hexOf(LIGHT, 'danger-text')).toBe('#ce2c31');
    expect(LIGHT['--bk-plate']).toBe('transparent');
    expect(LIGHT['--bk-plate-pad']).toBe('0px');
  });

  it.each([
    ['claro', LIGHT],
    ['escuro', DARK],
  ])('tema %s: todo texto tem contraste AA em toda superfície', (_, theme) => {
    const failures = [];
    SURFACES.forEach(surface =>
      TEXTS.forEach(text => {
        const ratio = contrastBetween(
          hexOf(theme, text),
          hexOf(theme, surface)
        );
        if (ratio < AA) failures.push(`${text} sobre ${surface}: ${ratio}`);
      })
    );
    [
      ['warn-ink', 'warn'],
      ['danger-ink', 'danger'],
      ['ok-ink', 'ok'],
      ['danger-text', 'card'],
      ['soft', 'chip'],
      ['medium', 'page'],
    ].forEach(([text, surface]) => {
      const ratio = contrastBetween(hexOf(theme, text), hexOf(theme, surface));
      if (ratio < AA) failures.push(`${text} sobre ${surface}: ${ratio}`);
    });
    expect(failures).toEqual([]);
  });

  it('no escuro o cartão se destaca do fundo e o campo do cartão', () => {
    const luminance = token => contrastBetween(hexOf(DARK, token), '#000000');
    expect(luminance('card')).toBeGreaterThan(luminance('page'));
    expect(luminance('field')).toBeGreaterThan(luminance('card'));
    expect(luminance('inset')).toBeGreaterThanOrEqual(luminance('field'));
    expect(DARK['--bk-plate']).toBe('#ffffff');
    expect(DARK['--bk-plate-pad']).not.toBe('0px');
  });

  it('as superfícies usadas na conta da cor da marca são as do arquivo de cores', () => {
    expect(LIGHT_SURFACE).toBe(hexOf(LIGHT, 'inset'));
    expect(DARK_SURFACE).toBe(hexOf(DARK, 'inset'));
    // A mais escura do claro e a mais clara do escuro: se a cor passa nelas, passa nas outras.
    SURFACES.forEach(surface =>
      expect(contrastBetween(LIGHT_SURFACE, '#000000')).toBeLessThanOrEqual(
        contrastBetween(hexOf(LIGHT, surface), '#000000')
      )
    );
    SURFACES.forEach(surface =>
      expect(contrastBetween(DARK_SURFACE, '#000000')).toBeGreaterThanOrEqual(
        contrastBetween(hexOf(DARK, surface), '#000000')
      )
    );
  });

  it('cada tema escolhe a versão legível da cor da marca e qual logo aparece', () => {
    expect(LIGHT['--brand'].startsWith('var(--brand-ink-light,')).toBe(true);
    expect(DARK['--brand'].startsWith('var(--brand-ink-dark,')).toBe(true);
    expect([LIGHT['--bk-light-only'], LIGHT['--bk-dark-only']]).toEqual([
      'block',
      'none',
    ]);
    expect([DARK['--bk-light-only'], DARK['--bk-dark-only']]).toEqual([
      'none',
      'block',
    ]);
    expect(LIGHT['color-scheme']).toBeUndefined();
    expect(themeSheet).toContain('color-scheme: light;');
    expect(themeSheet).toContain('color-scheme: dark;');
  });
});

describe('o tema vem do aparelho, sem script', () => {
  it('a folha da página liga o claro por padrão e o escuro pelo aparelho', () => {
    const light = pageSheet.indexOf(':root {\n  @include booking-light;');
    const media = pageSheet.indexOf('@media (prefers-color-scheme: dark) {');
    const dark = pageSheet.indexOf('@include booking-dark;');
    expect(light).toBeGreaterThan(-1);
    expect(media).toBeGreaterThan(light);
    expect(dark).toBeGreaterThan(media);
    expect(pageSheet).toContain("@import 'booking-theme';");
    expect(pageSheet).toContain('background-color: rgb(var(--bk-page));');
  });

  it('o layout avisa o navegador dos dois temas antes de o CSS chegar', () => {
    expect(layout).toContain(
      '<meta name="color-scheme" content="light dark" />'
    );
    // Nenhum script decide tema: o único <script> do layout é a configuração global.
    expect(layout.split('<script').length - 1).toBe(1);
    expect(layout.includes('prefers-color-scheme')).toBe(false);
    expect(layout.includes('data-booking-theme')).toBe(false);
  });

  it('nenhum arquivo da página lê o tema por JavaScript para pintar a tela', () => {
    const scripts = [
      ...vueFiles,
      'helpers/brand.js',
      'composables/useBookingFlow.js',
      // Única exceção: o quadro do hCaptcha vem de outro site, não enxerga as cores da página e só aceita o tema
      // como parâmetro, lido uma vez ao montar.
    ].filter(file => file !== 'components/CaptchaField.vue');
    scripts.forEach(file => {
      const source = read(root, file);
      expect(source.includes('matchMedia'), file).toBe(false);
      expect(source.includes('data-booking-theme'), file).toBe(false);
    });
  });

  it('um pedaço da tela pode forçar o tema (a prévia do painel)', () => {
    expect(themeSheet).toContain(
      "[data-booking-theme='light'] {\n  @include booking-light;\n}"
    );
    expect(themeSheet).toContain(
      "[data-booking-theme='dark'] {\n  @include booking-dark;\n}"
    );
    // O painel importa só as cores e o seletor que força: o tema do aparelho não muda o painel.
    expect(panelSheet).toContain(
      "@import '../../../public_booking_v2/assets/booking-theme';"
    );
    expect(themeSheet.includes(':root')).toBe(false);
    expect(themeSheet.includes('prefers-color-scheme')).toBe(false);
  });
});

describe('componentes usam as cores do tema', () => {
  it.each(vueFiles)(
    '%s não tem cor fixa (slate, white, yellow, red...)',
    file => {
      const source = read(root, file);
      FIXED_COLORS.forEach(fragment => {
        expect(source.includes(fragment), `${file}: ${fragment}`).toBe(false);
      });
    }
  );

  it('as telas usam os tokens: fundo, cartão, texto e avisos', () => {
    expect(read(root, 'App.vue')).toContain('bg-bk-page');
    expect(read(root, 'components', 'PageCard.vue')).toContain(
      'border-bk-line bg-bk-card'
    );
    expect(read(root, 'components', 'TextField.vue')).toContain('bg-bk-field');
    expect(read(root, 'components', 'FormFooter.vue')).toContain('bg-bk-warn');
    expect(read(root, 'components', 'ManageError.vue')).toContain(
      'bg-bk-danger'
    );
    expect(read(root, 'components', 'ManageMeeting.vue')).toContain(
      'bg-bk-ok text-bk-ok-ink'
    );
  });
});
