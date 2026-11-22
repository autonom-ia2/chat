import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { useAlert } from 'dashboard/composables';
import CompanyAPI from 'dashboard/api/companies';
import ContactNotesAPI from 'dashboard/api/contactNotes';
import ContactAPI from 'dashboard/api/contacts';
import RelacionamentosAPI from 'dashboard/api/relacionamentos';
import FichaDaPessoaPage from '../../pages/FichaDaPessoaPage.vue';
import FichaDaEmpresaPage from '../../pages/FichaDaEmpresaPage.vue';

// As duas fichas fora da demonstração (#2895): leem do servidor pelas leituras
// novas, escrevem pelos endpoints que o painel já tem, mostram cada erro no
// lugar certo, levam às rotas reais e escondem a escrita de quem só pode ver.
// O que ainda só avisa não aparece aqui (#2970): "Mandar mensagem" da empresa
// e o ícone de conversar de cada pessoa. As ações que vieram da ficha antiga
// (#3071) têm o próprio arquivo: acoesReais.spec.js.
const contexto = vi.hoisted(() => ({ params: {}, empurrar: vi.fn() }));
const pode = vi.hoisted(() => ({ editar: true, criarCards: true }));
const conversaNova = vi.hoisted(() => ({ abrir: vi.fn() }));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
// A conta destes testes não tem a carteira de seguros (a aba e o bloco Seguros
// têm teste próprio em specs/carteira). Quem diz isso é a conta que o servidor
// manda, pelo caminho de verdade: nada aqui troca `useContaDeSeguros`. A peça
// da carteira só é baixada quando aparece na tela: aqui não pode ser, e o
// `afterEach` confere.
const carteira = vi.hoisted(() => ({ pecasBaixadas: [] }));
vi.mock('../../components/carteira/SegurosDaFicha.vue', () => {
  carteira.pecasBaixadas = [...carteira.pecasBaixadas, 'SegurosDaFicha'];
  return { default: { render: () => null } };
});
// #3071 — o "Ligar" é o VoiceCallButton da casa (ele decide se aparece).
vi.mock('dashboard/components-next/Contacts/VoiceCallButton.vue', () => ({
  default: { props: ['phone'], template: '<button data-ligar />' },
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    currentAccount: { value: { carteira_seguros: false } },
    isCloudFeatureEnabled: () => false,
  }),
}));
vi.mock('dashboard/components-next/dialog/Dialog.vue', async () => ({
  default: (await import('../lista/dialogoFalso')).DialogoFalso,
}));
vi.mock('dashboard/components-next/TeleportWithDirection.vue', async () => ({
  default: (await import('../lista/teleportFalso')).TeleportFalso,
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ query: {}, params: contexto.params }),
  useRouter: () => ({ push: contexto.empurrar }),
}));
vi.mock('../../fonte/modoDemo', async importOriginal => ({
  ...(await importOriginal()),
  usarDemo: () => null,
}));
vi.mock('../../ficha/usePermissoesDaFicha', () => ({
  usePermissoesDaFicha: () => ({
    podeEditar: {
      get value() {
        return pode.editar;
      },
    },
    podeCriarCards: {
      get value() {
        return pode.criarCards;
      },
    },
    podeExportar: { value: false },
    podeApagar: { value: false },
    podeCriarLembrete: { value: false },
  }),
}));
// #3071 — as caixas da conta (para "Ligar") vêm do store: aqui não há voz.
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({ value: [] }),
}));
// A "Nova conversa" da casa lê o contato do store: aqui só se vê se abriu.
vi.mock('../../components/carteira/ConversaNova.vue', () => ({
  default: {
    render: () => null,
    methods: { abrir: id => conversaNova.abrir(id) },
  },
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
  default: { update: vi.fn(), listNotes: vi.fn(), listMedia: vi.fn() },
}));

withFullI18n('pt_BR');
vi.setConfig({ testTimeout: 30000 });

const marca = nome => `[data-relacionamentos="${nome}"]`;
const AGORA = Math.floor(Date.now() / 1000);
const DIA = 86_400;

