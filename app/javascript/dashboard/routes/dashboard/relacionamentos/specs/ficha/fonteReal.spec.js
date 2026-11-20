import AccountActionsAPI from 'dashboard/api/accountActions';
import CompanyAPI from 'dashboard/api/companies';
import ContactNotesAPI from 'dashboard/api/contactNotes';
import ContactAPI from 'dashboard/api/contacts';
import EtiquetasDoContatoAPI from 'dashboard/api/etiquetasDoContato';
import LabelsAPI from 'dashboard/api/labels';
import RelacionamentosAPI from 'dashboard/api/relacionamentos';
import { fichaFonte } from '../../fonte/fichaFonte';

// A fonte real da ficha (#2895): lê pelas leituras novas de Relacionamentos e
// escreve pelos endpoints que o painel já tem. Depois de escrever, relê a
// pessoa (ou a empresa) e devolve o formato da tela.
vi.mock('dashboard/api/relacionamentos', () => ({
  default: {
    pessoa: vi.fn(),
    conversasDaPessoa: vi.fn(),
    cardsDaPessoa: vi.fn(),
    notasDaPessoa: vi.fn(),
    arquivosDaPessoa: vi.fn(),
    origemDaPessoa: vi.fn(),
    empresa: vi.fn(),
    pessoasDaEmpresa: vi.fn(),
    conversasDaEmpresa: vi.fn(),
    cardsDaEmpresa: vi.fn(),
    pessoas: vi.fn(),
  },
}));
vi.mock('dashboard/api/contacts', () => ({
  default: {
    update: vi.fn(),
    markCustomer: vi.fn(),
    removeCustomer: vi.fn(),
    removeOptOut: vi.fn(),
    markOptOut: vi.fn(),
    delete: vi.fn(),
    destroyAvatar: vi.fn(),
    destroyCustomAttributes: vi.fn(),
  },
}));
vi.mock('dashboard/api/etiquetasDoContato', () => ({
  default: { alterar: vi.fn() },
}));
vi.mock('dashboard/api/contactNotes', () => ({
  default: { create: vi.fn(), delete: vi.fn() },
}));
vi.mock('dashboard/api/accountActions', () => ({
  default: { merge: vi.fn() },
}));
vi.mock('dashboard/api/labels', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/api/companies', () => ({
  default: {
    update: vi.fn(),
    create: vi.fn(),
    search: vi.fn(),
    delete: vi.fn(),
    destroyAvatar: vi.fn(),
    destroyCustomAttributes: vi.fn(),
    listNotes: vi.fn(),
    listMedia: vi.fn(),
    searchContacts: vi.fn(),
    createContact: vi.fn(),
    removeContact: vi.fn(),
  },
}));

const real = () => fichaFonte({ demo: null });
const erroHttp = status =>
  Object.assign(new Error(`Request failed with status code ${status}`), {
    response: { status, data: { error: 'pedido recusado' } },
  });

const ANA = { id: 7, name: 'Ana Albuquerino', contact_type: 'lead' };
const PADARIA = { id: 9, name: 'Padaria Bom Dia', cnpj: '11222333000181' };

