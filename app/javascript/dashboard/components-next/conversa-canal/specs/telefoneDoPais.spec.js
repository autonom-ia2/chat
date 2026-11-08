import {
  PAIS_PADRAO,
  exemploDoPais,
  formatarNoPais,
  paisesDoTelefone,
  posicaoDepoisDosDigitos,
  separarTelefone,
  telefoneCompleto,
  telefoneLegivel,
  nomeOuTelefone,
  nomeEhTelefone,
  nomeDoContatoNaTela,
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
      cru: '',
    });
    expect(separarTelefone('+351 912 345 678')).toEqual({
      pais: 'PT',
      digitos: '912345678',
      cru: '',
    });
    expect(separarTelefone('(11) 98765-4321', 'PT')).toEqual({
      pais: 'PT',
      digitos: '11987654321',
      cru: '',
    });
    expect(separarTelefone('')).toEqual({ pais: 'BR', digitos: '', cru: '' });
  });

  it('com + e país ainda incerto (ou sem país, como +800): fica como está', () => {
    expect(separarTelefone('+', 'PT')).toEqual({
      pais: 'PT',
      digitos: '',
      cru: '+',
    });
    expect(separarTelefone('+1').cru).toBe('+1');
    expect(separarTelefone('+800 1234 5678').cru).toBe('+800 1234 5678');
    expect(separarTelefone('+55')).toEqual({
      pais: 'BR',
      digitos: '',
      cru: '',
    });
  });

  it('cursor volta para depois do mesmo dígito', () => {
    expect(posicaoDepoisDosDigitos('(11) 98765-4321', 2)).toBe(3);
    expect(posicaoDepoisDosDigitos('(11) 98765-4321', 7)).toBe(10);
    expect(posicaoDepoisDosDigitos('(11) 98765-4321', 0)).toBe(0);
    expect(posicaoDepoisDosDigitos('(11) 9', 9)).toBe(6);
  });
});

describe('telefone legível (#2202)', () => {
  it('formata o telefone gravado com o país', () => {
    expect(telefoneLegivel('+5541966665555')).toBe('+55 41 96666-5555');
    expect(telefoneLegivel('+14155550132')).toBe('+1 415 555 0132');
  });

  it('o que não é número volta como veio', () => {
    expect(telefoneLegivel('abc')).toBe('abc');
    expect(telefoneLegivel(null)).toBe('');
  });

  it('nome que é só o número vira o telefone legível', () => {
    expect(nomeOuTelefone('5511955554444', '+5511955554444')).toBe(
      '+55 11 95555-4444'
    );
    expect(nomeOuTelefone('Joana', '+5511955554444')).toBe('Joana');
    expect(nomeOuTelefone('+5511955554444', '+5511955554444')).toBe(
      '+55 11 95555-4444'
    );
  });
});

describe('nome que é só telefone (#2202)', () => {
  it.each(['+55 11 95555-4444', '5511955554444', '(11) 95555-4444'])(
    '%s é telefone',
    nome => expect(nomeEhTelefone(nome)).toBe(true)
  );
  it.each(['Maria', 'Loja 24 horas', '+1', '', null])('%s não é', nome =>
    expect(nomeEhTelefone(nome)).toBe(false)
  );
});

describe('nome do contato na tela (#2255)', () => {
  it('nome que é o próprio número sai legível, com o telefone em snake_case ou camelCase', () => {
    expect(
      nomeDoContatoNaTela({
        name: '5511955554444',
        phone_number: '+5511955554444',
      })
    ).toBe('+55 11 95555-4444');
    expect(
      nomeDoContatoNaTela({
        name: '+5511955554444',
        phoneNumber: '+5511955554444',
      })
    ).toBe('+55 11 95555-4444');
  });

  it('nome normal não muda; sem nome, o telefone legível; sem nada, vazio', () => {
    expect(
      nomeDoContatoNaTela({ name: 'Joana', phone_number: '+5511955554444' })
    ).toBe('Joana');
    expect(nomeDoContatoNaTela({ phone_number: '+5511955554444' })).toBe(
      '+55 11 95555-4444'
    );
    expect(nomeDoContatoNaTela(null)).toBe('');
  });
});
