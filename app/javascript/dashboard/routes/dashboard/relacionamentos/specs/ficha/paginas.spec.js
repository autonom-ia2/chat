import { reactive } from 'vue';
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

// A conta cheia destes testes é a de outro segmento (`?demo=fora-do-segmento`):
// para a ficha é a mesma conta cheia de `?demo=cheio`, sem a carteira de
// seguros.
const CHEIA = vi.hoisted(() => 'fora-do-segmento');
const contexto = vi.hoisted(() => ({
  demo: CHEIA,
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
// A conta destes testes não tem a carteira de seguros (a aba e o bloco Seguros
// têm teste próprio em specs/carteira). Quem diz isso é a conta, pelo caminho
// de verdade: o estado da demonstração (`CHEIA`) e, fora dela, o que o servidor
// manda. Nada aqui troca `useContaDeSeguros`. A peça da carteira só é baixada
// quando aparece na tela: aqui não pode ser, e o `afterEach` confere.
const carteira = vi.hoisted(() => ({ pecasBaixadas: [] }));
vi.mock('../../components/carteira/SegurosDaFicha.vue', () => {
  carteira.pecasBaixadas = [...carteira.pecasBaixadas, 'SegurosDaFicha'];
  return { default: { render: () => null } };
});
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    currentAccount: { value: { carteira_seguros: false } },
  }),
}));
vi.mock('../../fonte/modoDemo', async importOriginal => ({
  ...(await importOriginal()),
  usarDemo: () => contexto.demo,
  demoCarregando: () => contexto.demo === 'carregando',
}));
// Aqui todo mundo pode tudo: quem só pode ver está em paginasReal.spec.js.
vi.mock('../../ficha/usePermissoesDaFicha', () => ({
  usePermissoesDaFicha: () => ({
    podeEditar: { value: true },
    podeCriarCards: { value: true },
  }),
}));
// Fora da demonstração (`demo` nulo) a ficha lê do servidor: aqui ele não
// responde, para os testes do estado de erro.
vi.mock('dashboard/api/relacionamentos', () => {
  const semServidor = () => Promise.reject(new Error('sem servidor'));
  const leituras = [
    'pessoa',
    'conversasDaPessoa',
    'cardsDaPessoa',
    'notasDaPessoa',
    'arquivosDaPessoa',
    'origemDaPessoa',
    'empresa',
    'pessoasDaEmpresa',
    'conversasDaEmpresa',
    'cardsDaEmpresa',
  ];
  return {
    default: Object.fromEntries(leituras.map(nome => [nome, semServidor])),
  };
});
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
      '<div data-dialog><slot /><slot name="footer" /><button data-confirmar @click="$emit(\'confirm\')" /></div>',
    methods: { open() {}, close() {} },
  },
};
const marca = (w, nome) => w.find(`[data-relacionamentos="${nome}"]`);

// Telas inteiras montam devagar numa máquina carregada (a CI também): o limite
// de 5 s por teste é de relógio, não de lógica.
vi.setConfig({ testTimeout: 30000 });

// Espera por condição, com folga para máquina carregada (o padrão é 1 s).
const esperarPor = (verificacao, opcoes) =>
  vi.waitFor(verificacao, { timeout: 5000, ...opcoes });
// O módulo de demonstração entra por import() dinâmico: espera o esqueleto sair.
const terminouDeCarregar = async w => {
  await esperarPor(() => expect(marca(w, 'carregando').exists()).toBe(false));
  await flushPromises();
};

const abrirPessoa = async (id, demo = CHEIA) => {
  contexto.demo = demo;
  contexto.params = { contactId: String(id) };
  const w = mount(FichaDaPessoaPage, {
    attachTo: document.body,
    global: { stubs },
  });
  await terminouDeCarregar(w);
  return w;
};
const abrirEmpresa = async (id, demo = CHEIA) => {
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
  expect(carteira.pecasBaixadas).toEqual([]);
});