// [método da fonte, método do cliente de API, o que o servidor devolve]
const LEITURAS = [
  ['pessoa', 'pessoa', ANA],
  ['conversas', 'conversasDaPessoa', [{ id: 55, canal: 'outro' }]],
  ['cards', 'cardsDaPessoa', [{ id: 3, titulo: 'Plano', valor: null }]],
  ['notas', 'notasDaPessoa', [{ id: 1, autor: 'Sônia', texto: 'Oi' }]],
  ['arquivos', 'arquivosDaPessoa', [{ id: 2, nome: 'a.pdf' }]],
  ['origem', 'origemDaPessoa', { tipo: 'canal', canal: 'whatsapp' }],
  ['empresa', 'empresa', PADARIA],
  ['pessoasDaEmpresa', 'pessoasDaEmpresa', [ANA]],
  ['conversasDaEmpresa', 'conversasDaEmpresa', [{ id: 55, pessoa: 'Ana' }]],
  ['cardsDaEmpresa', 'cardsDaEmpresa', [{ id: 3, pessoa: 'Ana' }]],
];
const ESCRITAS = [
  ['salvar', () => ContactAPI.update, [7, { name: 'Ana' }]],
  ['marcarCliente', () => ContactAPI.markCustomer, [7]],
  ['desmarcarCliente', () => ContactAPI.removeCustomer, [7]],
  ['liberarMensagens', () => ContactAPI.removeOptOut, [7]],
  ['guardarNota', () => ContactNotesAPI.create, [7, 'Ligar amanhã.']],
  [
    'salvarEmpresa',
    () => CompanyAPI.update,
    [9, { empresa: { name: 'Padaria' } }],
  ],
  ['apagarEmpresa', () => CompanyAPI.delete, [9]],
  ['porPessoaNaEmpresa', () => CompanyAPI.createContact, [9, 7]],
  ['tirarPessoaDaEmpresa', () => CompanyAPI.removeContact, [9, 7]],
];

afterEach(() => {
  vi.resetAllMocks();
});

describe('leituras', () => {
  it('não é a demonstração e tem os métodos de leitura e de escrita', () => {
    const fonte = real();
    expect(fonte.usaDemo).toBe(false);
    [...LEITURAS, ...ESCRITAS].forEach(([metodo]) =>
      expect(fonte[metodo]).toBeTypeOf('function')
    );
  });

  it.each(LEITURAS)(
    '%s devolve o que o servidor mandou, pelo id',
    async (metodo, doCliente, data) => {
      RelacionamentosAPI[doCliente].mockResolvedValue({ data });
      expect(await real()[metodo](7)).toEqual(data);
      expect(RelacionamentosAPI[doCliente]).toHaveBeenCalledWith(7);
    }
  );

  it('origem devolve null quando o servidor não sabe de onde veio', async () => {
    RelacionamentosAPI.origemDaPessoa.mockResolvedValue({ data: null });
    expect(await real().origem(7)).toBeNull();
  });
});

describe('erros do servidor', () => {
  it.each(LEITURAS)('%s: 404 vira NAO_ACHEI', async (metodo, doCliente) => {
    RelacionamentosAPI[doCliente].mockRejectedValue(erroHttp(404));
    await expect(real()[metodo](7)).rejects.toMatchObject({
      name: 'NAO_ACHEI',
    });
  });

  it.each([401, 403])('%i vira SEM_ACESSO', async status => {
    RelacionamentosAPI.cardsDaPessoa.mockRejectedValue(erroHttp(status));
    await expect(real().cards(7)).rejects.toMatchObject({
      name: 'SEM_ACESSO',
    });
  });

  it('o erro com nome guarda o do servidor como causa', async () => {
    const doServidor = erroHttp(404);
    RelacionamentosAPI.pessoa.mockRejectedValue(doServidor);
    await expect(real().pessoa(7)).rejects.toMatchObject({
      cause: doServidor,
    });
  });

  it('os outros erros sobem como vieram', async () => {
    const doServidor = erroHttp(500);
    RelacionamentosAPI.pessoa.mockRejectedValue(doServidor);
    await expect(real().pessoa(7)).rejects.toBe(doServidor);
  });

  it.each(ESCRITAS)(
    '%s: 404 vira NAO_ACHEI e nada é relido',
    async (metodo, cliente, argumentos) => {
      cliente().mockRejectedValue(erroHttp(404));
      await expect(real()[metodo](...argumentos)).rejects.toMatchObject({
        name: 'NAO_ACHEI',
      });
      expect(RelacionamentosAPI.pessoa).not.toHaveBeenCalled();
      expect(RelacionamentosAPI.empresa).not.toHaveBeenCalled();
    }
  );
});

