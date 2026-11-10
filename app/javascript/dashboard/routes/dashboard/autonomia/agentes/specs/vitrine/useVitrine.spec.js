// #2858 F2 — o estado da vitrine de ferramentas prontas com a API de verdade (mockada aqui): carregar, incluir,
// ligar/desligar, tirar, experimentar e a busca sem resultado. O estado é um só por página, então cada teste recarrega
// o módulo.
const api = vi.hoisted(() => ({
  listar: vi.fn(),
  incluir: vi.fn(),
  mudarLigada: vi.fn(),
  tirar: vi.fn(),
  experimentar: vi.fn(),
  buscaSemResultado: vi.fn(),
}));
vi.mock('dashboard/api/autonomia/ferramentasProntas', () => ({ default: api }));

const LISTA = {
  fontes: [{ chave: 'cep' }, { chave: 'cnpj' }],
  incluidas: [
    {
      id: 31,
      agente_id: 7,
      fonte: 'cep',
      ligada: true,
      usar_quando: 'Use quando o cliente informar um CEP.',
    },
    { id: 32, agente_id: 8, fonte: 'cnpj', ligada: false, usar_quando: null },
  ],
};

const falha = (status, data = {}) =>
  Object.assign(new Error(String(status)), { response: { status, data } });

const novoEstado = async () => {
  vi.resetModules();
  const { useVitrine } = await import('../../vitrine/useVitrine');
  return useVitrine();
};

beforeEach(() => {
  Object.values(api).forEach(fn => fn.mockReset());
  api.listar.mockResolvedValue({ data: LISTA });
});

describe('useVitrine · carregar', () => {
  it('reads the released sources and the tools of each agent', async () => {
    const vitrine = await novoEstado();
    await vitrine.carregar();
    expect(api.listar).toHaveBeenCalledTimes(1);
    expect(vitrine.fontes.value).toEqual(['cep', 'cnpj']);
    expect(vitrine.doAgente(7).map(item => item.fonte)).toEqual(['cep']);
    expect(vitrine.doAgente('8').map(item => item.id)).toEqual([32]);
    expect(vitrine.tem(7, 'cep')).toBe(true);
    expect(vitrine.tem(7, 'cnpj')).toBe(false);
    expect(vitrine.carregada.value).toBe(true);
    expect(vitrine.erro.value).toBe('');
  });

  it('an older list does not wipe out a change made while it was on the way: it asks again', async () => {
    let responder;
    const antiga = { id: 3, agente_id: 2, fonte: 'cnpj', ligada: true };
    const nova = { id: 9, agente_id: 1, fonte: 'cep', ligada: true };
    api.listar
      .mockReturnValueOnce(
        new Promise(resolve => {
          responder = resolve;
        })
      )
      .mockResolvedValueOnce({
        data: { fontes: [{ chave: 'cep' }], incluidas: [antiga, nova] },
      });
    api.incluir.mockResolvedValue({ data: nova });
    const vitrine = await novoEstado();
    const carga = vitrine.carregar();
    await vitrine.incluir({ fonte: 'cep', agenteId: 1, usarQuando: 'x' });
    responder({ data: { fontes: [{ chave: 'cep' }], incluidas: [antiga] } });
    await carga;
    expect(api.listar).toHaveBeenCalledTimes(2);
    expect(vitrine.incluidas.value.map(item => item.id)).toEqual([3, 9]);
  });

  it('two screens at the same time share one request', async () => {
    const vitrine = await novoEstado();
    await Promise.all([vitrine.carregar(), vitrine.carregar()]);
    expect(api.listar).toHaveBeenCalledTimes(1);
  });

  it.each([
    [401, {}, 'SEM_PERMISSAO'],
    [403, {}, 'SEM_PERMISSAO'],
    [404, { motivo: 'desligada' }, 'DESLIGADA'],
    [404, {}, 'NAO_ENCONTRADO'],
    [500, {}, 'GERAL'],
  ])('a %s (%o) turns into %s', async (status, data, motivo) => {
    api.listar.mockRejectedValue(falha(status, data));
    const vitrine = await novoEstado();
    await vitrine.carregar();
    expect(vitrine.erro.value).toBe(motivo);
    expect(vitrine.carregando.value).toBe(false);
  });

  it('no answer at all is a network problem', async () => {
    api.listar.mockRejectedValue(new Error('Network Error'));
    const vitrine = await novoEstado();
    await vitrine.carregar();
    expect(vitrine.erro.value).toBe('REDE');
  });
});

