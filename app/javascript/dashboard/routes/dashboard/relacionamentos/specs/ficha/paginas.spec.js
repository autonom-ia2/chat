import { flushPromises, mount } from '@vue/test-utils';
import { useAlert } from 'dashboard/composables';
import FichaDaPessoaPage from '../../pages/FichaDaPessoaPage.vue';
import FichaDaEmpresaPage from '../../pages/FichaDaEmpresaPage.vue';
import { esquecerEscritas } from '../../demo/ficha';

// As duas fichas inteiras (#2894), com a fonte de demonstração de verdade (sem
// atraso): carregando, cheio, vazio, erro e as ações principais.
const ID_CLIENTE_COMPLETO = 23;
const ID_RECUSOU_MANUAL = 203;
const ID_NUNCA_CONVERSOU = 39;
const ID_EMPRESA_COM_GENTE = 2;
const ID_EMPRESA_SEM_GENTE = 17;
const ID_QUE_NAO_EXISTE = 9999;

const contexto = vi.hoisted(() => ({
  demo: 'cheio',
  params: {},
  empurrar: vi.fn(),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (chave, valores) =>
      valores ? `${chave} ${JSON.stringify(valores)}` : chave,
    locale: { value: 'pt_BR' },
  }),
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ query: {}, params: contexto.params }),
  useRouter: () => ({ push: contexto.empurrar }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('../../fonte/modoDemo', () => ({ usarDemo: () => contexto.demo }));
vi.mock('../../fonte/fichaFonte', async importOriginal => {
  const original = await importOriginal();
  return {
    ...original,
    fichaFonte: opcoes => original.fichaFonte({ ...opcoes, atraso: 0 }),
  };
});

const stubs = {
  TeleportWithDirection: { template: '<div><slot /></div>' },
  Dialog: {
    template:
      '<div data-dialog><button data-confirmar @click="$emit(\'confirm\')" /></div>',
    methods: { open() {}, close() {} },
  },
};
const marca = (w, nome) => w.find(`[data-relacionamentos="${nome}"]`);

// O módulo de demonstração entra por import() dinâmico: espera o esqueleto sair.
const terminouDeCarregar = async w => {
  await vi.waitFor(() => expect(marca(w, 'carregando').exists()).toBe(false), {
    timeout: 5000,
  });
  await flushPromises();
};

const abrirPessoa = async (id, demo = 'cheio') => {
  contexto.demo = demo;
  contexto.params = { contactId: String(id) };
  const w = mount(FichaDaPessoaPage, {
    attachTo: document.body,
    global: { stubs },
  });
  await terminouDeCarregar(w);
  return w;
};
const abrirEmpresa = async (id, demo = 'cheio') => {
  contexto.demo = demo;
  contexto.params = { companyId: String(id) };
  const w = mount(FichaDaEmpresaPage, {
    attachTo: document.body,
    global: { stubs },
  });
  await terminouDeCarregar(w);
  return w;
};

beforeEach(() => {
  esquecerEscritas();
  vi.clearAllMocks();
});
afterEach(() => {
  document.body.innerHTML = '';
});

describe('FichaDaPessoaPage', () => {
  it('mostra o esqueleto enquanto carrega', () => {
    contexto.demo = 'cheio';
    contexto.params = { contactId: String(ID_CLIENTE_COMPLETO) };
    const w = mount(FichaDaPessoaPage, { global: { stubs } });
    expect(marca(w, 'carregando').attributes('aria-busy')).toBe('true');
    expect(marca(w, 'ficha-pessoa').exists()).toBe(false);
  });

  it('cliente com tudo: cabeçalho, conversas, cards, notas, arquivos e informações', async () => {
    const w = await abrirPessoa(ID_CLIENTE_COMPLETO);
    expect(w.attributes('data-relacionamentos')).toBe('pessoa');
    expect(marca(w, 'ficha-pessoa').exists()).toBe(true);
    expect(marca(w, 'conversar').exists()).toBe(true);
    expect(marca(w, 'mais-acoes').exists()).toBe(true);
    expect(marca(w, 'alterar').exists()).toBe(true);
    expect(marca(w, 'conversas').findAll('li')).toHaveLength(3);
    expect(w.findAll('[data-relacionamentos="card"]').length).toBeGreaterThan(
      0
    );
    expect(w.findAll('[data-relacionamentos="nota"]').length).toBeGreaterThan(
      0
    );
    expect(marca(w, 'arquivos').findAll('li').length).toBeGreaterThan(0);
    expect(marca(w, 'de-onde-veio').exists()).toBe(true);
    expect(w.find('[data-selo="cliente"]').exists()).toBe(true);
    expect(marca(w, 'faixa-nao-quer').exists()).toBe(false);
    expect(marca(w, 'carregando').exists()).toBe(false);
  });

  it('em 390 px a ordem é conversas, cards, informações, notas, arquivos, de onde veio', async () => {
    const w = await abrirPessoa(ID_CLIENTE_COMPLETO);
    const ordem = [
      'conversas',
      'cards',
      'informacoes',
      'notas',
      'arquivos',
      'de-onde-veio',
    ].map(nome =>
      marca(w, nome)
        .classes()
        .find(c => c.startsWith('order-') && c !== 'order-none')
    );
    expect(ordem).toEqual([
      'order-1',
      'order-2',
      'order-3',
      'order-4',
      'order-5',
      'order-6',
    ]);
  });

  it('quem nunca conversou: conversas e arquivos vazios, com uma ação cada', async () => {
    const w = await abrirPessoa(ID_NUNCA_CONVERSOU);
    expect(marca(w, 'conversas').find('[data-vazio]').exists()).toBe(true);
    expect(marca(w, 'arquivos').find('li').exists()).toBe(false);
    expect(marca(w, 'marcar-cliente').exists()).toBe(true);
  });

  it('Marcar como cliente simula e o selo aparece', async () => {
    const w = await abrirPessoa(ID_NUNCA_CONVERSOU);
    await marca(w, 'marcar-cliente').trigger('click');
    await vi.waitFor(() =>
      expect(useAlert).toHaveBeenCalledWith(
        expect.stringContaining('CLIENTE_MARCADO')
      )
    );
    expect(w.find('[data-selo="cliente"]').exists()).toBe(true);
    expect(marca(w, 'marcar-cliente').exists()).toBe(false);
  });

  it('quem pediu para parar tem a faixa e Liberar, depois de confirmar, a tira', async () => {
    const w = await abrirPessoa(ID_RECUSOU_MANUAL);
    expect(marca(w, 'faixa-nao-quer').exists()).toBe(true);
    await w.get('[data-confirmar]').trigger('click');
    await vi.waitFor(() =>
      expect(useAlert).toHaveBeenCalledWith(
        expect.stringContaining('FAIXA.LIBERADO')
      )
    );
    expect(marca(w, 'faixa-nao-quer').exists()).toBe(false);
  });

  it('Guardar a nota põe a nota no topo e limpa a caixa', async () => {
    const w = await abrirPessoa(ID_CLIENTE_COMPLETO);
    const caixa = marca(w, 'nota-caixa');
    await caixa.setValue('Mandar a proposta amanhã.');
    await marca(w, 'guardar-nota').trigger('click');
    await vi.waitFor(() =>
      expect(useAlert).toHaveBeenCalledWith(
        expect.stringContaining('NOTAS.GUARDADA')
      )
    );
    expect(w.findAll('[data-relacionamentos="nota"]')[0].text()).toContain(
      'Mandar a proposta amanhã.'
    );
    expect(caixa.element.value).toBe('');
  });

  it('Alterar abre a gaveta; salvar fecha e a ficha mostra o novo valor com um aviso', async () => {
    const w = await abrirPessoa(ID_CLIENTE_COMPLETO);
    expect(marca(w, 'gaveta-informacoes').exists()).toBe(false);
    await marca(w, 'alterar').trigger('click');
    expect(marca(w, 'gaveta-informacoes').exists()).toBe(true);
    await marca(w, 'gaveta-informacoes')
      .get('[data-foco]')
      .setValue('Nome Novo da Silva');
    await marca(w, 'salvar-informacoes').trigger('click');
    await vi.waitFor(() =>
      expect(useAlert).toHaveBeenCalledWith(
        expect.stringContaining('GAVETA.SALVO')
      )
    );
    expect(marca(w, 'gaveta-informacoes').exists()).toBe(false);
    expect(w.get('h1').text()).toBe('Nome Novo da Silva');
  });

  it('"Alterar informações" do ⋯ também abre a gaveta; as outras só avisam', async () => {
    const w = await abrirPessoa(ID_CLIENTE_COMPLETO);
    await marca(w, 'mais-acoes').trigger('click');
    await w.findAll('.n-dropdown-item button')[1].trigger('click');
    expect(useAlert).toHaveBeenCalledWith(
      expect.stringContaining('AVISOS.JUNTAR')
    );
    expect(marca(w, 'gaveta-informacoes').exists()).toBe(false);
    await marca(w, 'mais-acoes').trigger('click');
    await w.findAll('.n-dropdown-item button')[0].trigger('click');
    expect(marca(w, 'gaveta-informacoes').exists()).toBe(true);
  });

  it('Conversar e Novo card avisam o que vai acontecer', async () => {
    const w = await abrirPessoa(ID_CLIENTE_COMPLETO);
    await marca(w, 'conversar').trigger('click');
    expect(useAlert).toHaveBeenCalledWith(
      expect.stringContaining('AVISOS.CONVERSAR')
    );
  });

  it('clicar num card abre a gaveta dele, e Abrir no CRM leva à rota real', async () => {
    const w = await abrirPessoa(ID_CLIENTE_COMPLETO);
    await w.findAll('[data-relacionamentos="card"]')[0].trigger('click');
    expect(marca(w, 'gaveta-card').exists()).toBe(true);
    await marca(w, 'gaveta-card').get('[data-foco]').trigger('click');
    expect(contexto.empurrar).toHaveBeenCalledWith({
      name: 'crm_kanban_index',
      params: undefined,
      query: undefined,
    });
    await vi.waitFor(() =>
      expect(marca(w, 'gaveta-card').exists()).toBe(false)
    );
  });

  it('o link de volta leva à lista', async () => {
    const w = await abrirPessoa(ID_CLIENTE_COMPLETO);
    await marca(w, 'voltar').trigger('click');
    expect(contexto.empurrar).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'relationships_home' })
    );
  });

  it('pessoa que não existe: uma frase e Voltar para a lista', async () => {
    const w = await abrirPessoa(ID_QUE_NAO_EXISTE);
    expect(marca(w, 'vazio').text()).toContain('NAO_ACHEI_PESSOA');
    await marca(w, 'vazio').get('button').trigger('click');
    expect(contexto.empurrar).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'relationships_home' })
    );
  });

  it('conta vazia: não acha a pessoa', async () => {
    const w = await abrirPessoa(ID_CLIENTE_COMPLETO, 'vazio');
    expect(marca(w, 'vazio').exists()).toBe(true);
  });

  it('erro: mostra a frase e o botão, e Tentar de novo carrega outra vez', async () => {
    const w = await abrirPessoa(ID_CLIENTE_COMPLETO, null);
    expect(marca(w, 'erro').exists()).toBe(true);
    expect(marca(w, 'ficha-pessoa').exists()).toBe(false);
    contexto.demo = 'cheio';
    await marca(w, 'erro').get('button').trigger('click');
    await flushPromises();
    expect(marca(w, 'ficha-pessoa').exists()).toBe(false);
  });
});

