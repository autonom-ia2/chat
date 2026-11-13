import { ref } from 'vue';
import { flushPromises } from '@vue/test-utils';
import { useCarteiraNaLista } from '../../carteira/useCarteiraNaLista';

// O selo de seguro na lista de pessoas (#2897): cada página que chega pede o
// resumo só das pessoas dela; a carteira fora do ar não derruba a lista, mas a
// falha vai ao registro de erros do painel; selo de consulta antiga não pisa no
// da nova; e a conta sem a carteira não chama nada, nem baixa a fonte da
// carteira.
const sentry = vi.hoisted(() => ({ reportarSemDados: vi.fn() }));
vi.mock('dashboard/helper/sentryPrivacy', () => sentry);

const VENCIDO = { quantos: 2, selo: 'vencido', tipo: 'auto', dias: -3 };
const ATIVO = { quantos: 1, selo: 'ativo', tipo: 'vida', dias: 40 };

const ONDE_FALHOU = { tela: 'relacionamentos_lista_selos' };

// Uma resposta que só chega quando o teste solta.
const adiada = () => {
  const guarda = {};
  guarda.promessa = new Promise(resolve => {
    guarda.soltar = resolve;
  });
  return guarda;
};

const paginaCom = ids => ({
  itens: ids.map(id => ({ id, name: `Pessoa ${id}` })),
  total: ids.length,
  temMais: false,
});

// `paginas`: número da página -> ids das pessoas dela.
const montar = ({
  ligada = true,
  demo = null,
  paginas = { 1: [1, 2, 3] },
  resumoPorPessoa = vi.fn().mockResolvedValue({}),
  carregarFonte = null,
} = {}) => {
  const carteiraFonte = vi.fn(() => ({ resumoPorPessoa }));
  const carregar = carregarFonte ?? vi.fn(async () => ({ carteiraFonte }));
  const daLista = {
    usaDemo: false,
    listar: vi.fn(async ({ pagina = 1 } = {}) =>
      paginaCom(paginas[pagina] ?? [])
    ),
    contagens: vi.fn(),
  };
  const naConta = ref(ligada);
  const carteira = useCarteiraNaLista({
    demo,
    ligada: naConta,
    carregarFonte: carregar,
  });
  return {
    carteira,
    daLista,
    fonte: carteira.comSelos(daLista),
    carteiraFonte,
    carregar,
    resumoPorPessoa,
    naConta,
  };
};

beforeEach(() => sentry.reportarSemDados.mockReset());

describe('o resumo dos seguros de cada página', () => {
  it('pede só os ids da página que chegou, uma vez por página', async () => {
    const { fonte, resumoPorPessoa } = montar({
      paginas: { 1: [1, 2, 3], 2: [4, 5] },
    });

    await fonte.listar({ aba: 'pessoas', pagina: 1 });
    await flushPromises();
    await fonte.listar({ aba: 'pessoas', pagina: 2 });
    await flushPromises();

    expect(resumoPorPessoa.mock.calls).toEqual([[[1, 2, 3]], [[4, 5]]]);
  });

  it('entrega o selo de quem tem seguro e nada de quem não tem', async () => {
    const { fonte, carteira } = montar({
      resumoPorPessoa: vi.fn().mockResolvedValue({ 1: VENCIDO, 3: ATIVO }),
    });

    await fonte.listar({ aba: 'pessoas' });
    await flushPromises();

    expect([1, 2, 3, 99].map(carteira.daPessoa)).toEqual([
      VENCIDO,
      null,
      ATIVO,
      null,
    ]);
  });

  it('junta os selos das páginas já mostradas', async () => {
    const resumoPorPessoa = vi
      .fn()
      .mockResolvedValueOnce({ 1: VENCIDO })
      .mockResolvedValueOnce({ 5: ATIVO });
    const { fonte, carteira } = montar({
      paginas: { 1: [1, 2, 3], 2: [4, 5] },
      resumoPorPessoa,
    });

    await fonte.listar({ aba: 'pessoas', pagina: 1 });
    await fonte.listar({ aba: 'pessoas', pagina: 2 });
    await flushPromises();

    expect([carteira.daPessoa(1), carteira.daPessoa(5)]).toEqual([
      VENCIDO,
      ATIVO,
    ]);
  });

  it('reler a lista tira o selo de quem deixou de ter seguro', async () => {
    const resumoPorPessoa = vi
      .fn()
      .mockResolvedValueOnce({ 1: VENCIDO, 2: ATIVO })
      .mockResolvedValueOnce({ 2: ATIVO });
    const { fonte, carteira } = montar({ resumoPorPessoa });

    await fonte.listar({ aba: 'pessoas' });
    await flushPromises();
    await fonte.listar({ aba: 'pessoas' });
    await flushPromises();

    expect([carteira.daPessoa(1), carteira.daPessoa(2)]).toEqual([null, ATIVO]);
  });

  it('quando a carteira responde, nada vai ao registro de erros', async () => {
    const { fonte } = montar();

    await fonte.listar({ aba: 'pessoas' });
    await flushPromises();

    expect(sentry.reportarSemDados).not.toHaveBeenCalled();
  });

  it('a lista não espera a carteira: as pessoas chegam antes dos selos', async () => {
    const { fonte, carteira } = montar({
      resumoPorPessoa: vi.fn(() => new Promise(() => {})),
    });

    const resposta = await fonte.listar({ aba: 'pessoas' });

    expect(resposta.itens.map(({ id }) => id)).toEqual([1, 2, 3]);
    expect(carteira.daPessoa(1)).toBeNull();
  });

  it('entrega a resposta da lista como veio e mantém o resto da fonte', async () => {
    const { fonte, daLista } = montar();

    expect(await fonte.listar({ aba: 'pessoas' })).toEqual(
      paginaCom([1, 2, 3])
    );
    expect(daLista.listar).toHaveBeenCalledWith({ aba: 'pessoas' });
    expect(fonte.contagens).toBe(daLista.contagens);
    expect(fonte.usaDemo).toBe(false);
  });

  it('na demonstração, lê da carteira da demonstração', async () => {
    const { fonte, carteiraFonte } = montar({ demo: 'cheio' });

    await fonte.listar({ aba: 'pessoas' });
    await flushPromises();

    expect(carteiraFonte).toHaveBeenCalledWith({ demo: 'cheio' });
  });
});

