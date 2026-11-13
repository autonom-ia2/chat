import {
  PECAS_DA_CARTEIRA,
  contaDeSeguros,
  pecaPedida,
} from '../../fonte/modoCarteira';

// O que liga a carteira de seguros nas telas (#2897): fora da demonstração é o
// payload da conta; na demonstração, o estado dela.
describe('contaDeSeguros', () => {
  it('fora da demonstração vale o que o servidor disse da conta', () => {
    expect(contaDeSeguros(null, { carteira_seguros: true })).toBe(true);
    expect(contaDeSeguros(null, { carteira_seguros: false })).toBe(false);
  });

  it('sem a chave no payload, a conta não tem a carteira', () => {
    expect(contaDeSeguros(null, {})).toBe(false);
    expect(contaDeSeguros(null, undefined)).toBe(false);
    expect(contaDeSeguros(null, null)).toBe(false);
  });

  it('só `true` liga: valor parecido não', () => {
    expect(contaDeSeguros(null, { carteira_seguros: 'true' })).toBe(false);
    expect(contaDeSeguros(null, { carteira_seguros: 1 })).toBe(false);
  });

  it.each(['cheio', 'vazio', 'carregando', 'sem-seguros'])(
    'na demonstração %s a conta fictícia é de seguros',
    demo => {
      expect(contaDeSeguros(demo, { carteira_seguros: false })).toBe(true);
    }
  );

  it('na demonstração "fora do segmento" nada de seguro aparece', () => {
    expect(contaDeSeguros('fora-do-segmento', { carteira_seguros: true })).toBe(
      false
    );
  });
});

describe('pecaPedida', () => {
  it.each(PECAS_DA_CARTEIRA)('aceita a peça %s', peca => {
    expect(pecaPedida({ 'demo-carteira': peca }, true)).toBe(peca);
  });

  it('devolve null sem o parâmetro ou com valor que não existe', () => {
    expect(pecaPedida({}, true)).toBeNull();
    expect(pecaPedida(undefined, true)).toBeNull();
    expect(pecaPedida({ 'demo-carteira': 'inventado' }, true)).toBeNull();
    expect(pecaPedida({ 'demo-carteira': ['erro'] }, true)).toBeNull();
  });

  it('ignora o parâmetro fora do ambiente de desenvolvimento', () => {
    expect(pecaPedida({ 'demo-carteira': 'erro' }, false)).toBeNull();
  });
});
