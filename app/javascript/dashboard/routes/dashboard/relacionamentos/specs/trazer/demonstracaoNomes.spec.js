import { leituraDeExemplo, quemTrouxeNaDemo } from '../../demo/trazer';
const leitura = leituraDeExemplo('l1');

describe('nomes da planilha de exemplo são inventados', () => {
  const NOMES_QUE_PARECEM_REAIS = [
    'Marina Teixeira',
    'Otávio Lacerda',
    'Sofia Brandão',
    'Tadeu Marques',
    'Rita Nogueira',
    'Paulo Siqueira',
    'Helena Barreto',
    'Marina Alves',
  ];

  it('nenhum nome nem e-mail do demo é de gente comum', () => {
    const texto = JSON.stringify([leitura, quemTrouxeNaDemo()]);
    NOMES_QUE_PARECEM_REAIS.forEach(nome => {
      expect(texto).not.toContain(nome);
    });
    leitura.exemplos.forEach(e => {
      expect(e.email.endsWith('@exemplo.com.br')).toBe(true);
      expect(e.telefone.startsWith('+55 11 9')).toBe(true);
      expect(e.telefone.at(-5)).toBe('-');
      expect(e.telefone.slice(-4, -2)).toBe('00');
    });
  });
});