describe('FichaDaEmpresaPage', () => {
  it('mostra o esqueleto enquanto carrega', () => {
    contexto.demo = 'cheio';
    contexto.params = { companyId: String(ID_EMPRESA_COM_GENTE) };
    const w = mount(FichaDaEmpresaPage, { global: { stubs } });
    expect(marca(w, 'carregando').exists()).toBe(true);
  });

  it('cheia: cabeçalho, pessoas, conversas, cards e informações', async () => {
    const w = await abrirEmpresa(ID_EMPRESA_COM_GENTE);
    expect(w.attributes('data-relacionamentos')).toBe('empresa');
    expect(marca(w, 'ficha-empresa').exists()).toBe(true);
    expect(marca(w, 'pessoas-da-empresa').findAll('li').length).toBeGreaterThan(
      0
    );
    expect(marca(w, 'conversas').exists()).toBe(true);
    expect(marca(w, 'cards').exists()).toBe(true);
    expect(marca(w, 'informacoes').text()).toContain(
      'EMPRESA.INFORMACOES.CNPJ'
    );
  });

  it('uma pessoa da lista leva à ficha dela', async () => {
    const w = await abrirEmpresa(ID_EMPRESA_COM_GENTE);
    await w.get('[data-relacionamentos="pessoa-da-empresa"]').trigger('click');
    expect(contexto.empurrar).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'relacionamentos_pessoa' })
    );
  });

  it('sem pessoas: uma frase', async () => {
    const w = await abrirEmpresa(ID_EMPRESA_SEM_GENTE);
    expect(marca(w, 'pessoas-da-empresa').text()).toContain('PESSOAS_VAZIO');
  });

  it('o link de volta leva à aba de empresas', async () => {
    const w = await abrirEmpresa(ID_EMPRESA_COM_GENTE);
    await marca(w, 'voltar').trigger('click');
    expect(contexto.empurrar).toHaveBeenCalledWith({
      name: 'relationships_home',
      params: undefined,
      query: { aba: 'empresas' },
    });
  });

  it('empresa que não existe e erro', async () => {
    const naoAchei = await abrirEmpresa(ID_QUE_NAO_EXISTE);
    expect(marca(naoAchei, 'vazio').text()).toContain('NAO_ACHEI_EMPRESA');
    const erro = await abrirEmpresa(ID_EMPRESA_COM_GENTE, null);
    expect(marca(erro, 'erro').exists()).toBe(true);
  });
});