describe('quando a consulta muda', () => {
  it('selo de uma leitura antiga que chega atrasado não pisa no da leitura nova', async () => {
    const lenta = adiada();
    const resumoPorPessoa = vi
      .fn()
      .mockReturnValueOnce(lenta.promessa)
      .mockResolvedValueOnce({ 1: ATIVO });
    const { fonte, carteira } = montar({ resumoPorPessoa });

    await fonte.listar({ aba: 'pessoas' });
    await flushPromises();
    await fonte.listar({ aba: 'pessoas' });
    await flushPromises();
    lenta.soltar({ 1: VENCIDO });
    await flushPromises();

    expect(carteira.daPessoa(1)).toEqual(ATIVO);
  });

  it('a página que chega depois de a consulta mudar não pede selo', async () => {
    const lenta = adiada();
    const { fonte, daLista, resumoPorPessoa } = montar();
    daLista.listar.mockReturnValueOnce(lenta.promessa);

    const antiga = fonte.listar({ aba: 'pessoas', pagina: 2 });
    await fonte.listar({ aba: 'pessoas', busca: 'exemplo' });
    lenta.soltar(paginaCom([4, 5]));
    await antiga;
    await flushPromises();

    expect(resumoPorPessoa.mock.calls).toEqual([[[1, 2, 3]]]);
  });

  it('outra busca, grupo ou filtro tira o selo de quem saiu da tela', async () => {
    const resumoPorPessoa = vi
      .fn()
      .mockResolvedValueOnce({ 1: VENCIDO, 2: ATIVO })
      .mockResolvedValueOnce({ 2: ATIVO });
    const { fonte, carteira, daLista } = montar({ resumoPorPessoa });

    await fonte.listar({ aba: 'pessoas' });
    await flushPromises();
    daLista.listar.mockResolvedValueOnce(paginaCom([2, 9]));
    await fonte.listar({ aba: 'pessoas', busca: 'exemplo' });
    await flushPromises();

    expect([1, 2, 9].map(carteira.daPessoa)).toEqual([null, ATIVO, null]);
  });

  it('"mostrar mais" não tira o selo de quem já estava na tela', async () => {
    const resumoPorPessoa = vi
      .fn()
      .mockResolvedValueOnce({ 1: VENCIDO })
      .mockResolvedValueOnce({ 5: ATIVO });
    const { fonte, carteira } = montar({
      paginas: { 1: [1, 2, 3], 2: [4, 5] },
      resumoPorPessoa,
    });

    await fonte.listar({ aba: 'pessoas', pagina: 1 });
    await flushPromises();
    await fonte.listar({ aba: 'pessoas', pagina: 2 });
    await flushPromises();

    expect(carteira.daPessoa(1)).toEqual(VENCIDO);
  });

  it('ir para a aba Empresas esvazia os selos', async () => {
    const { fonte, carteira } = montar({
      resumoPorPessoa: vi.fn().mockResolvedValue({ 1: VENCIDO }),
    });

    await fonte.listar({ aba: 'pessoas' });
    await flushPromises();
    await fonte.listar({ aba: 'empresas' });
    await flushPromises();

    expect(carteira.daPessoa(1)).toBeNull();
  });
});