describe('useVitrine · mudanças', () => {
  it('includes a tool and shows it in the agent right away', async () => {
    const vitrine = await novoEstado();
    await vitrine.carregar();
    const nova = {
      id: 40,
      agente_id: 7,
      fonte: 'cnpj',
      ligada: true,
      usar_quando: 'Use quando o cliente informar um CNPJ.',
    };
    api.incluir.mockResolvedValue({ data: nova });
    await vitrine.incluir({
      fonte: 'cnpj',
      agenteId: '7',
      usarQuando: 'Use quando o cliente informar um CNPJ.',
    });
    expect(api.incluir).toHaveBeenCalledWith({
      fonte: 'cnpj',
      agenteId: 7,
      usarQuando: 'Use quando o cliente informar um CNPJ.',
    });
    expect(vitrine.tem(7, 'cnpj')).toBe(true);
    expect(vitrine.incluidas.value).toHaveLength(3);
  });

  it('including the same tool again replaces it, without a duplicate', async () => {
    const vitrine = await novoEstado();
    await vitrine.carregar();
    api.incluir.mockResolvedValue({
      data: { ...LISTA.incluidas[0], usar_quando: 'Outra frase.' },
    });
    await vitrine.incluir({ fonte: 'cep', agenteId: 7, usarQuando: 'x' });
    expect(vitrine.doAgente(7)).toHaveLength(1);
    expect(vitrine.doAgente(7)[0].usar_quando).toBe('Outra frase.');
  });

  it.each([
    ['nome_em_uso', 'NOME_EM_USO'],
    ['agente_de_cotacao', 'COTACAO'],
    ['desligada', 'DESLIGADA'],
    ['pessoa_de_outra_conta', 'GERAL'],
  ])('a refused include (%s) carries the reason %s', async (motivo, chave) => {
    const vitrine = await novoEstado();
    await vitrine.carregar();
    api.incluir.mockRejectedValue(falha(422, { motivo }));
    await expect(
      vitrine.incluir({ fonte: 'cnpj', agenteId: 7, usarQuando: 'x' })
    ).rejects.toMatchObject({ motivo: chave });
    expect(vitrine.tem(7, 'cnpj')).toBe(false);
  });

  it('turns a tool off and on with the answer from the server', async () => {
    const vitrine = await novoEstado();
    await vitrine.carregar();
    api.mudarLigada.mockResolvedValue({
      data: { ...LISTA.incluidas[0], ligada: false },
    });
    await vitrine.mudarLigada(31, false);
    expect(api.mudarLigada).toHaveBeenCalledWith(31, false);
    expect(vitrine.doAgente(7)[0].ligada).toBe(false);
  });

  it('removes a tool only after the server confirms', async () => {
    const vitrine = await novoEstado();
    await vitrine.carregar();
    api.tirar.mockRejectedValueOnce(falha(500));
    await expect(vitrine.tirar(31)).rejects.toMatchObject({ motivo: 'GERAL' });
    expect(vitrine.tem(7, 'cep')).toBe(true);

    api.tirar.mockResolvedValue({});
    await vitrine.tirar(31);
    expect(api.tirar).toHaveBeenCalledWith(31);
    expect(vitrine.tem(7, 'cep')).toBe(false);
  });
});

describe('useVitrine · experimentar e busca', () => {
  it('returns the situation and data from the server', async () => {
    const vitrine = await novoEstado();
    api.experimentar.mockResolvedValue({
      data: { situacao: 'encontrado', dados: { cidade: 'São Paulo' } },
    });
    expect(await vitrine.experimentar('cep', '01001-000')).toEqual({
      situacao: 'encontrado',
      dados: { cidade: 'São Paulo' },
    });
    expect(api.experimentar).toHaveBeenCalledWith('cep', '01001-000');
  });

  it('a failed call becomes one situation the screen can say', async () => {
    const vitrine = await novoEstado();
    api.experimentar.mockRejectedValueOnce(falha(401));
    expect(await vitrine.experimentar('cep', '1')).toEqual({
      situacao: 'sem_permissao',
    });
    api.experimentar.mockRejectedValueOnce(falha(500));
    expect(await vitrine.experimentar('cep', '1')).toEqual({
      situacao: 'nao_consegui_consultar',
    });
    api.experimentar.mockRejectedValueOnce(falha(404, { motivo: 'desligada' }));
    expect(await vitrine.experimentar('cep', '1')).toEqual({
      situacao: 'desligada',
    });
  });

  it('records a search without result and never breaks the screen', async () => {
    const vitrine = await novoEstado();
    api.buscaSemResultado.mockResolvedValueOnce({});
    expect(await vitrine.registrarBuscaSemResultado('avião')).toBe(true);
    api.buscaSemResultado.mockRejectedValueOnce(falha(500));
    expect(await vitrine.registrarBuscaSemResultado('barco')).toBe(false);
    expect(api.buscaSemResultado.mock.calls).toEqual([['avião'], ['barco']]);
  });
});