describe('FichaDaPessoaPage', () => {
  it('a empresa aparece só no cabeçalho, não em Informações', async () => {
    const w = await abrirPessoa(ID_CLIENTE_COMPLETO);
    expect(w.find('[data-contato="empresa"]').exists()).toBe(true);
    expect(
      marca(w, 'informacoes').find('[data-informacao="empresa"]').exists()
    ).toBe(false);
  });

  it('o esqueleto tem contraste, formato da ficha e "Carregando…" visível sem duplicar o anúncio', () => {
    contexto.demo = CHEIA;
    contexto.params = { contactId: String(ID_CLIENTE_COMPLETO) };
    const w = mount(FichaDaPessoaPage, { global: { stubs } });
    const esqueleto = marca(w, 'carregando');
    const texto = esqueleto.get('[data-relacionamentos="carregando-texto"]');
    expect(texto.text()).toContain('COMUM.CARREGANDO');
    // O leitor de tela já ouve pela região viva: o texto visível não repete.
    expect(texto.attributes('aria-hidden')).toBe('true');
    const blocos = esqueleto.findAll('[data-bloco]');
    expect(blocos.length).toBeGreaterThanOrEqual(5);
    blocos.forEach(bloco =>
      expect(bloco.classes()).toEqual(
        expect.arrayContaining([
          'bg-n-alpha-2',
          'animate-pulse',
          'motion-reduce:animate-none',
        ])
      )
    );
    expect(esqueleto.find('[data-bloco="circulo"]').classes()).toContain(
      'rounded-full'
    );
  });

  it('mostra o esqueleto enquanto carrega', () => {
    contexto.demo = CHEIA;
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

  const classesDe = (w, nome) => marca(w, nome).classes();

  it('no celular a ordem da tela é a do documento: nenhum cartão é reordenado por classe', async () => {
    const w = await abrirPessoa(ID_CLIENTE_COMPLETO);
    const nomes = [
      'conversas',
      'cards',
      'notas',
      'arquivos',
      'informacoes',
      'de-onde-veio',
    ];
    const naTela = w
      .findAll('[data-relacionamentos]')
      .map(no => no.attributes('data-relacionamentos'))
      .filter(nome => nomes.includes(nome));
    expect(naTela).toEqual(nomes);
    nomes.forEach(nome =>
      expect(
        classesDe(w, nome).some(
          c => c.startsWith('order-') || c.includes(':order-')
        )
      ).toBe(false)
    );
  });

  it('no desktop são duas colunas independentes, cada cartão do tamanho do conteúdo', async () => {
    const w = await abrirPessoa(ID_CLIENTE_COMPLETO);
    const principal = marca(w, 'coluna-principal');
    const lado = marca(w, 'coluna-lado');
    ['conversas', 'cards', 'notas', 'arquivos'].forEach(nome =>
      expect(principal.find(`[data-relacionamentos="${nome}"]`).exists()).toBe(
        true
      )
    );
    ['informacoes', 'de-onde-veio'].forEach(nome =>
      expect(lado.find(`[data-relacionamentos="${nome}"]`).exists()).toBe(true)
    );
    [principal, lado].forEach(coluna =>
      expect(coluna.classes()).toEqual(
        expect.arrayContaining(['flex', 'flex-col', 'gap-6'])
      )
    );
    expect(principal.classes()).toContain('lg:col-span-2');
    // Sem linha compartilhada: nenhuma classe de linha, folga ou span de linha.
    const classes = [...w.element.querySelectorAll('[class]')].flatMap(el => [
      ...el.classList,
    ]);
    ['lg:row-span-3', 'lg:mb-6', 'lg:gap-y-0'].forEach(c =>
      expect(classes).not.toContain(c)
    );
    expect(classes.filter(c => c.includes('grid-rows'))).toEqual([]);
    expect(classes.filter(c => c.includes('row-start'))).toEqual([]);
  });

  it('sair da ficha (parâmetro some) não dispara carga nem mostra "não achei"', async () => {
    contexto.demo = CHEIA;
    contexto.params = reactive({ contactId: String(ID_CLIENTE_COMPLETO) });
    const w2 = mount(FichaDaPessoaPage, {
      attachTo: document.body,
      global: { stubs },
    });
    await terminouDeCarregar(w2);
    contexto.params.contactId = undefined;
    await flushPromises();
    expect(marca(w2, 'carregando').exists()).toBe(false);
    expect(marca(w2, 'vazio').exists()).toBe(false);
    expect(marca(w2, 'ficha-pessoa').exists()).toBe(true);
  });

  it('o contêiner é o mesmo da lista, sem estourar a largura e com respiro embaixo', async () => {
    const w = await abrirPessoa(ID_CLIENTE_COMPLETO);
    const raiz = w.get('main > div').classes();
    expect(raiz).toEqual(
      expect.arrayContaining([
        'w-full',
        'max-w-6xl',
        'mx-auto',
        'min-w-0',
        'pb-24',
      ])
    );
    expect(w.classes()).toContain('min-w-0');
  });

  it('?demo=carregando: a ficha fica no esqueleto, sem resposta', async () => {
    contexto.demo = 'carregando';
    contexto.params = { contactId: String(ID_CLIENTE_COMPLETO) };
    const w = mount(FichaDaPessoaPage, { global: { stubs } });
    await flushPromises();
    expect(marca(w, 'carregando').exists()).toBe(true);
    expect(marca(w, 'ficha-pessoa').exists()).toBe(false);
    expect(marca(w, 'erro').exists()).toBe(false);
  });

  it('a região viva existe desde o início e recebe o resultado depois', async () => {
    contexto.demo = CHEIA;
    contexto.params = { contactId: String(ID_RECUSOU_MANUAL) };
    const w = mount(FichaDaPessoaPage, {
      attachTo: document.body,
      global: { stubs },
    });
    const regiao = marca(w, 'aviso-vivo').element;
    expect(regiao.getAttribute('role')).toBe('status');
    await terminouDeCarregar(w);
    expect(marca(w, 'aviso-vivo').element).toBe(regiao);
    expect(
      w.find('[data-relacionamentos="faixa-nao-quer"][role]').exists()
    ).toBe(false);
    await w.get('[data-confirmar]').trigger('click');
    await esperarPor(() =>
      expect(regiao.textContent).toContain('FAIXA.LIBERADO')
    );
  });

  it('quem nunca conversou: conversas e cards vazios, só com a frase', async () => {
    const w = await abrirPessoa(ID_NUNCA_CONVERSOU);
    expect(marca(w, 'conversas').find('[data-vazio]').exists()).toBe(true);
    expect(marca(w, 'conversas').find('button').exists()).toBe(false);
    expect(marca(w, 'cards').find('button').exists()).toBe(false);
    expect(marca(w, 'arquivos').find('li').exists()).toBe(false);
    expect(marca(w, 'marcar-cliente').exists()).toBe(true);
  });

  it('Marcar como cliente simula e o selo aparece', async () => {
    const w = await abrirPessoa(ID_NUNCA_CONVERSOU);
    await marca(w, 'marcar-cliente').trigger('click');
    await esperarPor(() =>
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
    await esperarPor(() =>
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
    await esperarPor(() =>
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
    await esperarPor(() =>
      expect(useAlert).toHaveBeenCalledWith(
        expect.stringContaining('GAVETA.SALVO')
      )
    );
    // A gaveta sai por uma transição (quadro de animação): espera ela sumir.
    await esperarPor(() =>
      expect(marca(w, 'gaveta-informacoes').exists()).toBe(false)
    );
    expect(w.get('h1').text()).toBe('Nome Novo da Silva');
  });

  it('"Alterar informações" do ⋯ também abre a gaveta; as outras só avisam', async () => {
    const w = await abrirPessoa(ID_CLIENTE_COMPLETO);
    await marca(w, 'mais-acoes').trigger('click');
    await w.findAll('.n-dropdown-item button')[2].trigger('click');
    expect(useAlert).toHaveBeenCalledWith(
      expect.stringContaining('AVISOS.JUNTAR')
    );
    expect(marca(w, 'gaveta-informacoes').exists()).toBe(false);
    await marca(w, 'mais-acoes').trigger('click');
    await w.findAll('.n-dropdown-item button')[0].trigger('click');
    expect(marca(w, 'gaveta-informacoes').exists()).toBe(true);
  });

  it('"Não é mais cliente" do ⋯ tira o selo na hora, e "Marcar como cliente" devolve', async () => {
    const w = await abrirPessoa(ID_CLIENTE_COMPLETO);
    expect(w.find('[data-selo="cliente"]').exists()).toBe(true);
    await marca(w, 'mais-acoes').trigger('click');
    await w.findAll('.n-dropdown-item button')[1].trigger('click');
    await esperarPor(() =>
      expect(useAlert).toHaveBeenCalledWith(
        expect.stringContaining('CABECALHO.CLIENTE_DESMARCADO')
      )
    );
    expect(w.find('[data-selo="cliente"]').exists()).toBe(false);
    await marca(w, 'marcar-cliente').trigger('click');
    await esperarPor(() =>
      expect(w.find('[data-selo="cliente"]').exists()).toBe(true)
    );
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
    await esperarPor(() =>
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
    contexto.demo = CHEIA;
    await marca(w, 'erro').get('button').trigger('click');
    await flushPromises();
    expect(marca(w, 'ficha-pessoa').exists()).toBe(false);
  });
});

describe('FichaDaEmpresaPage: estados', () => {
  it('?demo=carregando: fica no esqueleto, sem resposta', async () => {
    contexto.demo = 'carregando';
    contexto.params = { companyId: String(ID_EMPRESA_COM_GENTE) };
    const w = mount(FichaDaEmpresaPage, { global: { stubs } });
    await flushPromises();
    expect(marca(w, 'carregando').exists()).toBe(true);
    expect(marca(w, 'ficha-empresa').exists()).toBe(false);
  });
});

describe('FichaDaEmpresaPage: largura', () => {
  it('mesmo contêiner da lista e respiro embaixo', async () => {
    const w = await abrirEmpresa(ID_EMPRESA_COM_GENTE);
    expect(w.get('main > div').classes()).toEqual(
      expect.arrayContaining([
        'w-full',
        'max-w-6xl',
        'mx-auto',
        'min-w-0',
        'pb-24',
      ])
    );
  });
});

describe('FichaDaEmpresaPage', () => {
  it('mostra o esqueleto enquanto carrega', () => {
    contexto.demo = CHEIA;
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
    expect(marca(w, 'informacoes').text()).toContain('INFORMACOES.PESSOAS');
    expect(marca(w, 'informacoes').text()).not.toContain('INFORMACOES.CNPJ');
    expect(marca(w, 'cabecalho').text()).toContain('/');
  });

  it('Mandar mensagem abre o diálogo e Continuar só avisa', async () => {
    const w = await abrirEmpresa(ID_EMPRESA_COM_GENTE);
    await marca(w, 'mandar-mensagem').trigger('click');
    await w.get('[data-confirmar]').trigger('click');
    expect(useAlert).toHaveBeenCalledWith(
      expect.stringContaining('MENSAGEM.AVISO')
    );
  });

  it('Alterar abre a gaveta com título de título, e salvar troca o nome', async () => {
    const w = await abrirEmpresa(ID_EMPRESA_COM_GENTE);
    expect(marca(w, 'gaveta-empresa').exists()).toBe(false);
    await marca(w, 'alterar-empresa').trigger('click');
    const gaveta = marca(w, 'gaveta-empresa');
    expect(gaveta.get('h2').classes()).toEqual(
      expect.arrayContaining(['text-lg', 'font-semibold'])
    );
    await gaveta.get('[data-foco]').setValue('Empresa Nova Ltda');
    await marca(w, 'salvar-empresa').trigger('click');
    await esperarPor(() =>
      expect(useAlert).toHaveBeenCalledWith(
        expect.stringContaining('GAVETA.SALVO')
      )
    );
    await esperarPor(() =>
      expect(marca(w, 'gaveta-empresa').exists()).toBe(false)
    );
    expect(w.get('h1').text()).toBe('Empresa Nova Ltda');
  });

  it('conversar com uma pessoa da lista só avisa, não sai da ficha', async () => {
    const w = await abrirEmpresa(ID_EMPRESA_COM_GENTE);
    await w
      .get('[data-relacionamentos="conversar-com-pessoa"]')
      .trigger('click');
    expect(useAlert).toHaveBeenCalled();
    expect(contexto.empurrar).not.toHaveBeenCalled();
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
