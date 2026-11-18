import {
  OUTRA_SEGURADORA,
  bonusDigitado,
  cepComMascara,
  chaveDaSeguradora,
  dadosParaCorrigir,
  faltasDoFormulario,
  formularioDoSeguro,
  placaComMascara,
  primeiroCampoQueFalta,
  temNascimentoESexo,
} from '../../carteira/formularioDoSeguro';
import { aoMeioDia } from './apoio';

// O formulário "Corrigir o seguro" (#2897): do seguro para os campos, o que
// falta e o que mudou. Só é pedido o que o servidor pede.
const SEGURADORAS = ['Horizonte Seguros', 'Seguradora Atlântica'];
const SEGURO = {
  tipo: 'residencial',
  seguradora: 'Horizonte Seguros',
  numero: 'HZ-002318',
  comeca: aoMeioDia(2025, 11, 29),
  termina: aoMeioDia(2026, 11, 29),
  valor: 640,
  bem: 'Apartamento',
};
const inicial = () => formularioDoSeguro(SEGURO, SEGURADORAS);
const com = mudancas => ({ ...inicial(), ...mudancas });

describe('do seguro para os campos', () => {
  it('preenche cada campo do jeito de digitar', () => {
    expect(inicial()).toEqual({
      tipo: 'residencial',
      seguradora: 'Horizonte Seguros',
      outraSeguradora: '',
      numero: 'HZ-002318',
      comeca: '2025-11-29',
      termina: '2026-11-29',
      valor: '640,00',
      bem: 'Apartamento',
      nascimento: '',
      sexo: '',
      cep: '',
      placa: '',
      bonus: '',
    });
  });

  it('seguradora fora da lista vira "Outra", com o nome escrito', () => {
    expect(formularioDoSeguro(SEGURO, ['Seguradora Atlântica'])).toMatchObject({
      seguradora: OUTRA_SEGURADORA,
      outraSeguradora: 'Horizonte Seguros',
    });
  });

  it('acha a seguradora na lista mesmo quando o seguro traz outra grafia', () => {
    const lista = ['Seguradora Atlântica S.A.', 'Horizonte Seguros'];
    const seguro = { ...SEGURO, seguradora: 'seguradora atlantica sa' };
    const aberto = formularioDoSeguro(seguro, lista);

    expect(aberto).toMatchObject({
      seguradora: 'Seguradora Atlântica S.A.',
      outraSeguradora: '',
    });
    // Sem mexer em nada, a grafia diferente não conta como mudança.
    expect(dadosParaCorrigir(aberto, aberto)).toEqual({});
  });

  it.each([
    ['Seguradora Atlântica S.A.', 'seguradoraatlanticasa'],
    ['seguradora atlantica sa', 'seguradoraatlanticasa'],
    ['  HORIZONTE-Seguros 24h ', 'horizonteseguros24h'],
    ['Serra Azul & Cia. (Proteção)', 'serraazulciaprotecao'],
    [null, ''],
  ])('compara %s como o servidor: %s', (nome, chave) => {
    expect(chaveDaSeguradora(nome)).toBe(chave);
  });

  it('o que o seguro não tem fica em branco', () => {
    const vazio = { ...SEGURO, numero: null, comeca: null, valor: null };

    expect(
      formularioDoSeguro({ ...vazio, bem: null }, SEGURADORAS)
    ).toMatchObject({ numero: '', comeca: '', valor: '', bem: '' });
  });

  it('não altera o seguro que recebeu', () => {
    const copia = { ...SEGURO };

    formularioDoSeguro(SEGURO, SEGURADORAS);

    expect(SEGURO).toEqual(copia);
  });
});

