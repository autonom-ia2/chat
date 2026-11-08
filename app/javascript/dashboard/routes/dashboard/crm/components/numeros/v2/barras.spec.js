import { inicioDe, larguraDe } from './barras';

// Barras de CRM › Números (#1897): sem estilo em linha, a largura e a marca de
// "hoje" andam em degraus fixos de 5% com classes do Tailwind.
describe('barras', () => {
  it('arredonda a largura para o degrau de 5% mais perto', () => {
    expect(larguraDe(0)).toBe('w-0');
    expect(larguraDe(2)).toBe('w-0');
    expect(larguraDe(3)).toBe('w-[5%]');
    expect(larguraDe(67)).toBe('w-[65%]');
    expect(larguraDe(68)).toBe('w-[70%]');
    expect(larguraDe(100)).toBe('w-full');
  });

  it('não passa de 0 a 100 nem quebra com valor vazio', () => {
    expect(larguraDe(-10)).toBe('w-0');
    expect(larguraDe(140)).toBe('w-full');
    expect(larguraDe(null)).toBe('w-0');
    expect(larguraDe(undefined)).toBe('w-0');
  });

  it('a marca de hoje usa o início na mesma escada', () => {
    expect(inicioDe(0)).toBe('start-0');
    expect(inicioDe(61)).toBe('start-[60%]');
    expect(inicioDe(100)).toBe('start-full');
  });
});
