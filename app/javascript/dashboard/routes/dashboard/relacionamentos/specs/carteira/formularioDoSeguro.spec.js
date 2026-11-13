import {
  OUTRA_SEGURADORA,
  chaveDaSeguradora,
  dadosParaCorrigir,
  faltasDoFormulario,
  formularioDoSeguro,
  primeiroCampoQueFalta,
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
