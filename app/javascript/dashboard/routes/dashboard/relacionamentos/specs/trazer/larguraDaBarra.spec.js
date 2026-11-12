import { larguraDaBarra } from '../../trazer/larguraDaBarra';

// A largura da barra de andamento sem `style` (#2894): um degrau de 5%, para baixo.
describe('larguraDaBarra', () => {
  it.each([
    [0, 'w-0'],
    [4, 'w-0'],
    [5, 'w-[5%]'],
    [40, 'w-[40%]'],
    [41, 'w-[40%]'],
    [99, 'w-[95%]'],
    [100, 'w-full'],
  ])('%s%% usa %s', (porcentagem, classe) => {
    expect(larguraDaBarra(porcentagem)).toBe(classe);
  });

  it('limita o que passa de 100 ou fica abaixo de 0 e aguenta lixo', () => {
    expect(larguraDaBarra(250)).toBe('w-full');
    expect(larguraDaBarra(-10)).toBe('w-0');
    expect(larguraDaBarra(undefined)).toBe('w-0');
    expect(larguraDaBarra('abc')).toBe('w-0');
  });
});