const ANA = {
  id: 7,
  name: 'Ana Albuquerino',
  email: 'ana.albuquerino@exemplo.com.br',
  phone_number: '+5511910310001',
  thumbnail: '',
  blocked: false,
  contact_type: 'lead',
  customer_since: null,
  last_activity_at: AGORA - DIA,
  created_at: AGORA - 90 * DIA,
  additional_attributes: { city: 'Campinas', company_name: 'Padaria Bom Dia' },
  custom_attributes: {},
  labels: ['feira'],
  company_id: 9,
  opted_out_at: null,
  opt_out_source: null,
};
const PADARIA = {
  id: 9,
  name: 'Padaria Bom Dia',
  domain: 'padaria-bom-dia.exemplo.com.br',
  cnpj: '11222333000181',
  created_at: AGORA - 200 * DIA,
  contacts_count: 1,
  customers_count: 0,
  last_activity_at: AGORA - DIA,
};
const CONVERSAS = [
  {
    id: 55,
    canal: 'outro',
    trecho: null,
    quando: AGORA - DIA,
    situacao: 'adiada',
  },
  {
    id: 41,
    canal: 'whatsapp',
    trecho: 'Bom dia! Chegou o que eu pedi?',
    quando: AGORA - 9 * DIA,
    situacao: 'resolvida',
  },
];
const CARDS = [
  {
    id: 3,
    titulo: 'Plano mensal',
    funil: 'Vendas',
    etapa: 'Proposta',
    valor: null,
    situacao: 'estado_novo',
  },
];
const DA_PESSOA = {
  pessoa: ANA,
  conversasDaPessoa: CONVERSAS,
  cardsDaPessoa: CARDS,
  notasDaPessoa: [
    { id: 1, autor: 'Sônia Valtorini', quando: AGORA - DIA, texto: 'Ligar.' },
  ],
  arquivosDaPessoa: [
    { id: 2, nome: 'comprovante.pdf', tipo: 'documento', quando: AGORA - DIA },
  ],
  origemDaPessoa: {
    tipo: 'lista',
    nome: 'Clientes 2025',
    quando: AGORA - 90 * DIA,
  },
};
const DA_EMPRESA = {
  empresa: PADARIA,
  pessoasDaEmpresa: [ANA],
  conversasDaEmpresa: [{ ...CONVERSAS[1], pessoa: 'Ana Albuquerino' }],
  cardsDaEmpresa: [{ ...CARDS[0], pessoa: 'Ana Albuquerino' }],
};
const erroHttp = status =>
  Object.assign(new Error(`Request failed with status code ${status}`), {
    response: { status, data: { error: 'pedido recusado' } },
  });
const servidorResponde = () => {
  Object.entries({ ...DA_PESSOA, ...DA_EMPRESA }).forEach(([metodo, data]) =>
    RelacionamentosAPI[metodo].mockResolvedValue({ data })
  );
  // #3078 — as notas das pessoas da empresa vêm da rota de empresas.
  CompanyAPI.listNotes.mockResolvedValue({ data: { payload: [] } });
  CompanyAPI.listMedia.mockResolvedValue({
    data: { payload: [], meta: { total: 0 } },
  });
};

let aberta;
const abrir = async (Pagina, params) => {
  contexto.params = params;
  aberta = mount(Pagina, {
    attachTo: document.body,
    global: { stubs: { transition: true } },
  });
  await flushPromises();
  return aberta;
};
const abrirPessoa = () => abrir(FichaDaPessoaPage, { contactId: '7' });
const abrirEmpresa = () => abrir(FichaDaEmpresaPage, { companyId: '9' });

beforeEach(() => {
  pode.editar = true;
  pode.criarCards = true;
  servidorResponde();
});

afterEach(() => {
  aberta?.unmount();
  aberta = null;
  vi.resetAllMocks();
  expect(carteira.pecasBaixadas).toEqual([]);
});

