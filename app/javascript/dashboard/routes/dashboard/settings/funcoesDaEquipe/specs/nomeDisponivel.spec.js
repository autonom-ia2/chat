import { nomeEmUso, primeiroNomeLivre } from '../nomeDisponivel';

// #2308, especificação 5.B4: um nome por conta, sem diferenciar maiúsculas nem espaços.
const FUNCOES = [
  { id: 1, name: 'Atendente' },
  { id: 2, name: 'Vendedor 2' },
];

describe('nomeDisponivel', () => {
  it('nome em uso ignora maiúsculas, espaços e a própria função', () => {
    expect(nomeEmUso('  atendente ', FUNCOES)).toBe(true);
    expect(nomeEmUso('Atendente', FUNCOES, 1)).toBe(false);
    expect(nomeEmUso('Supervisor', FUNCOES)).toBe(false);
  });

  it('o primeiro nome livre conta a partir do nome sem o número', () => {
    expect(primeiroNomeLivre('Atendente', FUNCOES)).toBe('Atendente 2');
    expect(primeiroNomeLivre('Supervisor', FUNCOES)).toBe('Supervisor');
    expect(
      primeiroNomeLivre('Vendedor 2', [...FUNCOES, { name: 'Vendedor' }])
    ).toBe('Vendedor 3');
  });

  it('pula o nome que o servidor recusou (de uma integração)', () => {
    expect(primeiroNomeLivre('Atendente 2', FUNCOES, ['Atendente 2'])).toBe(
      'Atendente 3'
    );
  });
});