describe('escritas da pessoa', () => {
  const relida = { ...ANA, name: 'Ana Maria' };
  beforeEach(() => {
    RelacionamentosAPI.pessoa.mockResolvedValue({ data: relida });
    CompanyAPI.search.mockResolvedValue({ data: { payload: [] } });
  });

  // #3075 — o pedido da gaveta (ficha/informacoes.js#pedidoParaSalvar).
  const contato = {
    name: 'Ana Maria',
    phone_number: null,
    email: 'ana@exemplo.com.br',
    additional_attributes: { city: 'Bauru', company_name: '' },
    custom_attributes: { cpf: '52998224725' },
  };
  const pedido = extra => ({
    contato,
    empresaNova: null,
    foto: null,
    apagar: [],
    ...extra,
  });

  it('salvar manda o contato como a gaveta montou e relê a pessoa', async () => {
    ContactAPI.update.mockResolvedValue({ data: { payload: {} } });
    expect(await real().salvar(7, pedido())).toEqual(relida);
    expect(ContactAPI.update).toHaveBeenCalledTimes(1);
    expect(ContactAPI.update).toHaveBeenCalledWith(7, contato);
    expect(ContactAPI.destroyAvatar).not.toHaveBeenCalled();
    expect(ContactAPI.destroyCustomAttributes).not.toHaveBeenCalled();
    expect(RelacionamentosAPI.pessoa).toHaveBeenCalledWith(7);
  });

  it('empresa nova: cadastra pelo nome e liga a pessoa a ela', async () => {
    CompanyAPI.create.mockResolvedValue({
      data: { payload: { id: 31, name: 'Padaria Nova' } },
    });
    ContactAPI.update.mockResolvedValue({ data: { payload: {} } });
    await real().salvar(7, pedido({ empresaNova: 'Padaria Nova' }));
    expect(CompanyAPI.search).toHaveBeenCalledWith('Padaria Nova');
    expect(CompanyAPI.create).toHaveBeenCalledWith({
      company: { name: 'Padaria Nova' },
    });
    expect(ContactAPI.update).toHaveBeenCalledWith(7, {
      ...contato,
      company_id: 31,
      additional_attributes: {
        ...contato.additional_attributes,
        company_name: 'Padaria Nova',
      },
    });
  });

  it('empresa nova com o nome de uma que já existe usa a que existe', async () => {
    CompanyAPI.search.mockResolvedValue({
      data: {
        payload: [
          { id: 11, name: 'Padaria Nova Era' },
          { id: 12, name: 'PADARIA NOVA' },
        ],
      },
    });
    ContactAPI.update.mockResolvedValue({ data: { payload: {} } });
    await real().salvar(7, pedido({ empresaNova: ' padaria nova ' }));
    expect(CompanyAPI.create).not.toHaveBeenCalled();
    expect(ContactAPI.update).toHaveBeenCalledWith(7, {
      ...contato,
      company_id: 12,
      additional_attributes: {
        ...contato.additional_attributes,
        company_name: 'PADARIA NOVA',
      },
    });
  });

  it('pessoa recusada depois da empresa cadastrada: a falha leva a empresa, e a nova tentativa não cadastra outra', async () => {
    CompanyAPI.create.mockResolvedValue({
      data: { payload: { id: 31, name: 'Padaria Nova' } },
    });
    ContactAPI.update.mockRejectedValueOnce(erroHttp(422));
    const falha = await real()
      .salvar(7, pedido({ empresaNova: 'Padaria Nova' }))
      .catch(erro => erro);
    expect(falha.name).toBe('GravouEmParte');
    expect(falha.response.status).toBe(422);
    expect(falha.retomada.empresa).toEqual({ id: 31, nome: 'Padaria Nova' });
    expect(falha.retomada.pessoa).toBeNull();

    ContactAPI.update.mockResolvedValue({ data: { payload: {} } });
    await real().salvar(
      7,
      pedido({ empresaNova: 'Padaria Nova' }),
      falha.retomada
    );
    expect(CompanyAPI.create).toHaveBeenCalledTimes(1);
    expect(ContactAPI.update).toHaveBeenLastCalledWith(
      7,
      expect.objectContaining({ company_id: 31 })
    );
  });

  it('foto que falha depois da pessoa gravada: a ficha recebe a pessoa e a nova tentativa só manda a foto', async () => {
    ContactAPI.update
      .mockResolvedValueOnce({ data: { payload: { id: 7 } } })
      .mockRejectedValueOnce(erroHttp(500));
    const arquivo = new File(['x'], 'foto.png', { type: 'image/png' });
    const comFoto = pedido({ foto: { arquivo, previa: 'blob:x' } });
    const falha = await real()
      .salvar(7, comFoto)
      .catch(erro => erro);
    expect(falha.name).toBe('GravouEmParte');
    expect(falha.retomada.pessoa).toEqual({ id: 7 });
    expect(falha.retomada.pessoaNaFicha).toEqual(relida);

    ContactAPI.update.mockClear();
    ContactAPI.update.mockResolvedValue({ data: { payload: {} } });
    const { pessoaNaFicha: _relida, ...retomada } = falha.retomada;
    await real().salvar(7, comFoto, retomada);
    expect(ContactAPI.update).toHaveBeenCalledTimes(1);
    expect(ContactAPI.update.mock.calls[0][1]).toBeInstanceOf(FormData);
  });

  it('a empresa que não foi cadastrada não deixa a pessoa pela metade', async () => {
    CompanyAPI.create.mockRejectedValue(erroHttp(422));
    await expect(
      real().salvar(7, pedido({ empresaNova: 'Padaria Nova' }))
    ).rejects.toThrow();
    expect(ContactAPI.update).not.toHaveBeenCalled();
  });

  it('foto nova vai só com o arquivo; tirar a foto e apagar campos vêm depois', async () => {
    ContactAPI.update.mockResolvedValue({ data: { payload: {} } });
    ContactAPI.destroyCustomAttributes.mockResolvedValue({ data: {} });
    const arquivo = new File(['x'], 'foto.png', { type: 'image/png' });
    await real().salvar(
      7,
      pedido({ foto: { arquivo, previa: 'blob:x' }, apagar: ['aniversario'] })
    );
    expect(ContactAPI.update).toHaveBeenCalledTimes(2);
    const [, corpo] = ContactAPI.update.mock.calls[1];
    expect(corpo.get('avatar')).toBeInstanceOf(File);
    expect(ContactAPI.destroyCustomAttributes).toHaveBeenCalledWith(7, [
      'aniversario',
    ]);

    vi.clearAllMocks();
    ContactAPI.update.mockResolvedValue({ data: { payload: {} } });
    ContactAPI.destroyAvatar.mockResolvedValue({ data: {} });
    RelacionamentosAPI.pessoa.mockResolvedValue({ data: relida });
    await real().salvar(7, pedido({ foto: { tirar: true } }));
    expect(ContactAPI.update).toHaveBeenCalledTimes(1);
    expect(ContactAPI.destroyAvatar).toHaveBeenCalledWith(7);
  });

  it('buscarEmpresas devolve id e nome das empresas da conta', async () => {
    CompanyAPI.search.mockResolvedValue({
      data: { payload: [{ id: 3, name: 'Padaria Bom Dia', domain: null }] },
    });
    expect(await real().buscarEmpresas('padaria')).toEqual([
      { id: 3, nome: 'Padaria Bom Dia' },
    ]);
    expect(CompanyAPI.search).toHaveBeenCalledWith('padaria');
  });

  it('marcar como cliente escreve e relê a pessoa', async () => {
    ContactAPI.markCustomer.mockResolvedValue({ data: {} });
    expect(await real().marcarCliente(7)).toEqual(relida);
    expect(ContactAPI.markCustomer).toHaveBeenCalledWith(7);
    expect(RelacionamentosAPI.pessoa).toHaveBeenCalledWith(7);
  });

  it('desmarcar cliente escreve e relê a pessoa', async () => {
    ContactAPI.removeCustomer.mockResolvedValue({ data: {} });
    expect(await real().desmarcarCliente(7)).toEqual(relida);
    expect(ContactAPI.removeCustomer).toHaveBeenCalledWith(7);
    expect(RelacionamentosAPI.pessoa).toHaveBeenCalledWith(7);
  });

  it('liberar mensagens desfaz a recusa e relê a pessoa', async () => {
    ContactAPI.removeOptOut.mockResolvedValue({ data: {} });
    expect(await real().liberarMensagens(7)).toEqual(relida);
    expect(ContactAPI.removeOptOut).toHaveBeenCalledWith(7);
    expect(RelacionamentosAPI.pessoa).toHaveBeenCalledWith(7);
  });

  it('guardar nota devolve a nota no formato da tela, sem reler', async () => {
    ContactNotesAPI.create.mockResolvedValue({
      data: {
        id: 31,
        content: 'Ligar amanhã.',
        user: { id: 4, name: 'Sônia Valtorini' },
        created_at: 1_700_000_000,
        updated_at: 1_700_000_000,
      },
    });
    expect(await real().guardarNota(7, 'Ligar amanhã.')).toEqual({
      id: 31,
      autor: 'Sônia Valtorini',
      quando: 1_700_000_000,
      texto: 'Ligar amanhã.',
    });
    expect(ContactNotesAPI.create).toHaveBeenCalledWith(7, 'Ligar amanhã.');
    expect(RelacionamentosAPI.pessoa).not.toHaveBeenCalled();
  });
});

