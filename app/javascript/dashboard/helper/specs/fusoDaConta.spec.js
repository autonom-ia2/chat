import { rotuloDoFuso } from '../fusoDaConta';

// #1456: o fuso como Configurações da conta o mostra (a lista de fusos do #954).
describe('rotuloDoFuso', () => {
  it('mostra o fuso como a lista de Configurações da conta', () => {
    expect(rotuloDoFuso('America/Sao_Paulo')).toBe('America/Sao Paulo');
    expect(rotuloDoFuso('America/Porto_Velho')).toBe('America/Porto Velho');
    expect(rotuloDoFuso('UTC')).toBe('UTC');
  });

  it('sem fuso, vazio', () => {
    expect(rotuloDoFuso(undefined)).toBe('');
  });
});
