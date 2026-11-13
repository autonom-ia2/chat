import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { useRoute, useRouter } from 'vue-router';
import RelacionamentosAPI from 'dashboard/api/relacionamentos';
import SegurosAPI from 'dashboard/api/relacionamentosSeguros';
import FichaDaEmpresaPage from '../../pages/FichaDaEmpresaPage.vue';
import FichaDaPessoaPage from '../../pages/FichaDaPessoaPage.vue';
import ListaPage from '../../pages/ListaPage.vue';
import { esquecerEscritasDaCarteira } from '../../demo/carteira';
import { usarDemo } from '../../fonte/modoDemo';
import { POR_PAGINA } from '../../fonte/listaFonte';
import {
  assentar,
  carregarDemonstracao,
  daCarteira,
  semRolagem,
} from './apoio';

// Onde a carteira de seguros (#2897) entra nas páginas de Relacionamentos: a
// aba Seguros na lista e o bloco Seguros nas duas fichas. Só aparece em conta
// que tem a carteira (o payload da conta ou, na demonstração, o estado dela).
// O que cada peça faz por dentro está nos outros testes desta pasta.
// As páginas baixam as peças da carteira por import() dinâmico, que leva tempo
// de verdade: `carregarPecas` as carrega antes, e a montagem fica só por conta
// do relógio falso.
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/components-next/dialog/Dialog.vue', async () => ({
  default: (await import('./apoio')).DialogoFalso,
}));
vi.mock('dashboard/components-next/TeleportWithDirection.vue', async () => ({
  default: (await import('./apoio')).TeleportFalso,
}));
vi.mock('../../fonte/modoDemo', async importOriginal => ({
  ...(await importOriginal()),
  usarDemo: vi.fn(),
}));
// A conta aberta, como o servidor manda: `carteira_seguros` liga a carteira.
const conta = vi.hoisted(() => ({ carteira_seguros: true }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    isCloudFeatureEnabled: () => false,
    currentAccount: { value: conta },
  }),
}));
vi.mock('../../lista/usePermissoesDaLista', () => ({
  usePermissoesDaLista: () => ({
    podeCriarCards: { value: false },
    podeEtiquetar: { value: false },
    podeApagar: { value: false },
    podeTrazer: { value: false },
  }),
}));
vi.mock('../../ficha/usePermissoesDaFicha', () => ({
  usePermissoesDaFicha: () => ({
    podeEditar: { value: true },
    podeCriarCards: { value: false },
  }),
}));
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
vi.mock('dashboard/api/relacionamentosSeguros', () => ({
  default: {
    daPessoa: vi.fn(),
    daEmpresa: vi.fn(),
    seguro: vi.fn(),
    historia: vi.fn(),
  },
}));
vi.mock('vue-router', async () => {
  const { reactive } = await import('vue');
  const rota = reactive({ query: {}, params: {}, name: 'relationships_home' });
  const roteador = {
    push: vi.fn(destino => {
      if (destino.query) rota.query = destino.query;
    }),
  };
  return { useRoute: () => rota, useRouter: () => roteador };
});

withFullI18n('pt_BR');
vi.setConfig({ testTimeout: 30000 });

const rota = useRoute();
const roteador = useRouter();
const daLista = nome => `[data-relacionamentos="${nome}"]`;
const AGORA = Math.floor(Date.now() / 1000);

