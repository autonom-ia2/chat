import CompanyAPI from 'dashboard/api/companies';
import ContactNotesAPI from 'dashboard/api/contactNotes';
import ContactAPI from 'dashboard/api/contacts';
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
  },
}));
vi.mock('dashboard/api/contacts', () => ({
  default: {
    update: vi.fn(),
    markCustomer: vi.fn(),
    removeCustomer: vi.fn(),
    removeOptOut: vi.fn(),
  },
}));
vi.mock('dashboard/api/contactNotes', () => ({
  default: { create: vi.fn() },
}));
vi.mock('dashboard/api/companies', () => ({
  default: { update: vi.fn() },
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
  ['salvarEmpresa', () => CompanyAPI.update, [9, { name: 'Padaria' }]],
];

afterEach(() => {
  vi.resetAllMocks();
});

describe('leituras', () => {
  it('não é a demonstração e tem os 16 métodos', () => {
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
  });

  it('salvar manda os dados como a gaveta montou e relê a pessoa', async () => {
    const dados = {
      name: 'Ana Maria',
      phone_number: null,
      email: 'ana@exemplo.com.br',
      additional_attributes: { city: 'Bauru', company_name: '' },
      custom_attributes: { cpf: '52998224725' },
    };
    ContactAPI.update.mockResolvedValue({ data: { payload: {} } });
    expect(await real().salvar(7, dados)).toEqual(relida);
    expect(ContactAPI.update).toHaveBeenCalledWith(7, dados);
    expect(RelacionamentosAPI.pessoa).toHaveBeenCalledWith(7);
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

describe('escrita da empresa', () => {
  const relida = { ...PADARIA, name: 'Padaria Nova' };
  beforeEach(() => {
    CompanyAPI.update.mockResolvedValue({ data: { payload: {} } });
    RelacionamentosAPI.empresa.mockResolvedValue({ data: relida });
  });

  it('salvar manda nome e site, o CNPJ em additional_attributes, e relê a empresa', async () => {
    const salva = await real().salvarEmpresa(9, {
      name: 'Padaria Nova',
      cnpj: '11222333000181',
      domain: 'padaria.exemplo.com.br',
    });
    expect(salva).toEqual(relida);
    expect(CompanyAPI.update).toHaveBeenCalledWith(9, {
      company: {
        name: 'Padaria Nova',
        domain: 'padaria.exemplo.com.br',
        additional_attributes: { cnpj: '11222333000181' },
      },
    });
    expect(RelacionamentosAPI.empresa).toHaveBeenCalledWith(9);
  });

  // No banco o site e o CNPJ são únicos por conta quando não são nulos: texto
  // vazio em duas empresas bateria uma na outra.
  it('site e CNPJ apagados vão como null, nunca como texto vazio', async () => {
    await real().salvarEmpresa(9, { name: 'Padaria', cnpj: '', domain: '' });
    expect(CompanyAPI.update).toHaveBeenCalledWith(9, {
      company: {
        name: 'Padaria',
        domain: null,
        additional_attributes: { cnpj: null },
      },
    });
  });
});
