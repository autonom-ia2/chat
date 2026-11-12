// #2477 — no celular, o botão do menu (MobileSidebarLauncher, fixo em bottom-4 start-4, 56 px, z-40) fica por cima
// de toda tela. O layout reserva a faixa dele embaixo (Dashboard.vue), mas uma barra fixa na base da tela fica fora
// do fluxo da página e ocupa a mesma faixa. A regra, num lugar só: barra fixa embaixo começa depois do botão
// (ps-20, 80 px), como o BotaoGrande. Esta spec lê todas as telas e falha quando uma barra nova esquece o recuo.
const RAIZ = '../../../';
const telas = import.meta.glob('../../../**/*.vue', {
  query: '?raw',
  import: 'default',
  eager: true,
});

// Barras que cobrem a tela inteira com fundo (diálogo modal): o botão do menu fica por baixo do fundo, sem toque.
const COBREM_A_TELA = ['routes/dashboard/autonomia/agentes/components/AgenteGaveta.vue'];

const BARRAS = [
  { marca: 'fixed inset-x-0 bottom-0', recuos: ['ps-20', 'pl-20'] },
  {
    marca: 'max-md:fixed max-md:inset-x-0 max-md:bottom-0',
    recuos: ['max-md:ps-20'],
  },
];

const caminhoCurto = caminho => caminho.slice(RAIZ.length);

// A lista de classes que contém a marca: o trecho entre as aspas que a cercam.
const classesEmVolta = (fonte, posicao) => {
  const antes = fonte.slice(0, posicao);
  const abre = Math.max(antes.lastIndexOf('"'), antes.lastIndexOf("'"));
  const fecha = fonte.indexOf(fonte[abre], posicao);
  return fonte.slice(abre + 1, fecha).split(' ');
};

const barrasSemRecuo = () => {
  const faltando = [];
  Object.entries(telas).forEach(([caminho, fonte]) => {
    const tela = caminhoCurto(caminho);
    if (COBREM_A_TELA.includes(tela)) return;
    BARRAS.forEach(({ marca, recuos }) => {
      let posicao = fonte.indexOf(marca);
      while (posicao !== -1) {
        const classes = classesEmVolta(fonte, posicao);
        if (!recuos.some(recuo => classes.includes(recuo))) faltando.push(tela);
        posicao = fonte.indexOf(marca, posicao + marca.length);
      }
    });
  });
  return faltando;
};

describe('barras fixas embaixo no celular', () => {
  it('lê as telas do painel', () => {
    expect(Object.keys(telas).length).toBeGreaterThan(100);
  });

  it('as exceções ainda existem', () => {
    const existentes = Object.keys(telas).map(caminhoCurto);
    COBREM_A_TELA.forEach(tela => expect(existentes).toContain(tela));
  });

  it('toda barra fixa embaixo começa depois do botão do menu', () => {
    expect(barrasSemRecuo()).toEqual([]);
  });
});
