// O modo demonstração de Relacionamentos (#2894): `?demo=<estado>` só vale em
// desenvolvimento e "gruda" — a navegação interna não leva o parâmetro.
const carregar = async () => {
  vi.resetModules();
  return import('../fonte/modoDemo');
};

describe('demoPedido', () => {
  it.each(['cheio', 'vazio'])('aceita o estado %s', async estado => {
    const { demoPedido } = await carregar();
    expect(demoPedido({ demo: estado })).toBe(estado);
  });

  it('devolve null sem o parâmetro', async () => {
    const { demoPedido } = await carregar();
    expect(demoPedido({})).toBeNull();
    expect(demoPedido()).toBeNull();
    expect(demoPedido({ demo: '' })).toBeNull();
  });

  it('ignora estado que não existe e valor que não é texto', async () => {
    const { demoPedido } = await carregar();
    expect(demoPedido({ demo: 'inventado' })).toBeNull();
    expect(demoPedido({ demo: ['cheio'] })).toBeNull();
  });

  it('ignora o parâmetro fora do ambiente de desenvolvimento', async () => {
    const { demoPedido } = await carregar();
    expect(demoPedido({ demo: 'cheio' }, false)).toBeNull();
  });
});

describe('usarDemo e estadoDemo', () => {
  it('começa sem demonstração', async () => {
    const { estadoDemo } = await carregar();
    expect(estadoDemo()).toBeNull();
  });

  it('guarda o estado que veio na URL', async () => {
    const { usarDemo, estadoDemo } = await carregar();
    expect(usarDemo({ demo: 'vazio' })).toBe('vazio');
    expect(estadoDemo()).toBe('vazio');
  });

  it('continua em demonstração quando a próxima URL não traz o parâmetro', async () => {
    const { usarDemo, estadoDemo } = await carregar();
    usarDemo({ demo: 'cheio' });
    expect(usarDemo({})).toBe('cheio');
    expect(usarDemo({ aba: 'empresas' })).toBe('cheio');
    expect(estadoDemo()).toBe('cheio');
  });

  it('troca de estado quando a URL traz outro', async () => {
    const { usarDemo, estadoDemo } = await carregar();
    usarDemo({ demo: 'cheio' });
    usarDemo({ demo: 'vazio' });
    expect(estadoDemo()).toBe('vazio');
  });

  it('não guarda nada fora do ambiente de desenvolvimento', async () => {
    const { usarDemo, estadoDemo } = await carregar();
    expect(usarDemo({ demo: 'cheio' }, false)).toBeNull();
    expect(estadoDemo()).toBeNull();
  });

  it('não deixa um estado inválido apagar o que já estava guardado', async () => {
    const { usarDemo, estadoDemo } = await carregar();
    usarDemo({ demo: 'vazio' });
    usarDemo({ demo: 'inventado' });
    expect(estadoDemo()).toBe('vazio');
  });
});

describe('?demo=desligado', () => {
  it('zera o estado guardado em desenvolvimento', async () => {
    const { usarDemo, estadoDemo } = await carregar();
    usarDemo({ demo: 'cheio' });
    expect(usarDemo({ demo: 'desligado' })).toBeNull();
    expect(estadoDemo()).toBeNull();
    expect(usarDemo({})).toBeNull();
  });

  it('não é um estado de demonstração', async () => {
    const { demoPedido } = await carregar();
    expect(demoPedido({ demo: 'desligado' })).toBeNull();
  });

  it('fora do desenvolvimento não mexe em nada', async () => {
    const { usarDemo, estadoDemo } = await carregar();
    usarDemo({ demo: 'cheio' });
    expect(usarDemo({ demo: 'desligado' }, false)).toBe('cheio');
    expect(estadoDemo()).toBe('cheio');
  });
});

describe('?demo=carregando', () => {
  it('é um estado conhecido e as fontes o consultam por demoCarregando()', async () => {
    const { demoPedido, usarDemo, estadoDemo, demoCarregando } =
      await carregar();
    expect(demoPedido({ demo: 'carregando' })).toBe('carregando');
    expect(demoCarregando()).toBe(false);
    usarDemo({ demo: 'carregando' });
    expect(estadoDemo()).toBe('carregando');
    expect(demoCarregando()).toBe(true);
    usarDemo({ demo: 'desligado' });
    expect(demoCarregando()).toBe(false);
  });

  it('esperarParaSempre nunca resolve', async () => {
    vi.useFakeTimers();
    const { esperarParaSempre } = await carregar();
    let resolveu = false;
    esperarParaSempre().then(() => {
      resolveu = true;
    });
    await vi.advanceTimersByTimeAsync(60000);
    expect(resolveu).toBe(false);
    vi.useRealTimers();
  });

  it('fora do desenvolvimento não vale', async () => {
    const { demoPedido } = await carregar();
    expect(demoPedido({ demo: 'carregando' }, false)).toBeNull();
  });
});