// #3071 — as ações que vieram da ficha antiga, pelos endpoints dela.
describe('ações da ficha antiga', () => {
  const relida = { ...ANA, name: 'Ana Maria' };
  beforeEach(() => {
    RelacionamentosAPI.pessoa.mockResolvedValue({ data: relida });
  });

  it.each([
    ['marcarNaoQuer', () => ContactAPI.markOptOut, [7], [7]],
    ['bloquear', () => ContactAPI.update, [7], [7, { blocked: true }]],
    ['desbloquear', () => ContactAPI.update, [7], [7, { blocked: false }]],
    [
      'alterarEtiquetas',
      () => EtiquetasDoContatoAPI.alterar,
      [7, { por: ['site'], tirar: ['feira'] }],
      [7, { por: ['site'], tirar: ['feira'] }],
    ],
  ])(
    '%s escreve pelo contato e relê a pessoa',
    async (metodo, api, args, chamado) => {
      api().mockResolvedValue({ data: {} });
      expect(await real()[metodo](...args)).toEqual(relida);
      expect(api()).toHaveBeenCalledWith(...chamado);
      expect(RelacionamentosAPI.pessoa).toHaveBeenCalledWith(7);
    }
  );

  it('juntar: a pessoa da ficha é a que fica (base), a escolhida é absorvida', async () => {
    AccountActionsAPI.merge.mockResolvedValue({ data: {} });
    expect(await real().juntar(7, 8)).toEqual(relida);
    expect(AccountActionsAPI.merge).toHaveBeenCalledWith(7, 8);
  });

  it('apagar e apagar nota não releem nada', async () => {
    ContactAPI.delete.mockResolvedValue({ data: {} });
    ContactNotesAPI.delete.mockResolvedValue({ data: {} });
    await real().apagar(7);
    await real().apagarNota(7, 31);
    expect(ContactAPI.delete).toHaveBeenCalledWith(7);
    expect(ContactNotesAPI.delete).toHaveBeenCalledWith(7, 31);
    expect(RelacionamentosAPI.pessoa).not.toHaveBeenCalled();
  });

  it('o 422 do apagar sobe com a frase do servidor', async () => {
    const recusa = Object.assign(new Error('422'), {
      response: { status: 422, data: { message: 'Está online.' } },
    });
    ContactAPI.delete.mockRejectedValue(recusa);
    await expect(real().apagar(7)).rejects.toBe(recusa);
  });

  it('buscar pessoas usa a busca da lista e tira a própria pessoa', async () => {
    RelacionamentosAPI.pessoas.mockResolvedValue({
      data: { itens: [ANA, { id: 8, name: 'Bruno' }], total: 2 },
    });
    expect(await real().buscarPessoas('an', 7)).toEqual([
      { id: 8, name: 'Bruno' },
    ]);
    expect(RelacionamentosAPI.pessoas).toHaveBeenCalledWith({ busca: 'an' });
  });

  it('as etiquetas da conta vêm com a cor, em ordem alfabética', async () => {
    LabelsAPI.get.mockResolvedValue({
      data: {
        payload: [
          { title: 'site', color: '#111' },
          { title: 'feira', color: '#222' },
        ],
      },
    });
    expect(await real().etiquetasDaConta()).toEqual([
      { nome: 'feira', cor: '#222' },
      { nome: 'site', cor: '#111' },
    ]);
  });
});