const ANA = {
  id: 7,
  name: 'Ana Albuquerino',
  email: 'ana.albuquerino@exemplo.com.br',
  phone_number: '+5511910310001',
  thumbnail: '',
  blocked: false,
  contact_type: 'customer',
  customer_since: AGORA,
  last_activity_at: AGORA,
  created_at: AGORA,
  additional_attributes: { city: 'Campinas', company_name: 'Padaria Bom Dia' },
  custom_attributes: {},
  labels: [],
  company_id: 9,
  opted_out_at: null,
  opt_out_source: null,
};
const PADARIA = {
  id: 9,
  name: 'Padaria Bom Dia',
  domain: 'padaria-bom-dia.exemplo.com.br',
  cnpj: '11222333000181',
  created_at: AGORA,
  contacts_count: 1,
  customers_count: 1,
  last_activity_at: AGORA,
};
const DAS_FICHAS = {
  pessoa: ANA,
  conversasDaPessoa: [],
  cardsDaPessoa: [],
  notasDaPessoa: [],
  arquivosDaPessoa: [],
  origemDaPessoa: { tipo: 'lista', nome: 'Clientes 2025', quando: AGORA },
  empresa: PADARIA,
  pessoasDaEmpresa: [ANA],
  conversasDaEmpresa: [],
  cardsDaEmpresa: [],
};
// Um seguro como o servidor manda.
const SEGURO = {
  id: 31,
  pessoaId: 7,
  pessoa: { id: 7, name: 'Ana Albuquerino', phone_number: '+5511910310001' },
  segurado: {
    tipo: 'empresa',
    id: 9,
    nome: 'Padaria Bom Dia',
    documento: null,
  },
  tipo: 'empresarial',
  ramoOriginal: null,
  seguradora: 'Horizonte Seguros',
  numero: 'HZ-000031',
  valor: 4200,
  bem: 'Loja',
  comeca: '2025-11-29',
  termina: '2026-11-29',
  selo: 'ativo',
  dias: 17,
  origem: { tipo: 'planilha', arquivo: null, em: AGORA },
  temPdf: false,
  canceladoEm: null,
  corrigidoAMao: [],
};

let aberta;
const abrir = async (Pagina, { demo = null, query = {}, params = {} } = {}) => {
  usarDemo.mockReturnValue(demo);
  rota.query = query;
  rota.params = params;
  aberta = mount(Pagina, {
    attachTo: document.body,
    global: { stubs: { transition: true } },
  });
  await assentar();
  await assentar();
  return aberta;
};
const abrirLista = (demo, query) => abrir(ListaPage, { demo, query });
const abrirPessoa = () =>
  abrir(FichaDaPessoaPage, { params: { contactId: '7' } });
const abrirEmpresa = () =>
  abrir(FichaDaEmpresaPage, { params: { companyId: '9' } });
const abas = w => w.findAll('[role="tab"]').map(aba => aba.text());
const clicar = async (w, seletor) => {
  await w.get(seletor).trigger('click');
  await assentar();
  await assentar();
};

// Na conta com a carteira a lista de pessoas da demonstração também baixa a
// carteira fictícia da lista (o grupo e a busca) e a peça do selo.
const carregarPecas = async () => {
  await carregarDemonstracao();
  await import('../../demo/carteiraNaLista.js');
  await import('../../fonte/carteiraFonte');
  await import('../../components/carteira/SeloDoSeguro.vue');
  await import('../../components/carteira/ListaDeSeguros.vue');
  await import('../../components/carteira/SegurosDaFicha.vue');
};

beforeAll(carregarPecas, 60000);
beforeEach(() => {
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
  semRolagem();
  conta.carteira_seguros = true;
  rota.name = 'relationships_home';
  Object.entries(DAS_FICHAS).forEach(([leitura, data]) =>
    RelacionamentosAPI[leitura].mockResolvedValue({ data })
  );
  SegurosAPI.daPessoa.mockResolvedValue({ data: [SEGURO] });
  SegurosAPI.daEmpresa.mockResolvedValue({ data: [SEGURO] });
});
afterEach(() => {
  vi.useRealTimers();
  aberta?.unmount();
  aberta = null;
  esquecerEscritasDaCarteira();
});

