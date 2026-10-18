import {
  horaNoFuso,
  opcaoDaTela,
  periodoDoDia,
  primeiroNome,
  tempoDeEspera,
  vazioForcado,
} from '../telaInicial';

describe('telaInicial', () => {
  it('lê a opção da URL e ignora valor fora da lista', () => {
    expect(opcaoDaTela({ inicio: '2' })).toBe('2');
    expect(opcaoDaTela({ inicio: '9' })).toBeNull();
    expect(opcaoDaTela({})).toBeNull();
    expect(vazioForcado({ vazio: '1' })).toBe(true);
    expect(vazioForcado({})).toBe(false);
  });

  it('separa manhã, tarde e noite', () => {
    expect(periodoDoDia(4)).toBe('NOITE');
    expect(periodoDoDia(5)).toBe('MANHA');
    expect(periodoDoDia(12)).toBe('TARDE');
    expect(periodoDoDia(18)).toBe('NOITE');
  });

  it('usa o fuso da conta, não o do navegador', () => {
    const meioDiaUtc = new Date('2026-10-18T12:00:00Z');
    expect(horaNoFuso(meioDiaUtc, 'America/Sao_Paulo')).toBe(9);
    expect(horaNoFuso(meioDiaUtc, 'Asia/Tokyo')).toBe(21);
  });

  it('pega o primeiro nome', () => {
    expect(primeiroNome('  John Doe ')).toBe('John');
    expect(primeiroNome(undefined)).toBe('');
  });

  it('mede a espera na maior unidade inteira', () => {
    expect(tempoDeEspera(0, 30)).toEqual({ unidade: 'MINUTOS', valor: 1 });
    expect(tempoDeEspera(0, 45 * 60)).toEqual({
      unidade: 'MINUTOS',
      valor: 45,
    });
    expect(tempoDeEspera(0, 3 * 3600)).toEqual({ unidade: 'HORAS', valor: 3 });
    expect(tempoDeEspera(0, 50 * 3600)).toEqual({ unidade: 'DIAS', valor: 2 });
  });
});
