// #2932–#2934 — o que os passos com motor leem do servidor: públicos salvos,
// blocos da conta, a contagem da lista e o teste da busca. Cada teste carrega o
// módulo de novo, porque os públicos e os blocos ficam guardados depois da 1ª
// leitura. As funções falsas são as mesmas em cada carga (vi.hoisted).
const { AutomacoesAPI, AudiencesAPI } = vi.hoisted(() => ({
  AutomacoesAPI: {
    get: vi.fn(),
    contarLista: vi.fn(),
    testarConsulta: vi.fn(),
  },
  AudiencesAPI: { list: vi.fn() },
}));
vi.mock('dashboard/api/autonomia/automacoes', () => ({
  default: AutomacoesAPI,
}));
vi.mock('dashboard/api/campaignJourneyAudiences', () => ({
  default: AudiencesAPI,
}));

const carregar = async () => {
  vi.resetModules();
  return import('../dadosDaConta');
};

describe('dadosDaConta', () => {
  it('os públicos vêm dos salvos, com o nome para a frase', async () => {
    AudiencesAPI.list.mockResolvedValue({
      data: { payload: [{ id: 4, name: 'Clientes ativos' }] },
    });
    const dados = await carregar();

    await dados.carregarPublicos();

    expect(AudiencesAPI.list).toHaveBeenCalledWith({ saved: true });
    expect(dados.publicosDaConta()).toEqual([
      { value: 4, label: 'Clientes ativos' },
    ]);
    expect(dados.nomeDoPublico(4)).toBe('Clientes ativos');
    expect(dados.nomeDoPublico(5)).toBe('');
  });

  it('a leitura dos públicos que falha deixa a lista vazia e tenta de novo', async () => {
    AudiencesAPI.list.mockRejectedValueOnce(new Error('rede'));
    const dados = await carregar();

    expect(await dados.carregarPublicos()).toEqual([]);
    AudiencesAPI.list.mockResolvedValue({
      data: { payload: [{ id: 1, name: 'Sem compra' }] },
    });
    await dados.carregarPublicos();

    expect(AudiencesAPI.list).toHaveBeenCalledTimes(2);
    expect(dados.nomeDoPublico(1)).toBe('Sem compra');
  });

  it('os blocos são só as automações marcadas, com os passos da receita', async () => {
    AutomacoesAPI.get.mockResolvedValue({
      data: {
        automacoes: [
          {
            id: 1,
            nome: 'Boas-vindas',
            bloco: true,
            versao: { receita: { passos: [{ id: 'p1', tipo: 'parar' }] } },
          },
          { id: 2, nome: 'Comum', bloco: false },
        ],
      },
    });
    const dados = await carregar();

    await dados.carregarBlocos();
    await dados.carregarBlocos();

    expect(AutomacoesAPI.get).toHaveBeenCalledTimes(1);
    expect(dados.blocosDaConta().map(bloco => bloco.id)).toEqual([1]);
    expect(dados.blocoDe(1).passos).toHaveLength(1);
    expect(dados.blocoDe(2)).toBeNull();
  });

  it('esquecer os blocos faz a próxima abertura ler de novo', async () => {
    AutomacoesAPI.get.mockResolvedValue({ data: { automacoes: [] } });
    const dados = await carregar();

    await dados.carregarBlocos();
    dados.esquecerBlocos();
    await dados.carregarBlocos();

    expect(AutomacoesAPI.get).toHaveBeenCalledTimes(2);
  });

  it('a contagem da lista vem do servidor e fica para a prévia', async () => {
    const contagem = { total: 7, primeiros: ['Ana'], fora_do_teto: 2, teto: 5 };
    AutomacoesAPI.contarLista.mockResolvedValue({ data: contagem });
    const dados = await carregar();
    const lista = { de: 'etiqueta', etiqueta: 'vip' };

    expect(await dados.contarLista(lista, 5)).toEqual(contagem);
    expect(AutomacoesAPI.contarLista).toHaveBeenCalledWith({ lista, teto: 5 });
    expect(dados.contagemDaTela()).toEqual(contagem);
  });

  it('o teste da busca guarda os dados achados; a falha volta com o motivo', async () => {
    AutomacoesAPI.testarConsulta.mockResolvedValueOnce({
      data: {
        ok: true,
        dados: [{ caminho: 'pedido.status', valor: 'enviado', rotulo: 'X' }],
      },
    });
    const dados = await carregar();
    const fonte = { de: 'endereco', url: 'https://loja.exemplo/api' };

    await dados.testarConsulta(fonte);
    expect(dados.valorDoTeste('pedido.status')).toBe('enviado');

    AutomacoesAPI.testarConsulta.mockRejectedValueOnce({
      response: { data: { error: 'Endereço não permitido.' } },
    });
    expect(await dados.testarConsulta(fonte)).toEqual({
      ok: false,
      error: 'Endereço não permitido.',
    });
  });

  it('o "Buscar agora" do ensaio dá o valor de cada dado guardado', async () => {
    AutomacoesAPI.testarConsulta.mockResolvedValue({
      data: { ok: true, dados: [{ caminho: 'pedido.status', valor: 'pago' }] },
    });
    const dados = await carregar();
    const passo = {
      fonte: { de: 'endereco', url: 'https://loja.exemplo/api' },
      guardar: [
        { nome: 'Status', caminho: 'pedido.status' },
        { nome: 'Prazo', caminho: 'pedido.prazo' },
      ],
    };

    const resposta = await dados.buscarNoEnsaio(passo);

    expect(resposta.ok).toBe(true);
    expect(resposta.dados).toEqual([
      { nome: 'Status', valor: 'pago' },
      { nome: 'Prazo', valor: '' },
    ]);
  });
});