describe('a aba Seguros na lista de Relacionamentos', () => {
  it('conta com a carteira ganha a aba, e a lista de pessoas abre como sempre', async () => {
    const w = await abrirLista('cheio');

    expect(abas(w)).toEqual(['Pessoas', 'Empresas', 'Seguros']);
    expect(w.findAll(daLista('linha'))).toHaveLength(POR_PAGINA);
    expect(w.find(daCarteira('heroi')).exists()).toBe(false);
  });

  it('clicar na aba põe `?aba=seguros` no endereço e troca a tela', async () => {
    const w = await abrirLista('cheio');

    await clicar(w, daLista('aba-seguros'));

    expect(roteador.push).toHaveBeenLastCalledWith({
      query: { aba: 'seguros' },
    });
    expect(w.find(daCarteira('heroi')).exists()).toBe(true);
    expect(w.findAll(daCarteira('linha'))).toHaveLength(POR_PAGINA);
    expect(w.find(daLista('linha')).exists()).toBe(false);
  });

  it('o endereço com `?aba=seguros` abre direto na aba', async () => {
    const w = await abrirLista('cheio', { aba: 'seguros' });

    expect(w.find(daCarteira('heroi')).exists()).toBe(true);
    expect(w.get(daLista('aba-seguros')).attributes('aria-selected')).toBe(
      'true'
    );
  });

  it('voltar para Pessoas tira a aba e o seguro aberto do endereço', async () => {
    const w = await abrirLista('cheio', { aba: 'seguros', apolice: '1' });

    await clicar(w, daLista('aba-pessoas'));

    expect(roteador.push).toHaveBeenLastCalledWith({ query: {} });
    expect(w.find(daCarteira('heroi')).exists()).toBe(false);
    expect(w.findAll(daLista('linha'))).toHaveLength(POR_PAGINA);
  });

  it('ir de Seguros para Empresas leva a aba no endereço', async () => {
    const w = await abrirLista('cheio', { aba: 'seguros' });

    await clicar(w, daLista('aba-empresas'));

    expect(roteador.push).toHaveBeenLastCalledWith({
      query: { aba: 'empresas' },
    });
    expect(w.find(daCarteira('heroi')).exists()).toBe(false);
  });

  it('a aba Seguros não oferece trazer seguros', async () => {
    const w = await abrirLista('cheio', { aba: 'seguros' });

    expect(w.find(daCarteira('heroi')).exists()).toBe(true);
    expect(w.find(daCarteira('heroi-trazer')).exists()).toBe(false);
    expect(w.get(daCarteira('heroi')).text()).not.toContain('Trazer');
  });

  it('conta de outro segmento não tem a aba, e `?aba=seguros` abre Pessoas', async () => {
    const w = await abrirLista('fora-do-segmento', { aba: 'seguros' });

    expect(abas(w)).toEqual(['Pessoas', 'Empresas']);
    expect(w.find('[data-carteira]').exists()).toBe(false);
    expect(w.findAll(daLista('linha'))).toHaveLength(POR_PAGINA);
  });
});

describe('o bloco Seguros nas fichas', () => {
  it('na ficha da pessoa, fica antes das conversas', async () => {
    const w = await abrirPessoa();

    expect(SegurosAPI.daPessoa).toHaveBeenCalledWith(7);
    const bloco = w.get(daCarteira('seguros'));
    expect(bloco.get('h2').text()).toBe('Seguros (1)');
    const blocos = w.findAll('section').map(secao => secao.element);
    expect(blocos.indexOf(bloco.element)).toBeGreaterThanOrEqual(0);
    expect(blocos.indexOf(bloco.element)).toBeLessThan(
      blocos.indexOf(w.get(daLista('conversas')).element)
    );
  });

  it('o nome do segurado na gaveta leva à ficha da empresa', async () => {
    SegurosAPI.seguro.mockResolvedValue({ data: SEGURO });
    SegurosAPI.historia.mockResolvedValue({ data: [] });
    const w = await abrirPessoa();
    await clicar(w, `${daCarteira('seguro')} button`);

    await w.get(daCarteira('abrir-segurado')).trigger('click');

    expect(roteador.push).toHaveBeenLastCalledWith(
      expect.objectContaining({
        name: 'relacionamentos_empresa',
        params: expect.objectContaining({ companyId: 9 }),
      })
    );
  });

  it('na ficha da empresa, lê os seguros dela', async () => {
    const w = await abrirEmpresa();

    expect(SegurosAPI.daEmpresa).toHaveBeenCalledWith(9);
    expect(w.get(`${daCarteira('seguros-da-empresa')} h2`).text()).toBe(
      'Seguros da empresa (1)'
    );
  });

  it.each([
    ['da pessoa', abrirPessoa, ANA.name],
    ['da empresa', abrirEmpresa, PADARIA.name],
  ])(
    'conta sem a carteira: a ficha %s não mostra nem pede seguro',
    async (_, abrirFicha, nome) => {
      conta.carteira_seguros = false;

      const w = await abrirFicha();

      expect(w.find('[data-carteira]').exists()).toBe(false);
      expect(SegurosAPI.daPessoa).not.toHaveBeenCalled();
      expect(SegurosAPI.daEmpresa).not.toHaveBeenCalled();
      // A ficha abriu inteira: o título é o nome de quem ela mostra.
      expect(w.get('h1').text()).toBe(nome);
    }
  );
});
