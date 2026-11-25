import { parse } from '@vue/compiler-sfc';

// Tipos de nó do compilador do Vue (`@vue/compiler-core`, NodeTypes).
const NodeTypes = { ELEMENT: 1, ATTRIBUTE: 6, DIRECTIVE: 7 };

// Piloto da conta 16: o `<span class="sr-only">(abre em nova aba)</span>` do link "Escolher quem
// recebe" não tinha ancestral posicionado. `.sr-only` é `position: absolute`; sem `relative` por
// perto ele se posiciona pelo documento (top ≈ 1064px), aumenta a altura rolável do <html> e a
// janela inteira rola além do app, mostrando fundo branco. Esta trava lê o template de cada
// componente do módulo: todo `sr-only` tem `relative` no elemento pai (o `<template>` não conta,
// pois não vira elemento), e todo `absolute` tem um ancestral posicionado no mesmo template.

const sources = import.meta.glob('../**/*.vue', {
  query: '?raw',
  import: 'default',
  eager: true,
});

const POSICIONADAS = ['relative', 'absolute', 'fixed', 'sticky'];

const classeEstatica = no =>
  no.props
    .filter(p => p.type === NodeTypes.ATTRIBUTE && p.name === 'class')
    .flatMap(p =>
      (p.value?.content || '').replaceAll('\n', ' ').split(' ').filter(Boolean)
    );

const classeDinamica = no =>
  no.props
    .filter(
      p =>
        p.type === NodeTypes.DIRECTIVE &&
        p.name === 'bind' &&
        p.arg?.content === 'class'
    )
    .map(p => p.exp?.content || '')
    .join(' ');

const temClasse = (no, classe) =>
  classeEstatica(no).includes(classe) ||
  classeDinamica(no).includes(`'${classe}'`);

const temClasseEstatica = (no, classe) => classeEstatica(no).includes(classe);

const ehElemento = no => no.type === NodeTypes.ELEMENT && no.tag !== 'template';

const percorrer = (no, ancestrais, visitar) => {
  (no.children || []).forEach(filho => {
    if (filho.type !== NodeTypes.ELEMENT) return;
    visitar(filho, ancestrais);
    const proximos = ehElemento(filho) ? [...ancestrais, filho] : ancestrais;
    percorrer(filho, proximos, visitar);
  });
};

const templateDe = fonte => parse(fonte).descriptor.template?.ast;

const violacoes = () => {
  const lista = [];
  Object.entries(sources).forEach(([caminho, fonte]) => {
    const template = templateDe(fonte);
    if (!template) return;
    percorrer(template, [], (no, ancestrais) => {
      const local = `${caminho}:${no.loc.start.line} <${no.tag}>`;
      const pai = ancestrais[ancestrais.length - 1];
      if (
        temClasse(no, 'sr-only') &&
        !(pai && temClasseEstatica(pai, 'relative'))
      ) {
        lista.push(`${local} sr-only sem pai relative`);
      }
      if (
        temClasse(no, 'absolute') &&
        !ancestrais.some(a => POSICIONADAS.some(c => temClasse(a, c)))
      ) {
        lista.push(`${local} absolute sem ancestral posicionado`);
      }
    });
  });
  return lista;
};

// Utilitários do Tailwind que criam `filter`, `backdrop-filter` ou `transform` (sem o prefixo de variante).
const CRIAM_CONTENCAO = [
  'filter',
  'blur',
  'brightness-',
  'contrast-',
  'drop-shadow',
  'grayscale',
  'hue-rotate-',
  'invert',
  'saturate-',
  'sepia',
  'backdrop-',
  'transform',
  'scale-',
  'rotate-',
  'translate-',
  'skew-',
];

const todasAsClasses = no =>
  [
    ...classeEstatica(no),
    ...classeDinamica(no).replaceAll("'", ' ').replaceAll('"', ' ').split(' '),
  ].filter(Boolean);

// `hover:-translate-y-1` → `translate-y-1`: sem a variante e sem o sinal de negativo.
const semVariante = classe => {
  const utilitario = classe.split(':').pop();
  return utilitario.startsWith('-') ? utilitario.slice(1) : utilitario;
};

const botoesDoCartaoComFiltro = () => {
  const lista = [];
  Object.entries(sources).forEach(([caminho, fonte]) => {
    const template = templateDe(fonte);
    if (!template) return;
    percorrer(template, [], no => {
      const classes = todasAsClasses(no);
      if (!classes.includes('after:absolute')) return;
      classes
        .map(semVariante)
        .filter(classe => CRIAM_CONTENCAO.some(p => classe.startsWith(p)))
        .forEach(classe =>
          lista.push(`${caminho}:${no.loc.start.line} <${no.tag}> ${classe}`)
        );
    });
  });
  return lista;
};

describe('Agentes · elementos posicionados ficam presos ao componente', () => {
  it('lê os templates do módulo', () => {
    expect(Object.keys(sources).length).toBeGreaterThan(40);
  });

  it('todo sr-only tem pai relative e todo absolute tem ancestral posicionado', () => {
    expect(violacoes()).toEqual([]);
  });

  // #3219 — o botão que se estica sobre o cartão (`after:absolute`) não pode ter filtro nem transformação, nem no
  // hover: `filter`/`transform` tornam o botão o bloco de contenção do `::after`, que encolhe para o tamanho do botão, e
  // o resto do cartão para de responder ao clique (aconteceu com `hover:brightness-110` no "Escolher").
  it('o botão que cobre o cartão não usa filtro nem transformação', () => {
    expect(botoesDoCartaoComFiltro()).toEqual([]);
  });
});