describe('ficha da pessoa com os dados do servidor', () => {
  it('pede tudo pelo id e mostra o que voltou', async () => {
    const w = await abrirPessoa();
    Object.keys(DA_PESSOA).forEach(metodo =>
      expect(RelacionamentosAPI[metodo]).toHaveBeenCalledWith(7)
    );
    expect(w.get('h1').text()).toBe('Ana Albuquerino');
    expect(w.get(marca('conversas')).text()).toContain(
      'Bom dia! Chegou o que eu pedi?'
    );
    expect(w.get(marca('notas')).text()).toContain('Sônia Valtorini');
    expect(w.get(marca('arquivos')).text()).toContain('comprovante');
    expect(w.get(marca('de-onde-veio')).text()).toContain('Clientes 2025');
  });

  it('conversa de outro canal, adiada e sem trecho aparece em palavras', async () => {
    const w = await abrirPessoa();
    const primeira = w.get(`${marca('conversas')} li`);
    expect(primeira.get('[role="img"]').attributes('aria-label')).toBe(
      'Outro canal'
    );
    expect(primeira.text()).toContain('Conversa sem texto');
    expect(primeira.text()).toContain('Adiada');
  });

  it('card sem valor e em estado que a tela não conhece: sem valor, com rótulo neutro', async () => {
    const w = await abrirPessoa();
    const card = w.get(marca('card'));
    expect(card.text()).toContain('Plano mensal');
    expect(card.text()).toContain('Outra situação');
    expect(card.text()).not.toContain('R$');
    expect(card.text()).not.toContain('estado_novo');
  });
});

describe('ficha da pessoa: erros do servidor', () => {
  it('404 diz que não achou e oferece voltar para a lista', async () => {
    RelacionamentosAPI.pessoa.mockRejectedValue(erroHttp(404));
    const w = await abrirPessoa();
    expect(w.get(marca('vazio')).text()).toContain('Não achei esta pessoa.');
    expect(w.find(marca('ficha-pessoa')).exists()).toBe(false);
    await w.get(`${marca('vazio')} button`).trigger('click');
    expect(contexto.empurrar).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'relationships_home' })
    );
  });

  it.each([401, 403])(
    '%i diz que a pessoa não tem acesso, sem "tentar de novo"',
    async status => {
      RelacionamentosAPI.pessoa.mockRejectedValue(erroHttp(status));
      const w = await abrirPessoa();
      expect(w.get(marca('sem-acesso')).text()).toContain(
        'Você não tem acesso a esta ficha.'
      );
      expect(w.find(marca('erro')).exists()).toBe(false);
      expect(w.find(marca('ficha-pessoa')).exists()).toBe(false);
    }
  );

  it('500 mostra o erro, e "Tentar de novo" pede outra vez', async () => {
    RelacionamentosAPI.pessoa.mockRejectedValueOnce(erroHttp(500));
    const w = await abrirPessoa();
    expect(w.get(marca('erro')).text()).toContain(
      'Não consegui abrir esta ficha.'
    );
    await w.get(`${marca('erro')} button`).trigger('click');
    await flushPromises();
    expect(RelacionamentosAPI.pessoa).toHaveBeenCalledTimes(2);
    expect(w.get('h1').text()).toBe('Ana Albuquerino');
  });

  it('quem não pode ver os cards fica sem a parte de cards, e o resto abre', async () => {
    RelacionamentosAPI.cardsDaPessoa.mockRejectedValue(erroHttp(401));
    const w = await abrirPessoa();
    expect(w.get('h1').text()).toBe('Ana Albuquerino');
    expect(w.find(marca('cards')).exists()).toBe(false);
    expect(w.find(marca('conversas')).exists()).toBe(true);
    expect(w.find(marca('erro')).exists()).toBe(false);
  });

  it('500 nos cards mostra o erro só ali, e "Tentar de novo" relê só os cards', async () => {
    RelacionamentosAPI.cardsDaPessoa.mockRejectedValueOnce(erroHttp(500));
    const w = await abrirPessoa();
    const falha = w.get(`${marca('cards')} ${marca('falha-da-parte')}`);
    expect(falha.text()).toContain('Não consegui mostrar esta parte.');
    expect(w.find(marca('card')).exists()).toBe(false);
    await falha.get('button').trigger('click');
    await flushPromises();
    expect(w.get(marca('card')).text()).toContain('Plano mensal');
    expect(RelacionamentosAPI.cardsDaPessoa).toHaveBeenCalledTimes(2);
    expect(RelacionamentosAPI.pessoa).toHaveBeenCalledTimes(1);
  });
});

