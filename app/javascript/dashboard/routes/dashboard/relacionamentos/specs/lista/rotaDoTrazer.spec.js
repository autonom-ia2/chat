import { rotaDoTrazer } from '../../lista/rotaDoTrazer';

// #2947 — "Trazer minha lista" só lê do servidor quando a E3 (#2896) entrar. Até
// lá, fora da demonstração o botão não pode levar a uma tela que recusa tudo.
describe('rotaDoTrazer', () => {
  it('fora da demonstração leva à importação de contatos que já funciona', () => {
    expect(rotaDoTrazer(null)).toBe('contacts_import_journey');
    expect(rotaDoTrazer(undefined)).toBe('contacts_import_journey');
  });

  it('na demonstração leva à tela nova', () => {
    expect(rotaDoTrazer('cheio')).toBe('relacionamentos_trazer');
    expect(rotaDoTrazer('vazio')).toBe('relacionamentos_trazer');
  });
});
