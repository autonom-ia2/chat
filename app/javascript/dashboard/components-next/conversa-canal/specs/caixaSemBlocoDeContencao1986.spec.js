import { CAIXA_DE_RESPOSTA } from '../visualWhatsapp';

// #1986: filter, transform, backdrop-filter, perspective, contain e will-change
// num ancestral viram o bloco de contenção de todo position: fixed lá dentro. A
// barra e a caixa de resposta guardam os modais (modelos do WhatsApp, confirmação)
// e a área de soltar anexos; com um desses, eles ficam presos à caixa, não à tela.
const CRIAM_BLOCO_DE_CONTENCAO = [
  'filter',
  '[filter',
  'drop-shadow',
  'blur',
  'brightness',
  'contrast',
  'grayscale',
  'invert',
  'saturate',
  'sepia',
  'hue-rotate',
  'backdrop-',
  '[backdrop-filter',
  'transform',
  '[transform',
  'translate-',
  '-translate-',
  'scale-',
  'rotate-',
  '-rotate-',
  'skew-',
  'perspective',
  '[perspective',
  'contain-',
  '[contain',
  'will-change',
  '[will-change',
  '[translate',
  '[scale',
  '[rotate',
  'content-auto',
  '[content-visibility',
];

// Separa a classe nos ":" de fora do colchete: `dark:[filter:x]` vira
// ['dark', '[filter:x]']; o ":" de dentro do colchete fica onde está.
const partesDaClasse = classe => {
  const partes = [];
  let nivel = 0;
  let atual = '';
  [...classe].forEach(letra => {
    if (letra === '[') nivel += 1;
    if (letra === ']') nivel -= 1;
    if (letra === ':' && nivel === 0) {
      partes.push(atual);
      atual = '';
      return;
    }
    atual += letra;
  });
  return [...partes, atual];
};

const semImportante = classe =>
  classe.startsWith('!') ? classe.slice(1) : classe;

// Classes que valem para o próprio elemento, em qualquer estado (`dark:`,
// `max-md:`, `hover:` contam). As de seletor arbitrário (`[&_.left-wrap]:…`)
// valem para os filhos e ficam de fora.
const classesDoProprioElemento = classes =>
  classes
    .split(' ')
    .filter(Boolean)
    .map(partesDaClasse)
    .filter(partes => !partes.slice(0, -1).some(v => v.startsWith('[')))
    .map(partes => semImportante(partes[partes.length - 1]));

const quemPrende = classes =>
  classesDoProprioElemento(classes).filter(classe =>
    CRIAM_BLOCO_DE_CONTENCAO.some(prefixo => classe.startsWith(prefixo))
  );

describe('caixa de resposta da pele WhatsApp sem bloco de contenção (#1986)', () => {
  it('a caixa não usa filter, transform nem parecidos', () => {
    expect(quemPrende(CAIXA_DE_RESPOSTA.caixa)).toEqual([]);
  });

  it('a barra em volta da caixa também não', () => {
    expect(quemPrende(CAIXA_DE_RESPOSTA.barra)).toEqual([]);
  });

  it('nem as classes que entram na caixa por estado (resposta, nota, gravando)', () => {
    expect(quemPrende(CAIXA_DE_RESPOSTA.soResposta)).toEqual([]);
    expect(quemPrende(CAIXA_DE_RESPOSTA.nota)).toEqual([]);
    expect(quemPrende(CAIXA_DE_RESPOSTA.gravando)).toEqual([]);
  });

  it('a sombra fica em cada pílula, como box-shadow', () => {
    const sombra = 'shadow-[0_1px_0_rgba(0,0,0,0.08)]';
    const daCaixa = CAIXA_DE_RESPOSTA.caixa.split(' ');
    expect(daCaixa).toContain(`[&_.left-wrap]:${sombra}`);
    expect(daCaixa).toContain(`[&_.right-wrap]:${sombra}`);
    expect(CAIXA_DE_RESPOSTA.campo.split(' ')).toContain(sombra);
  });

  it('o guarda acusa o filter antigo, se ele voltar', () => {
    expect(
      quemPrende(
        'px-4 [filter:drop-shadow(0_1px_1px_rgba(0,0,0,0.08))] !transform'
      )
    ).toEqual([
      '[filter:drop-shadow(0_1px_1px_rgba(0,0,0,0.08))]',
      'transform',
    ]);
  });

  it('o guarda acusa também com variante de estado, não com seletor de filho', () => {
    expect(
      quemPrende(
        'dark:[filter:blur(1px)] max-md:!translate-y-1 [&_.left-wrap]:scale-95 max-md:[&_.left-wrap]:blur-sm'
      )
    ).toEqual(['[filter:blur(1px)]', 'translate-y-1']);
  });
});
