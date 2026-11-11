// O que liga a carteira de seguros no protótipo (#2897): a demonstração, e só
// no ambiente de desenvolvimento. Sem ela, nada de seguro aparece.
const carregar = async () => {
  vi.resetModules();
  const [demo, carteira] = await Promise.all([
    import('../../fonte/modoDemo'),
    import('../../fonte/modoCarteira'),
  ]);
  return { ...demo, ...carteira };
};

describe('contaDeSeguros', () => {
  it('sem demonstração, a conta não é de seguros', async () => {
    const { contaDeSeguros } = await carregar();
    expect(contaDeSeguros()).toBe(false);
  });

  it.each(['cheio', 'vazio', 'carregando', 'sem-seguros'])(
    'na demonstração "%s" a conta é de seguros',
    async estado => {
      const { contaDeSeguros, usarDemo } = await carregar();
      usarDemo({ demo: estado });
      expect(contaDeSeguros()).toBe(true);
    }
  );

  it('em "fora-do-segmento" a conta é de outro segmento', async () => {
    const { contaDeSeguros, usarDemo } = await carregar();
    usarDemo({ demo: 'fora-do-segmento' });
    expect(contaDeSeguros()).toBe(false);
  });

  it('fora do desenvolvimento a demonstração não liga nada', async () => {
    const { contaDeSeguros, usarDemo } = await carregar();
    usarDemo({ demo: 'cheio' }, false);
    expect(contaDeSeguros()).toBe(false);
  });
});

describe('abaDeSegurosPermitida', () => {
  it('em desenvolvimento, o endereço abre a aba, menos em conta de outro segmento', async () => {
    const { abaDeSegurosPermitida, usarDemo } = await carregar();
    expect(abaDeSegurosPermitida()).toBe(true);
    usarDemo({ demo: 'fora-do-segmento' });
    expect(abaDeSegurosPermitida()).toBe(false);
  });

  it('fora do desenvolvimento, o endereço não abre a aba', async () => {
    const { abaDeSegurosPermitida } = await carregar();
    expect(abaDeSegurosPermitida(false)).toBe(false);
  });
});

describe('aggerLigadoNaDemo', () => {
  it('ligado na conta cheia; desligado sem demonstração, em "sem-seguros" e em "vazio"', async () => {
    const { aggerLigadoNaDemo } = await carregar();
    expect(aggerLigadoNaDemo('cheio')).toBe(true);
    expect(aggerLigadoNaDemo(null)).toBe(false);
    expect(aggerLigadoNaDemo('sem-seguros')).toBe(false);
    expect(aggerLigadoNaDemo('vazio')).toBe(false);
  });
});

describe('pecaPedida (?demo-carteira=)', () => {
  it.each(['carregando', 'erro', 'vazio'])('aceita "%s"', async peca => {
    const { pecaPedida } = await carregar();
    expect(pecaPedida({ 'demo-carteira': peca })).toBe(peca);
  });

  it('ignora valor desconhecido, falta do parâmetro e o ambiente de produção', async () => {
    const { pecaPedida } = await carregar();
    expect(pecaPedida({ 'demo-carteira': 'inventado' })).toBeNull();
    expect(pecaPedida({})).toBeNull();
    expect(pecaPedida()).toBeNull();
    expect(pecaPedida({ 'demo-carteira': 'erro' }, false)).toBeNull();
  });
});
