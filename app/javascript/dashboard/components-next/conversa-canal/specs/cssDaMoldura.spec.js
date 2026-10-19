import { semUnidadeDaTela } from '../email/cssDaMoldura';

// #1884: na moldura, vh/vmin/vmax valem para a janela do painel (como no Gmail).
const TELA = { altura: 800, largura: 1000, combina: () => false };

describe('semUnidadeDaTela', () => {
  it('troca vh, dvh, vmin e vmax por px da janela do painel', () => {
    expect(semUnidadeDaTela('min-height: 100vh;', TELA)).toBe(
      'min-height: 800px;'
    );
    expect(semUnidadeDaTela('height: calc(50dvh - 20px);', TELA)).toBe(
      'height: calc(400px - 20px);'
    );
    expect(semUnidadeDaTela('margin-top: -10vh;', TELA)).toBe(
      'margin-top: -80px;'
    );
    expect(semUnidadeDaTela('width: 10vmin; height: .5vmax', TELA)).toBe(
      'width: 80px; height: 5px'
    );
  });

  it('pega número com expoente e as unidades de contêiner e de bloco', () => {
    expect(semUnidadeDaTela('height: 1e+06vh;', TELA)).toBe(
      'height: 8000000px;'
    );
    expect(semUnidadeDaTela('height: 100cqh; min-height: 50dvb', TELA)).toBe(
      'height: 800px; min-height: 400px'
    );
    expect(semUnidadeDaTela('padding: 10cqmax 10cqmin', TELA)).toBe(
      'padding: 100px 80px'
    );
  });

  it('não mexe em seletor, nome, texto entre aspas nem em outra unidade', () => {
    [
      '.vh { color: red; }',
      'h1, .col-2vh { width: 50vw; }',
      'p { font-family: "Fonte 100vh"; background: url("a100vh.png"); }',
      'td:nth-child(2) { padding: 10px 2em; }',
      'p { --a2vh: 1; }',
    ].forEach(css => expect(semUnidadeDaTela(css, TELA)).toBe(css));
  });
});