describe('o que falta', () => {
  it('no formulário como abriu não falta nada', () => {
    expect(faltasDoFormulario(inicial(), inicial())).toEqual({});
  });

  it('início, valor e bem podem ficar em branco', () => {
    const emBranco = com({ comeca: '', valor: '', bem: '' });

    expect(faltasDoFormulario(emBranco, inicial())).toEqual({});
  });

  it('"Outra" seguradora pede o nome', () => {
    const semNome = com({ seguradora: OUTRA_SEGURADORA, outraSeguradora: ' ' });

    expect(faltasDoFormulario(semNome, inicial())).toEqual({
      outraSeguradora: 'OUTRA_SEGURADORA',
    });
  });

  it('o número só é pedido de quem já tinha número', () => {
    const semNumero = formularioDoSeguro(
      { ...SEGURO, numero: null },
      SEGURADORAS
    );

    expect(faltasDoFormulario(com({ numero: '  ' }), inicial())).toEqual({
      numero: 'NUMERO',
    });
    expect(faltasDoFormulario(semNumero, semNumero)).toEqual({});
  });

  it('a data em que termina é obrigatória e tem de existir', () => {
    expect(faltasDoFormulario(com({ termina: '' }), inicial())).toEqual({
      termina: 'TERMINA',
    });
    expect(
      faltasDoFormulario(com({ termina: '2026-02-30' }), inicial())
    ).toEqual({ termina: 'TERMINA' });
  });

  it('data de início que não existe é avisada no campo dela', () => {
    expect(
      faltasDoFormulario(com({ comeca: '2025-02-30' }), inicial())
    ).toEqual({ comeca: 'COMECA' });
  });

  it('o seguro não pode terminar antes de começar', () => {
    const invertido = com({ comeca: '2026-11-29', termina: '2026-11-28' });
    const noMesmoDia = com({ comeca: '2026-11-29', termina: '2026-11-29' });

    expect(faltasDoFormulario(invertido, inicial())).toEqual({
      termina: 'TERMINA_ANTES',
    });
    expect(faltasDoFormulario(noMesmoDia, inicial())).toEqual({});
  });

  it.each(['abc', '12,345', '1,2,3'])('o valor %s não é um valor', valor => {
    expect(faltasDoFormulario(com({ valor }), inicial())).toEqual({
      valor: 'VALOR',
    });
  });

  it('o foco vai para o primeiro campo que falta, na ordem da tela', () => {
    expect(primeiroCampoQueFalta({ valor: 'VALOR', numero: 'NUMERO' })).toBe(
      'numero'
    );
    expect(primeiroCampoQueFalta({ termina: 'TERMINA' })).toBe('termina');
    expect(primeiroCampoQueFalta({})).toBeNull();
  });
});

describe('o que mudou, pronto para a fonte', () => {
  it('sem mudança, não há o que mandar', () => {
    expect(dadosParaCorrigir(inicial(), inicial())).toEqual({});
  });

  it('o mesmo valor escrito de outro jeito não é mudança', () => {
    expect(dadosParaCorrigir(inicial(), com({ valor: '640' }))).toEqual({});
    expect(dadosParaCorrigir(inicial(), com({ valor: 'R$ 640,00' }))).toEqual(
      {}
    );
  });

  it('manda só o que mudou, no formato do seguro', () => {
    const mudado = com({
      tipo: 'auto',
      numero: ' HZ-002319 ',
      termina: '2026-12-05',
      valor: '700,5',
      bem: ' Casa em Campinas ',
    });

    expect(dadosParaCorrigir(inicial(), mudado)).toEqual({
      tipo: 'auto',
      numero: 'HZ-002319',
      termina: aoMeioDia(2026, 12, 5),
      valor: 700.5,
      bem: 'Casa em Campinas',
    });
  });

  it('data de início e valor apagados vão como null', () => {
    expect(
      dadosParaCorrigir(inicial(), com({ comeca: '', valor: '' }))
    ).toEqual({ comeca: null, valor: null });
  });

  it('trocar para outra seguradora manda o nome escrito, sem espaço sobrando', () => {
    const outra = com({
      seguradora: OUTRA_SEGURADORA,
      outraSeguradora: ' Seguradora Aurora ',
    });

    expect(dadosParaCorrigir(inicial(), outra)).toEqual({
      seguradora: 'Seguradora Aurora',
    });
  });

  it('escolher na lista a seguradora que estava em "Outra" não é mudança', () => {
    const aberto = formularioDoSeguro(SEGURO, []);
    const escolhida = {
      ...aberto,
      seguradora: 'Horizonte Seguros',
      outraSeguradora: '',
    };

    expect(dadosParaCorrigir(aberto, escolhida)).toEqual({});
  });
});