describe('escrita da empresa', () => {
  const relida = { ...PADARIA, name: 'Padaria Nova' };
  const pedido = (extra = {}) => ({
    empresa: {
      name: 'Padaria Nova',
      domain: 'padaria.exemplo.com.br',
      description: null,
      additional_attributes: { cnpj: '11222333000181', city: 'Campinas' },
      custom_attributes: { porte: 'pequeno' },
    },
    foto: null,
    apagar: [],
    ...extra,
  });
  beforeEach(() => {
    CompanyAPI.update.mockResolvedValue({ data: { payload: { id: 9 } } });
    RelacionamentosAPI.empresa.mockResolvedValue({ data: relida });
  });

  it('salvar manda a empresa do pedido como veio e relê a empresa', async () => {
    const salva = await real().salvarEmpresa(9, pedido());
    expect(salva).toEqual(relida);
    expect(CompanyAPI.update).toHaveBeenCalledTimes(1);
    expect(CompanyAPI.update).toHaveBeenCalledWith(9, {
      company: pedido().empresa,
    });
    expect(CompanyAPI.destroyAvatar).not.toHaveBeenCalled();
    expect(CompanyAPI.destroyCustomAttributes).not.toHaveBeenCalled();
    expect(RelacionamentosAPI.empresa).toHaveBeenCalledWith(9);
  });

  it('a foto nova vai num PATCH só com o arquivo; tirar a foto é o DELETE do avatar', async () => {
    const arquivo = new File(['x'], 'logo.png', { type: 'image/png' });
    await real().salvarEmpresa(9, pedido({ foto: { arquivo } }));
    const [, corpo] = CompanyAPI.update.mock.calls[1];
    expect(corpo).toBeInstanceOf(FormData);
    expect(corpo.get('company[avatar]')).toBe(arquivo);
    await real().salvarEmpresa(9, pedido({ foto: { tirar: true } }));
    expect(CompanyAPI.destroyAvatar).toHaveBeenCalledWith(9);
  });

  it('os campos esvaziados saem de verdade', async () => {
    await real().salvarEmpresa(9, pedido({ apagar: ['porte'] }));
    expect(CompanyAPI.destroyCustomAttributes).toHaveBeenCalledWith(9, [
      'porte',
    ]);
  });

  it('se só a foto falha, a falha diz que gravou em parte e traz a empresa relida', async () => {
    CompanyAPI.update
      .mockResolvedValueOnce({ data: { payload: { id: 9 } } })
      .mockRejectedValueOnce(erroHttp(422));
    const arquivo = new File(['x'], 'logo.png', { type: 'image/png' });
    await expect(
      real().salvarEmpresa(9, pedido({ foto: { arquivo } }))
    ).rejects.toMatchObject({
      name: 'GravouEmParte',
      retomada: { empresa: { id: 9 }, empresaNaFicha: relida },
    });
  });

  // #3079 — a empresa pequena sai na hora (200); a grande vai para a fila
  // do servidor (202), e a ficha avisa.
  it('apagar chama o DELETE e diz se a empresa ficou na fila do servidor', async () => {
    CompanyAPI.delete.mockResolvedValue({ status: 200 });
    expect(await real().apagarEmpresa(9)).toEqual({ naFila: false });
    expect(CompanyAPI.delete).toHaveBeenCalledWith(9);
    CompanyAPI.delete.mockResolvedValue({ status: 202 });
    expect(await real().apagarEmpresa(9)).toEqual({ naFila: true });
  });

  it('apagar empresa que não existe mais dá NAO_ACHEI', async () => {
    CompanyAPI.delete.mockRejectedValue(
      Object.assign(new Error('x'), { response: { status: 404 } })
    );
    await expect(real().apagarEmpresa(9)).rejects.toMatchObject({
      name: 'NAO_ACHEI',
    });
  });
});