describe('ficha da pessoa: para onde os botões levam', () => {
  it('Conversar abre a conversa mais recente da pessoa', async () => {
    const w = await abrirPessoa();
    await w.get(marca('conversar')).trigger('click');
    expect(contexto.empurrar).toHaveBeenCalledWith({
      name: 'inbox_conversation',
      params: { conversation_id: 55 },
      query: undefined,
    });
    expect(useAlert).not.toHaveBeenCalled();
  });

  // #3071 — "Conversar" aparece sempre: com quem nunca conversou abre a "Nova
  // conversa" já com a pessoa.
  it('com quem nunca conversou, Conversar abre a Nova conversa já com a pessoa', async () => {
    RelacionamentosAPI.conversasDaPessoa.mockResolvedValue({ data: [] });
    conversaNova.abrir.mockResolvedValue(true);
    const w = await abrirPessoa();
    await w.get(marca('conversar')).trigger('click');
    await flushPromises();
    expect(conversaNova.abrir).toHaveBeenCalledWith(7);
    expect(contexto.empurrar).not.toHaveBeenCalled();
    expect(useAlert).not.toHaveBeenCalled();
  });

  it('se a Nova conversa não abre (quem só lê conversas), a tela diz por quê', async () => {
    RelacionamentosAPI.conversasDaPessoa.mockResolvedValue({ data: [] });
    conversaNova.abrir.mockResolvedValue(false);
    const w = await abrirPessoa();
    await w.get(marca('conversar')).trigger('click');
    await flushPromises();
    expect(useAlert).toHaveBeenCalledWith(
      'Vocês ainda não conversaram por aqui. O telefone está na ficha.'
    );
  });

  // A leitura das conversas falhou: o clique lê de novo antes de abrir.
  const AVISO_DE_FALHA = `${marca('conversas')} ${marca('falha-da-parte')}`;

  it('se as conversas não vieram, Conversar lê de novo e abre a mais recente', async () => {
    RelacionamentosAPI.conversasDaPessoa.mockRejectedValueOnce(erroHttp(500));
    const w = await abrirPessoa();
    expect(w.find(AVISO_DE_FALHA).exists()).toBe(true);
    await w.get(marca('conversar')).trigger('click');
    await flushPromises();
    expect(RelacionamentosAPI.conversasDaPessoa).toHaveBeenCalledTimes(2);
    expect(contexto.empurrar).toHaveBeenCalledWith({
      name: 'inbox_conversation',
      params: { conversation_id: 55 },
      query: undefined,
    });
    expect(useAlert).not.toHaveBeenCalled();
  });

  it('se as conversas continuam sem vir, Conversar não abre nada e diz que não conseguiu ver', async () => {
    RelacionamentosAPI.conversasDaPessoa.mockRejectedValue(erroHttp(500));
    const w = await abrirPessoa();
    await w.get(marca('conversar')).trigger('click');
    await flushPromises();
    expect(contexto.empurrar).not.toHaveBeenCalled();
    expect(conversaNova.abrir).not.toHaveBeenCalled();
    expect(useAlert).toHaveBeenCalledWith(
      'Não consegui ver as conversas dessa pessoa agora. Tente de novo.'
    );
    expect(w.find(marca('conversar')).exists()).toBe(true);
  });

  it('quem não pode ver as conversas fica sem a parte, e Conversar continua', async () => {
    RelacionamentosAPI.conversasDaPessoa.mockRejectedValue(erroHttp(401));
    const w = await abrirPessoa();
    expect(w.find(marca('conversas')).exists()).toBe(false);
    expect(w.find(marca('conversar')).exists()).toBe(true);
  });

  it('Abrir no CRM leva ao card', async () => {
    const w = await abrirPessoa();
    await w.get(marca('card')).trigger('click');
    await w.get(`${marca('gaveta-card')} [data-foco]`).trigger('click');
    expect(contexto.empurrar).toHaveBeenCalledWith({
      name: 'crm_kanban_index',
      params: undefined,
      query: { card_id: '3' },
    });
  });

  it('Novo card leva ao CRM já com a pessoa', async () => {
    const w = await abrirPessoa();
    await w.get(marca('novo-card')).trigger('click');
    expect(contexto.empurrar).toHaveBeenCalledWith({
      name: 'crm_kanban_index',
      params: undefined,
      query: { new_contact_id: '7' },
    });
  });

  it('quem não pode criar card não vê Novo card', async () => {
    pode.criarCards = false;
    const w = await abrirPessoa();
    expect(w.find(marca('novo-card')).exists()).toBe(false);
  });
});