describe('quando não há o que pedir', () => {
  it('conta sem a carteira não chama nada, nem baixa a fonte da carteira', async () => {
    const { fonte, carteira, carregar, resumoPorPessoa } = montar({
      ligada: false,
    });

    const resposta = await fonte.listar({ aba: 'pessoas' });
    await flushPromises();

    expect(resposta.itens).toHaveLength(3);
    expect(carregar).not.toHaveBeenCalled();
    expect(resumoPorPessoa).not.toHaveBeenCalled();
    expect(carteira.daPessoa(1)).toBeNull();
  });

  it('a conta que passa a ter a carteira começa a pedir na leitura seguinte', async () => {
    const { fonte, naConta, resumoPorPessoa } = montar({ ligada: false });

    await fonte.listar({ aba: 'pessoas' });
    naConta.value = true;
    await fonte.listar({ aba: 'pessoas' });
    await flushPromises();

    expect(resumoPorPessoa).toHaveBeenCalledTimes(1);
  });

  it('na aba Empresas não pede: os ids são de empresas, não de pessoas', async () => {
    const { fonte, carregar } = montar();

    await fonte.listar({ aba: 'empresas' });
    await flushPromises();

    expect(carregar).not.toHaveBeenCalled();
  });

  it('página sem ninguém não pede', async () => {
    const { fonte, carregar } = montar({ paginas: {} });

    await fonte.listar({ aba: 'pessoas' });
    await flushPromises();

    expect(carregar).not.toHaveBeenCalled();
  });
});

describe('a carteira fora do ar', () => {
  const falha = () =>
    Object.assign(new Error('Request failed with status code 500'), {
      response: { status: 500 },
    });

  it('não derruba a lista: as pessoas vêm e ninguém ganha selo', async () => {
    const { fonte, carteira } = montar({
      resumoPorPessoa: vi.fn().mockRejectedValue(falha()),
    });

    const resposta = await fonte.listar({ aba: 'pessoas' });
    await flushPromises();

    expect(resposta.itens).toHaveLength(3);
    expect([1, 2, 3].map(carteira.daPessoa)).toEqual([null, null, null]);
  });

  it('a falha vai ao registro de erros, só com o erro e o nome da tela', async () => {
    const erro = falha();
    const { fonte } = montar({
      resumoPorPessoa: vi.fn().mockRejectedValue(erro),
    });

    await fonte.listar({ aba: 'pessoas' });
    await flushPromises();

    expect(sentry.reportarSemDados.mock.calls).toEqual([[erro, ONDE_FALHOU]]);
  });

  it('nem quando a própria fonte da carteira não baixa, e isso também é registrado', async () => {
    const erro = new Error('sem rede');
    const { fonte, carteira } = montar({
      carregarFonte: vi.fn().mockRejectedValue(erro),
    });

    const resposta = await fonte.listar({ aba: 'pessoas' });
    await flushPromises();

    expect(resposta.itens).toHaveLength(3);
    expect(carteira.daPessoa(1)).toBeNull();
    expect(sentry.reportarSemDados.mock.calls).toEqual([[erro, ONDE_FALHOU]]);
  });

  it('defeito de código dentro da fonte da carteira não some: a lista segue e o erro é registrado', async () => {
    const defeito = new TypeError('resumoDosSeguros is not a function');
    const { fonte, carteira } = montar({
      resumoPorPessoa: vi.fn(() => {
        throw defeito;
      }),
    });

    const resposta = await fonte.listar({ aba: 'pessoas' });
    await flushPromises();

    expect(resposta.itens).toHaveLength(3);
    expect(carteira.daPessoa(1)).toBeNull();
    expect(sentry.reportarSemDados.mock.calls).toEqual([
      [defeito, ONDE_FALHOU],
    ]);
  });

  it('guarda os selos que já tinha e volta a pedir na leitura seguinte', async () => {
    const resumoPorPessoa = vi
      .fn()
      .mockResolvedValueOnce({ 1: VENCIDO })
      .mockRejectedValueOnce(falha())
      .mockResolvedValueOnce({ 1: ATIVO });
    const { fonte, carteira } = montar({ resumoPorPessoa });

    await fonte.listar({ aba: 'pessoas' });
    await flushPromises();
    await fonte.listar({ aba: 'pessoas' });
    await flushPromises();
    expect(carteira.daPessoa(1)).toEqual(VENCIDO);

    await fonte.listar({ aba: 'pessoas' });
    await flushPromises();
    expect(carteira.daPessoa(1)).toEqual(ATIVO);
  });

  it('a falha da lista continua subindo: quem mostra o erro é a lista', async () => {
    const { fonte, daLista, carregar } = montar();
    daLista.listar.mockRejectedValue(falha());

    await expect(fonte.listar({ aba: 'pessoas' })).rejects.toThrow('500');
    expect(carregar).not.toHaveBeenCalled();
  });
});