describe('leituras e pessoas da empresa', () => {
  it('notas: as das pessoas da empresa, com de quem é cada uma', async () => {
    CompanyAPI.listNotes.mockResolvedValue({
      data: {
        payload: [
          {
            id: 1,
            content: 'Ligar amanhã.',
            created_at: 100,
            user: { name: 'Sônia' },
            contact: { id: 7, name: 'Ana' },
          },
          { id: 2, content: 'Sem autor.', created_at: 50, contact: null },
        ],
      },
    });
    expect(await real().notasDaEmpresa(9)).toEqual([
      {
        id: 1,
        autor: 'Sônia',
        quando: 100,
        texto: 'Ligar amanhã.',
        pessoa: { id: 7, nome: 'Ana' },
      },
      { id: 2, autor: null, quando: 50, texto: 'Sem autor.', pessoa: null },
    ]);
    expect(CompanyAPI.listNotes).toHaveBeenCalledWith(9);
  });

  it('mídias: as 5 mais novas, com o tipo da tela, de quem e quando, e o total', async () => {
    CompanyAPI.listMedia.mockResolvedValue({
      data: {
        payload: [
          {
            id: 3,
            filename: 'foto.jpg',
            file_type: 'image',
            created_at: '1970-01-01T00:01:40Z',
            contact: { id: 7, name: 'Ana' },
          },
          { id: 4, filename: 'a.pdf', file_type: 'file', created_at: null },
        ],
        meta: { total: 12 },
      },
    });
    const midias = await real().midiasDaEmpresa(9);
    expect(CompanyAPI.listMedia).toHaveBeenCalledWith(9, {
      per_page: 5,
      page: 1,
    });
    expect(midias.total).toBe(12);
    expect(midias.itens[0]).toEqual({
      id: 3,
      nome: 'foto.jpg',
      tipo: 'imagem',
      quando: 100,
      pessoa: 'Ana',
    });
    expect(midias.itens[1]).toMatchObject({ tipo: 'documento', pessoa: '' });
  });

  it('procurar quem pôr: diz em que empresa cada pessoa está hoje', async () => {
    CompanyAPI.searchContacts.mockResolvedValue({
      data: {
        payload: [
          { id: 7, name: 'Ana', company: { id: 2, name: 'Outra' } },
          { id: 8, name: 'Bia', company: null },
        ],
      },
    });
    const achadas = await real().buscarPessoasParaEmpresa(9, 'an');
    expect(CompanyAPI.searchContacts).toHaveBeenCalledWith(9, 'an');
    expect(achadas[0].empresa).toEqual({ id: 2, nome: 'Outra' });
    expect(achadas[1].empresa).toBeNull();
  });

  it('pôr e tirar usam a rota de pessoas da empresa', async () => {
    CompanyAPI.createContact.mockResolvedValue({});
    CompanyAPI.removeContact.mockResolvedValue({});
    await real().porPessoaNaEmpresa(9, 7);
    await real().tirarPessoaDaEmpresa(9, 7);
    expect(CompanyAPI.createContact).toHaveBeenCalledWith(9, {
      contact_id: 7,
    });
    expect(CompanyAPI.removeContact).toHaveBeenCalledWith(9, 7);
  });
});