// #3043 (E8.1) — os dados do segurado que a cotação da renovação pede.
describe('os dados do segurado', () => {
  const COM_DADOS = {
    ...SEGURO,
    tipo: 'auto',
    nascimento: aoMeioDia(1985, 3, 15),
    sexo: 'F',
    cep: '12345678',
    placa: 'EXM0A00',
    bonus: 5,
  };
  const aberto = () => formularioDoSeguro(COM_DADOS, SEGURADORAS);
  // 17/11/2026, meio-dia, no relógio de quem lê.
  const AGORA = new Date(2026, 10, 17, 12).getTime();

  it('do seguro para os campos: o CEP com traço e a classe como texto', () => {
    expect(aberto()).toMatchObject({
      nascimento: '1985-03-15',
      sexo: 'F',
      cep: '12345-678',
      placa: 'EXM0A00',
      bonus: '5',
    });
  });

  it.each([
    ['12345678', '12345-678'],
    ['123', '123'],
    ['12a34-5678 9', '12345-678'],
    [null, ''],
  ])('o CEP %s aparece como %s', (digitado, mostrado) => {
    expect(cepComMascara(digitado)).toBe(mostrado);
  });

  it.each([
    ['abc-1d23', 'ABC1D23'],
    ['exm 0a00 9', 'EXM0A00'],
    [null, ''],
  ])('a placa %s aparece como %s', (digitado, mostrado) => {
    expect(placaComMascara(digitado)).toBe(mostrado);
  });

  it.each([
    ['5', 5],
    [' 0 ', 0],
    ['10', 10],
    ['11', null],
    ['5.0', null],
    ['-1', null],
    ['', null],
  ])('a classe de bônus %s é %s', (digitado, classe) => {
    expect(bonusDigitado(digitado)).toBe(classe);
  });

  it('o seguro de empresa não tem nascimento nem sexo', () => {
    expect(temNascimentoESexo({ segurado: { tipo: 'empresa' } })).toBe(false);
    expect(temNascimentoESexo({ segurado: { tipo: 'pessoa' } })).toBe(true);
  });

  it('em branco não falta nada; o que foi escrito e não serve falta', () => {
    const emBranco = {
      ...aberto(),
      nascimento: '',
      sexo: '',
      cep: '',
      placa: '',
      bonus: '',
    };
    const errado = {
      ...aberto(),
      nascimento: '2026-11-18',
      cep: '1234-567',
      placa: 'EXM0A',
      bonus: '11',
    };

    expect(faltasDoFormulario(emBranco, aberto(), AGORA)).toEqual({});
    expect(faltasDoFormulario(errado, aberto(), AGORA)).toEqual({
      nascimento: 'NASCIMENTO',
      cep: 'CEP',
      placa: 'PLACA',
      bonus: 'BONUS',
    });
    const hoje = { ...aberto(), nascimento: '2026-11-17' };
    expect(faltasDoFormulario(hoje, aberto(), AGORA)).toEqual({});
  });

  it('manda só o que mudou: o CEP em dígitos, a placa em maiúsculas e o apagado como null', () => {
    const mudado = {
      ...aberto(),
      nascimento: '1985-03-16',
      sexo: '',
      cep: '98765-432',
      placa: 'abc-1d23',
      bonus: '',
    };

    expect(dadosParaCorrigir(aberto(), mudado)).toEqual({
      nascimento: aoMeioDia(1985, 3, 16),
      sexo: null,
      cep: '98765432',
      placa: 'ABC1D23',
      bonus: null,
    });
    expect(
      dadosParaCorrigir(aberto(), { ...aberto(), placa: 'exm-0a00' })
    ).toEqual({});
  });

  it('o formulário sem os dados do segurado (a apólice nova) não os manda', () => {
    const semDados = { ...inicial() };
    ['nascimento', 'sexo', 'cep', 'placa', 'bonus'].forEach(campo => {
      delete semDados[campo];
    });

    expect(
      dadosParaCorrigir(semDados, { ...semDados, numero: 'HZ-002319' })
    ).toEqual({ numero: 'HZ-002319' });
  });
});