describe('ficha da pessoa: escritas', () => {
  it('Marcar como cliente escreve, relê a pessoa e o selo aparece', async () => {
    ContactAPI.markCustomer.mockResolvedValue({ data: {} });
    const w = await abrirPessoa();
    RelacionamentosAPI.pessoa.mockResolvedValue({
      data: { ...ANA, contact_type: 'customer', customer_since: AGORA },
    });
    await w.get(marca('marcar-cliente')).trigger('click');
    await flushPromises();
    expect(ContactAPI.markCustomer).toHaveBeenCalledWith(7);
    expect(w.find('[data-selo="cliente"]').exists()).toBe(true);
    expect(useAlert).toHaveBeenCalledWith(
      'Pronto. Ana Albuquerino agora é cliente.'
    );
  });

  const CLIENTE = { ...ANA, contact_type: 'customer', customer_since: AGORA };
  const escolherNoMais = async (w, texto) => {
    await w.get(marca('mais-acoes')).trigger('click');
    await w
      .findAll('.n-dropdown-item button')
      .find(item => item.text().includes(texto))
      .trigger('click');
    await flushPromises();
  };

  it('"Não é mais cliente", no ⋯, escreve na hora, relê a pessoa e o selo some', async () => {
    RelacionamentosAPI.pessoa.mockResolvedValue({ data: CLIENTE });
    ContactAPI.removeCustomer.mockResolvedValue({ data: {} });
    const w = await abrirPessoa();
    expect(w.find('[data-selo="cliente"]').exists()).toBe(true);
    RelacionamentosAPI.pessoa.mockResolvedValue({ data: ANA });
    await escolherNoMais(w, 'Não é mais cliente');
    expect(ContactAPI.removeCustomer).toHaveBeenCalledWith(7);
    expect(w.find('[data-selo="cliente"]').exists()).toBe(false);
    expect(w.find(marca('marcar-cliente')).exists()).toBe(true);
    expect(useAlert).toHaveBeenCalledWith(
      'Ana Albuquerino não é mais cliente.'
    );
  });

  it('se o servidor recusa o "Não é mais cliente", o selo fica e a tela avisa', async () => {
    RelacionamentosAPI.pessoa.mockResolvedValue({ data: CLIENTE });
    ContactAPI.removeCustomer.mockRejectedValue(erroHttp(500));
    const w = await abrirPessoa();
    await escolherNoMais(w, 'Não é mais cliente');
    expect(w.find('[data-selo="cliente"]').exists()).toBe(true);
    expect(useAlert).toHaveBeenCalledWith('Não consegui mudar. Tente de novo.');
  });

  it('quem não é cliente não tem "Não é mais cliente" no "⋯"', async () => {
    const w = await abrirPessoa();
    await w.get(marca('mais-acoes')).trigger('click');
    expect(w.text()).toContain('Alterar informações');
    expect(w.text()).not.toContain('Não é mais cliente');
  });

  it('de quem é cliente, o "⋯" guarda "Alterar informações" e "Não é mais cliente", sem botão solto', async () => {
    RelacionamentosAPI.pessoa.mockResolvedValue({ data: CLIENTE });
    const w = await abrirPessoa();
    expect(w.find(marca('alterar-informacoes')).exists()).toBe(false);
    await w.get(marca('mais-acoes')).trigger('click');
    const itens = w.findAll('.n-dropdown-item button');
    expect(itens[0].text()).toContain('Alterar informações');
    expect(itens[1].text()).toContain('Não é mais cliente');
  });

  it('Salvar nota escreve e a nota entra no topo', async () => {
    ContactNotesAPI.create.mockResolvedValue({
      data: {
        id: 31,
        content: 'Mandar a proposta amanhã.',
        user: { id: 4, name: 'Tiago Zanquetta' },
        created_at: AGORA,
      },
    });
    const w = await abrirPessoa();
    await w.get(marca('nota-caixa')).setValue('Mandar a proposta amanhã.');
    await w.get(`${marca('notas')} form`).trigger('submit');
    await flushPromises();
    expect(ContactNotesAPI.create).toHaveBeenCalledWith(
      7,
      'Mandar a proposta amanhã.'
    );
    const primeira = w.findAll(marca('nota'))[0];
    expect(primeira.text()).toContain('Mandar a proposta amanhã.');
    expect(primeira.text()).toContain('Tiago Zanquetta');
    expect(w.get(marca('nota-caixa')).element.value).toBe('');
  });

  it('Liberar, depois de confirmar, desfaz a recusa e a faixa some', async () => {
    RelacionamentosAPI.pessoa.mockResolvedValue({
      data: { ...ANA, opted_out_at: AGORA - DIA, opt_out_source: 'manual' },
    });
    ContactAPI.removeOptOut.mockResolvedValue({ data: {} });
    const w = await abrirPessoa();
    RelacionamentosAPI.pessoa.mockResolvedValue({ data: ANA });
    await w.get(marca('liberar')).trigger('click');
    await w.get(marca('liberar-confirmar')).trigger('click');
    await flushPromises();
    expect(ContactAPI.removeOptOut).toHaveBeenCalledWith(7);
    expect(w.find(marca('faixa-nao-quer')).exists()).toBe(false);
  });

  it('Alterar salva pelo contato e a ficha mostra o que o servidor releu', async () => {
    ContactAPI.update.mockResolvedValue({ data: { payload: {} } });
    const w = await abrirPessoa();
    await w.get(marca('alterar')).trigger('click');
    await w
      .get(`${marca('gaveta-informacoes')} [data-foco]`)
      .setValue('Ana Maria Albuquerino');
    RelacionamentosAPI.pessoa.mockResolvedValue({
      data: { ...ANA, name: 'Ana Maria Albuquerino' },
    });
    await w.get(marca('salvar-informacoes')).trigger('click');
    await flushPromises();
    expect(ContactAPI.update).toHaveBeenCalledWith(
      7,
      expect.objectContaining({
        name: 'Ana Maria Albuquerino',
        phone_number: '+5511910310001',
        additional_attributes: expect.objectContaining({ city: 'Campinas' }),
      })
    );
    expect(w.get('h1').text()).toBe('Ana Maria Albuquerino');
    expect(useAlert).toHaveBeenCalledWith('Informações salvas.');
  });

  it('se o servidor recusa, a gaveta fica aberta e a tela diz que não salvou', async () => {
    ContactAPI.update.mockRejectedValue(erroHttp(422));
    const w = await abrirPessoa();
    await w.get(marca('alterar')).trigger('click');
    await w.get(marca('salvar-informacoes')).trigger('click');
    await flushPromises();
    expect(w.find(marca('gaveta-informacoes')).exists()).toBe(true);
    expect(useAlert).toHaveBeenCalledWith(
      'Não consegui salvar. Tente de novo.'
    );
  });
});

