import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { mount } from '@vue/test-utils';
import Button from '../Button.vue';

// Contraste do botão cheio (#2218): texto x fundo em cada cor, nos dois temas,
// parado e com o cursor em cima. Os valores saem dos tokens reais do painel.
const AA_TEXTO_NORMAL = 4.5;
const BRANCO = [255, 255, 255];
const SCSS = resolve(__dirname, '../../../assets/scss/_next-colors.scss');

const lerTokens = linhas => {
  const tokens = {};
  linhas.forEach(linha => {
    const texto = linha.trim();
    if (!texto.startsWith('--') || !texto.endsWith(';')) return;
    const [nome, valor] = texto.slice(2, -1).split(':');
    const partes = valor.trim().split(' ').map(Number);
    if (partes.length !== 3 || partes.some(Number.isNaN)) return;
    tokens[nome.trim()] = partes;
  });
  return tokens;
};

const temas = () => {
  const linhas = readFileSync(SCSS, 'utf8').split('\n');
  const inicioEscuro = linhas.findIndex(l => l.trim() === '.dark {');
  if (inicioEscuro < 0) throw new Error('bloco .dark não achado no SCSS');
  const claro = lerTokens(linhas.slice(0, inicioEscuro));
  return {
    claro,
    escuro: { ...claro, ...lerTokens(linhas.slice(inicioEscuro)) },
  };
};

const luminancia = rgb => {
  const [r, g, b] = rgb.map(v => {
    const s = v / 255;
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
};

const contraste = (a, b) => {
  const [claro, escuro] = [luminancia(a), luminancia(b)].sort((x, y) => y - x);
  return (claro + 0.05) / (escuro + 0.05);
};

// Ordem de precedência no Tailwind: base < dark: < hover < dark:hover.
const PRECEDENCIA = {
  claro: {
    parado: [''],
    hover: ['', 'hover:enabled:'],
    foco: ['', 'focus-visible:'],
  },
  escuro: {
    parado: ['', 'dark:'],
    hover: ['', 'dark:', 'hover:enabled:', 'dark:hover:enabled:'],
    foco: ['', 'dark:', 'focus-visible:', 'dark:focus-visible:'],
  },
};

// Cor da classe vencedora; null quando ela não é um token sólido (ex.: alpha).
const corVencedora = (classes, prefixos, tokens) => {
  const vencedora = prefixos
    .map(prefixo =>
      classes.find(
        c => c.startsWith(prefixo) && !c.slice(prefixo.length).includes(':')
      )
    )
    .filter(Boolean)
    .pop();
  if (!vencedora) return null;
  const nome = vencedora.slice(vencedora.lastIndexOf('-n-') + 3);
  if (vencedora.endsWith('-white')) return BRANCO;
  if (!vencedora.includes('-n-')) return null;
  return tokens[nome] || null;
};

const parDoEstado = (classes, estado, tema, tokens) => {
  const camadas = PRECEDENCIA[tema][estado];
  const fundo = corVencedora(
    classes,
    camadas.map(c => `${c}bg-`),
    tokens
  );
  const texto = corVencedora(
    classes.filter(c => c.endsWith('-white') || c.includes('text-n-')),
    PRECEDENCIA[tema].parado.map(c => `${c}text-`),
    tokens
  );
  return [fundo, texto];
};

describe('Button cheio: contraste AA do texto', () => {
  const tokensPorTema = temas();
  const CORES = ['blue', 'ruby', 'teal', 'amber', 'slate'];
  const ESTADOS = [
    ['parado', 'parado'],
    ['com o cursor em cima', 'hover'],
    ['com foco do teclado', 'foco'],
  ];
  // O cinza usa fundo translúcido (n-alpha-2) no hover e no foco do tema claro.
  const TRANSLUCIDO_NO_CLARO = ['slate'];

  CORES.forEach(nomeDaCor => {
    const wrapper = mount(Button, {
      props: { label: 'Salvar', color: nomeDaCor },
    });
    const classes = wrapper.get('button').classes();

    ['claro', 'escuro'].forEach(tema => {
      ESTADOS.forEach(([rotulo, estado]) => {
        const [fundo, texto] = parDoEstado(
          classes,
          estado,
          tema,
          tokensPorTema[tema]
        );
        // Fora isso, a cor tem de vir de um token do painel (nada de hex solto).
        const translucido =
          tema === 'claro' &&
          estado !== 'parado' &&
          TRANSLUCIDO_NO_CLARO.includes(nomeDaCor);
        if (translucido) return;

        it(`${nomeDaCor}, tema ${tema}, ${rotulo}: passa de 4,5:1`, () => {
          expect(fundo).toBeTruthy();
          expect(texto).toBeTruthy();
          expect(contraste(fundo, texto)).toBeGreaterThanOrEqual(
            AA_TEXTO_NORMAL
          );
        });
      });
    });
  });
});
