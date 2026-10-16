import {
  PAIS_PADRAO,
  exemploDoPais,
  formatarNoPais,
  paisesDoTelefone,
  separarTelefone,
  telefoneCompleto,
} from '../mais/telefoneDoPais';

describe('telefone do contato com país (#1702)', () => {
  it('lista de países com bandeira, nome e DDI; o botão mostra só bandeira e DDI', () => {
    const paises = paisesDoTelefone('pt-BR');
    const brasil = paises.find(pais => pais.value === 'BR');
    expect(brasil).toEqual({
      value: 'BR',
      label: '🇧🇷 Brasil (+55)',
      shortLabel: '🇧🇷 +55',
      searchLabel: 'Brasil',
    });
    expect(paises.length).toBeGreaterThan(200);
    expect(paises.find(pais => pais.value === 'US').searchLabel).toBe(
      'Estados Unidos'
    );
  });

  it('Brasil é o padrão', () => {
    expect(PAIS_PADRAO).toBe('BR');
  });

  it('formata enquanto digita, do jeito do país', () => {
    expect(formatarNoPais('11987654321', 'BR')).toBe('(11) 98765-4321');
    expect(formatarNoPais('4155550100', 'US')).toBe('(415) 555-0100');
    expect(formatarNoPais('', 'BR')).toBe('');
    expect(exemploDoPais('BR')).toBe('(11) 96123-4567');
  });

  it('número completo só quando existe no país escolhido', () => {
    expect(telefoneCompleto('11987654321', 'BR')).toBe('+5511987654321');
    expect(telefoneCompleto('1133334444', 'BR')).toBe('+551133334444');
    expect(telefoneCompleto('2025550123', 'US')).toBe('+12025550123');
    expect(telefoneCompleto('1198765', 'BR')).toBe('');
    expect(telefoneCompleto('11987654321', 'US')).toBe('');
    expect(telefoneCompleto('', 'BR')).toBe('');
  });

  it('número com + separa país e número; sem + não adivinha', () => {
    expect(separarTelefone('+5511987654321')).toEqual({
      pais: 'BR',
      digitos: '11987654321',
    });
    expect(separarTelefone('+351 912 345 678')).toEqual({
      pais: 'PT',
      digitos: '912345678',
    });
    expect(separarTelefone('(11) 98765-4321', 'PT')).toEqual({
      pais: 'PT',
      digitos: '11987654321',
    });
    expect(separarTelefone('')).toEqual({ pais: 'BR', digitos: '' });
  });
});