describe('ficha da pessoa: quem só pode ver', () => {
  it('não tem Alterar, Marcar como cliente, Liberar nem a caixa de nota', async () => {
    pode.editar = false;
    RelacionamentosAPI.pessoa.mockResolvedValue({
      data: { ...ANA, opted_out_at: AGORA - DIA, opt_out_source: 'manual' },
    });
    const w = await abrirPessoa();
    expect(w.find(marca('alterar')).exists()).toBe(false);
    expect(w.find(marca('marcar-cliente')).exists()).toBe(false);
    expect(w.find(marca('liberar')).exists()).toBe(false);
    expect(w.find(marca('nota-caixa')).exists()).toBe(false);
    expect(w.find(marca('guardar-nota')).exists()).toBe(false);
    expect(w.find(marca('faixa-nao-quer')).exists()).toBe(true);
    expect(w.get(marca('notas')).text()).toContain('Ligar.');
    // Sem nada que quem só pode ver possa fazer, o "⋯" não aparece.
    expect(w.find(marca('mais-acoes')).exists()).toBe(false);
    expect(w.find(marca('mudar-etiquetas')).exists()).toBe(false);
    expect(w.find(marca('apagar-nota')).exists()).toBe(false);
    expect(w.text()).not.toContain('Alterar informações');
  });

  it('de cliente, vê o selo mas não tem "Não é mais cliente"', async () => {
    pode.editar = false;
    RelacionamentosAPI.pessoa.mockResolvedValue({
      data: { ...ANA, contact_type: 'customer', customer_since: AGORA },
    });
    const w = await abrirPessoa();
    expect(w.find('[data-selo="cliente"]').exists()).toBe(true);
    expect(w.find(marca('mais-acoes')).exists()).toBe(false);
    expect(w.text()).not.toContain('Não é mais cliente');
  });

  // #3071 — sem poder criar card, sobra só Conversar, que aparece sempre.
  it('sem poder criar card, o cabeçalho fica só com Conversar, com ou sem conversa', async () => {
    pode.editar = false;
    pode.criarCards = false;
    RelacionamentosAPI.conversasDaPessoa.mockResolvedValueOnce({ data: [] });
    const semConversa = await abrirPessoa();
    const grupo = semConversa.get(`${marca('cabecalho')} [role="group"]`);
    // O Ligar é do VoiceCallButton, que se esconde sem caixa de voz.
    expect(grupo.findAll('button:not([data-ligar])')).toHaveLength(1);
    expect(grupo.find(marca('conversar')).exists()).toBe(true);
  });
});

describe('ficha da empresa com os dados do servidor', () => {
  it('pede tudo pelo id e mostra a empresa, as pessoas, as conversas e os cards', async () => {
    const w = await abrirEmpresa();
    Object.keys(DA_EMPRESA).forEach(metodo =>
      expect(RelacionamentosAPI[metodo]).toHaveBeenCalledWith(9)
    );
    expect(w.get('h1').text()).toBe('Padaria Bom Dia');
    expect(w.get(marca('pessoa-da-empresa')).text()).toContain(
      'Ana Albuquerino'
    );
    expect(w.get(marca('conversas')).text()).toContain('Ana Albuquerino');
    expect(w.get(marca('card')).text()).toContain('Plano mensal');
  });

  it('404 diz que não achou; 403 (sem a chave de empresas), que não tem acesso', async () => {
    RelacionamentosAPI.empresa.mockRejectedValue(erroHttp(404));
    const naoAchei = await abrirEmpresa();
    expect(naoAchei.get(marca('vazio')).text()).toContain(
      'Não achei esta empresa.'
    );
    naoAchei.unmount();
    RelacionamentosAPI.empresa.mockRejectedValue(erroHttp(403));
    const semAcesso = await abrirEmpresa();
    expect(semAcesso.get(marca('sem-acesso')).text()).toContain(
      'Você não tem acesso a esta ficha.'
    );
  });

  it('500 nas pessoas mostra o erro só ali; quem não vê cards fica sem a parte', async () => {
    RelacionamentosAPI.pessoasDaEmpresa.mockRejectedValueOnce(erroHttp(500));
    RelacionamentosAPI.cardsDaEmpresa.mockRejectedValue(erroHttp(401));
    const w = await abrirEmpresa();
    expect(w.find(marca('cards')).exists()).toBe(false);
    await w
      .get(`${marca('pessoas-da-empresa')} ${marca('falha-da-parte')} button`)
      .trigger('click');
    await flushPromises();
    expect(w.get(marca('pessoa-da-empresa')).text()).toContain(
      'Ana Albuquerino'
    );
  });

  it('Abrir no CRM leva ao card', async () => {
    const w = await abrirEmpresa();
    await w.get(marca('card')).trigger('click');
    await w.get(`${marca('gaveta-card')} [data-foco]`).trigger('click');
    expect(contexto.empurrar).toHaveBeenCalledWith({
      name: 'crm_kanban_index',
      params: undefined,
      query: { card_id: '3' },
    });
  });

  it('Alterar salva pela empresa (CNPJ em additional_attributes) e mostra o que o servidor releu', async () => {
    CompanyAPI.update.mockResolvedValue({ data: { payload: {} } });
    const w = await abrirEmpresa();
    await w.get(marca('alterar-empresa')).trigger('click');
    await w
      .get(`${marca('gaveta-empresa')} [data-foco]`)
      .setValue('Padaria Nova');
    RelacionamentosAPI.empresa.mockResolvedValue({
      data: { ...PADARIA, name: 'Padaria Nova' },
    });
    await w.get(marca('salvar-empresa')).trigger('click');
    await flushPromises();
    expect(CompanyAPI.update).toHaveBeenCalledWith(9, {
      company: {
        name: 'Padaria Nova',
        domain: 'padaria-bom-dia.exemplo.com.br',
        description: null,
        additional_attributes: { cnpj: '11222333000181', city: null },
        custom_attributes: {},
      },
    });
    expect(w.get('h1').text()).toBe('Padaria Nova');
  });

  // #2970 — "Mandar mensagem" e o ícone de conversar de cada pessoa ainda só
  // avisam: fora da demonstração não aparecem.
  it('não tem Mandar mensagem, o ícone de conversar de cada pessoa nem Ver todas; Alterar continua', async () => {
    const w = await abrirEmpresa();
    expect(w.find(marca('mandar-mensagem')).exists()).toBe(false);
    expect(w.get(marca('cabecalho')).text()).not.toContain('Mandar mensagem');
    expect(w.find(marca('conversar-com-pessoa')).exists()).toBe(false);
    expect(w.findAll(`${marca('conversas')} li`)).toHaveLength(1);
    expect(w.get(marca('conversas')).text()).not.toContain('Ver todas');
    // #3078 — o histórico é de verdade: cada conversa abre.
    await w.get(`${marca('conversas')} li button`).trigger('click');
    expect(contexto.empurrar).toHaveBeenCalledWith({
      name: 'inbox_conversation',
      params: { conversation_id: CONVERSAS[1].id },
      query: undefined,
    });
    contexto.empurrar.mockClear();
    expect(w.find(marca('alterar-empresa')).exists()).toBe(true);
    await w.get(marca('pessoa-da-empresa')).trigger('click');
    expect(contexto.empurrar).toHaveBeenCalledWith({
      name: 'relacionamentos_pessoa',
      params: { contactId: 7 },
      query: undefined,
    });
    expect(useAlert).not.toHaveBeenCalled();
  });

  it('quem só pode ver não tem Alterar: o cabeçalho fica sem botão de ação', async () => {
    pode.editar = false;
    const w = await abrirEmpresa();
    expect(w.find(marca('alterar-empresa')).exists()).toBe(false);
    expect(w.find(marca('mandar-mensagem')).exists()).toBe(false);
    expect(w.find(`${marca('cabecalho')} [role="group"]`).exists()).toBe(false);
  });
});
