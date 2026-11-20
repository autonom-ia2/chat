import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { useAlert } from 'dashboard/composables';
import CompanyAPI from 'dashboard/api/companies';
import RelacionamentosAPI from 'dashboard/api/relacionamentos';
import FichaDaEmpresaPage from '../../pages/FichaDaEmpresaPage.vue';

// #3078 — a ficha da empresa com tudo o que a ficha antiga de Empresas fazia,
// fora da demonstração: cada ação escreve pelo endpoint de empresas que a
// ficha antiga usava, pergunta antes quando apaga, diz o que aconteceu e,
// quando dá, oferece "Desfazer". Quem só pode ver lê tudo e não muda nada.
const contexto = vi.hoisted(() => ({ params: {}, empurrar: vi.fn() }));
const pode = vi.hoisted(() => ({
  apagar: true,
  lembrete: true,
  editar: true,
}));
const conta = vi.hoisted(() => ({ flags: [] }));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    currentAccount: { value: { carteira_seguros: false } },
    isCloudFeatureEnabled: flag => conta.flags.includes(flag),
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
const valor = vi.hoisted(() => chave => ({
  get value() {
    return pode[chave];
  },
}));
vi.mock('../../ficha/usePermissoesDaFicha', () => ({
  usePermissoesDaFicha: () => ({
    podeEditar: valor('editar'),
    podeCriarCards: { value: true },
    podeExportar: { value: false },
    podeApagar: valor('apagar'),
    podeCriarLembrete: valor('lembrete'),
  }),
}));
vi.mock(
  'dashboard/routes/dashboard/crm/components/lembrete/LembreteGaveta.vue',
  () => ({
    __esModule: true,
    default: {
      props: ['show', 'contato', 'empresa', 'titulo', 'dia'],
      template:
        '<div data-lembrete-gaveta :data-empresa="empresa.id">{{ empresa.name }} | {{ titulo }}</div>',
    },
  })
);
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({ value: [] }),
}));
vi.mock('dashboard/api/relacionamentos', () => ({
  default: {
    empresa: vi.fn(),
    pessoasDaEmpresa: vi.fn(),
    conversasDaEmpresa: vi.fn(),
    cardsDaEmpresa: vi.fn(),
  },
}));
vi.mock('dashboard/api/companies', () => ({
  default: {
    update: vi.fn(),
    delete: vi.fn(),
    listNotes: vi.fn(),
    listMedia: vi.fn(),
    searchContacts: vi.fn(),
    createContact: vi.fn(),
    removeContact: vi.fn(),
  },
}));

withFullI18n('pt_BR');
vi.setConfig({ testTimeout: 30000 });

const marca = nome => `[data-relacionamentos="${nome}"]`;
const AGORA = Math.floor(Date.now() / 1000);
const DIA = 86_400;
const MIDIAS = 'relationships_company_media';

const PADARIA = {
  id: 9,
  name: 'Padaria Bom Dia',
  cnpj: '11222333000181',
  domain: 'padaria.exemplo.com.br',
  city: 'Campinas',
  description: 'Pães e bolos.',
  thumbnail: '',
  contacts_count: 1,
  customers_count: 0,
  created_at: AGORA - 300 * DIA,
  last_activity_at: AGORA - DIA,
  custom_attributes: {},
};
const ANA = {
  id: 7,
  name: 'Ana Albuquerino',
  email: 'ana@exemplo.com.br',
  phone_number: '+5511910310001',
  thumbnail: '',
  contact_type: 'lead',
  opted_out_at: null,
};

const servidorResponde = () => {
  RelacionamentosAPI.empresa.mockResolvedValue({ data: PADARIA });
  RelacionamentosAPI.pessoasDaEmpresa.mockResolvedValue({ data: [ANA] });
  RelacionamentosAPI.conversasDaEmpresa.mockResolvedValue({ data: [] });
  RelacionamentosAPI.cardsDaEmpresa.mockResolvedValue({ data: [] });
  CompanyAPI.listNotes.mockResolvedValue({
    data: {
      payload: [
        {
          id: 1,
          content: 'Prefere de manhã.',
          created_at: AGORA - DIA,
          user: { name: 'Sônia' },
          contact: { id: 7, name: 'Ana Albuquerino' },
        },
      ],
    },
  });
  CompanyAPI.listMedia.mockResolvedValue({
    data: {
      payload: [
        {
          id: 3,
          filename: 'cardapio.pdf',
          file_type: 'file',
          created_at: new Date((AGORA - DIA) * 1000).toISOString(),
          contact: { id: 7, name: 'Ana Albuquerino' },
        },
      ],
      meta: { total: 8 },
    },
  });
};

let aberta;
const abrirEmpresa = async () => {
  contexto.params = { companyId: '9' };
  aberta = mount(FichaDaEmpresaPage, {
    attachTo: document.body,
    global: { stubs: { transition: true } },
  });
  await flushPromises();
  return aberta;
};
const escolherNoMais = async (w, evento) => {
  await w.get(marca('mais-acoes')).trigger('click');
  await w.get(`[data-mais="${evento}"]`).trigger('click');
  await flushPromises();
};
const confirmar = async (w, pergunta) => {
  await w
    .get(`[data-carteira="${pergunta}"]`)
    .element.closest('[data-dialogo-falso]')
    .querySelector('[data-carteira="dialogo-confirmar"]')
    .click();
  await flushPromises();
};

beforeEach(() => {
  Object.assign(pode, { apagar: true, lembrete: true, editar: true });
  conta.flags = ['companies', MIDIAS];
  servidorResponde();
});

afterEach(() => {
  aberta?.unmount();
  aberta = null;
  vi.resetAllMocks();
});

describe('cabeçalho e informações', () => {
  it('foto, cidade, o site que abre numa aba nova e as informações da ficha antiga', async () => {
    const w = await abrirEmpresa();
    const cabecalho = w.get(marca('cabecalho'));
    expect(cabecalho.get(marca('cidade-da-empresa')).text()).toBe('Campinas');
    const site = cabecalho.get(marca('site-da-empresa'));
    expect(site.attributes('href')).toBe('https://padaria.exemplo.com.br/');
    expect(site.attributes('target')).toBe('_blank');
    expect(site.attributes('aria-label')).toBe(
      'Abrir o site padaria.exemplo.com.br numa aba nova'
    );
    const informacoes = w.get(marca('informacoes'));
    expect(informacoes.get('[data-informacao="sobre"]').text()).toContain(
      'Pães e bolos.'
    );
    expect(informacoes.get('[data-informacao="cidade"]').text()).toContain(
      'Campinas'
    );
    expect(informacoes.find('[data-informacao="desde"]').exists()).toBe(true);
    expect(
      informacoes.get('[data-informacao="ultima_conversa"]').text()
    ).toContain('ontem');
  });

  it('quem só pode ver lê tudo, com o aviso, e não tem nenhuma ação de escrita', async () => {
    Object.assign(pode, { editar: false, apagar: false, lembrete: false });
    const w = await abrirEmpresa();
    expect(w.get(marca('so-leitura')).text()).toBe(
      'Você pode ver estas informações, mas não pode mudar.'
    );
    expect(w.find(marca('alterar')).exists()).toBe(false);
    expect(w.find(marca('por-pessoa')).exists()).toBe(false);
    expect(w.find(marca('tirar-pessoa')).exists()).toBe(false);
    expect(w.find(marca('acoes-da-empresa')).exists()).toBe(false);
    expect(w.findAll(marca('nota'))).toHaveLength(1);
  });
});

describe('apagar a empresa', () => {
  it('pergunta, diz o que acontece com as pessoas e volta para a aba Empresas', async () => {
    CompanyAPI.delete.mockResolvedValue({ status: 200 });
    const w = await abrirEmpresa();
    await escolherNoMais(w, 'apagar');
    const pergunta = w.get('[data-carteira="confirmar-apagar-empresa"]');
    expect(pergunta.text()).toContain('Apagar Padaria Bom Dia?');
    // A perda primeiro, em frases curtas; sem a frase óbvia de que sai da lista.
    expect(pergunta.text()).toContain(
      'Os lembretes e os arquivos desta empresa são apagados. 1 pessoa continua na sua lista, com as conversas, mas sem empresa. Isto não volta.'
    );
    expect(pergunta.text()).not.toContain('sai da sua lista');
    await confirmar(w, 'confirmar-apagar-empresa');
    expect(CompanyAPI.delete).toHaveBeenCalledWith(9);
    expect(useAlert).toHaveBeenCalledWith('Padaria Bom Dia foi apagada.');
    expect(contexto.empurrar).toHaveBeenCalledWith({
      name: 'relationships_home',
      params: undefined,
      query: { aba: 'empresas' },
    });
  });

  // #3079 — a empresa com muitas pessoas o servidor apaga em alguns minutos
  // (202): o aviso diz isso, sem fingir que ela já saiu.
  it('empresa que o servidor põe na fila: avisa que sai da lista em alguns minutos', async () => {
    CompanyAPI.delete.mockResolvedValue({ status: 202 });
    const w = await abrirEmpresa();
    await escolherNoMais(w, 'apagar');
    await confirmar(w, 'confirmar-apagar-empresa');
    expect(useAlert).toHaveBeenCalledWith(
      'Padaria Bom Dia tem muitas pessoas e sai da lista em alguns minutos.'
    );
    expect(contexto.empurrar).toHaveBeenCalledWith(
      expect.objectContaining({ query: { aba: 'empresas' } })
    );
  });

  it('sem poder apagar, o cabeçalho só tem "Alterar informações", como botão', async () => {
    Object.assign(pode, { apagar: false });
    const w = await abrirEmpresa();
    expect(w.find(marca('mais-acoes')).exists()).toBe(false);
    expect(w.get(marca('alterar-empresa')).text()).toBe('Alterar informações');
  });
});

describe('pôr e tirar pessoa', () => {
  it('tirar mostra o aviso com "Desfazer", que põe a pessoa de volta', async () => {
    CompanyAPI.removeContact.mockResolvedValue({});
    CompanyAPI.createContact.mockResolvedValue({});
    const w = await abrirEmpresa();
    await w.get(marca('tirar-pessoa')).trigger('click');
    await flushPromises();
    expect(CompanyAPI.removeContact).toHaveBeenCalledWith(9, 7);
    expect(w.get('[data-carteira="aviso-vivo"]').text()).toContain(
      'Ana Albuquerino saiu de Padaria Bom Dia. A pessoa continua na sua lista.'
    );
    // A ficha relê a empresa e as pessoas dela.
    expect(RelacionamentosAPI.pessoasDaEmpresa).toHaveBeenCalledTimes(2);
    await w.get('[data-carteira="desfazer"]').trigger('click');
    await flushPromises();
    expect(CompanyAPI.createContact).toHaveBeenCalledWith(9, {
      contact_id: 7,
    });
    expect(w.get('[data-carteira="aviso-vivo"]').text()).toContain(
      'Pronto. Ana Albuquerino voltou para Padaria Bom Dia.'
    );
  });

  it('pôr procura quem não está, avisa quem muda de empresa e põe', async () => {
    CompanyAPI.searchContacts.mockResolvedValue({
      data: {
        payload: [
          {
            id: 8,
            name: 'Bruno Dornelaz',
            phone_number: '+5511910310002',
            email: '',
            company: { id: 2, name: 'Farmácia Central' },
          },
        ],
      },
    });
    CompanyAPI.createContact.mockResolvedValue({});
    const w = await abrirEmpresa();
    await w.get(marca('por-pessoa')).trigger('click');
    const dialogo = () => w.get(marca('dialogo-por-pessoa'));
    // Sem escolha, confirmar diz o que falta.
    await w.get(marca('confirmar-por')).trigger('submit');
    expect(dialogo().get(marca('por-falta')).text()).toBe(
      'Toque numa pessoa da lista para escolher.'
    );
    const campo = dialogo().get(marca('busca'));
    await campo.setValue('Bruno');
    await campo.trigger('keydown', { key: 'Enter' });
    await flushPromises();
    expect(CompanyAPI.searchContacts).toHaveBeenCalledWith(9, 'Bruno');
    expect(dialogo().text()).toContain('Está em Farmácia Central');
    await w.get('[data-pessoa="8"]').setValue(true);
    expect(dialogo().get(marca('muda-de-empresa')).text()).toBe(
      'Bruno Dornelaz sai de Farmácia Central e entra em Padaria Bom Dia. Uma pessoa fica numa empresa só.'
    );
    await w.get(marca('confirmar-por')).trigger('submit');
    await flushPromises();
    expect(CompanyAPI.createContact).toHaveBeenCalledWith(9, {
      contact_id: 8,
    });
    expect(w.find(marca('dialogo-por-pessoa')).exists()).toBe(false);
    // "Desfazer" devolve quem veio de outra empresa para lá.
    expect(w.get('[data-carteira="aviso-vivo"]').text()).toContain(
      'Bruno Dornelaz saiu de Farmácia Central e entrou em Padaria Bom Dia.'
    );
    await w.get('[data-carteira="desfazer"]').trigger('click');
    await flushPromises();
    expect(CompanyAPI.createContact).toHaveBeenLastCalledWith(2, {
      contact_id: 8,
    });
    expect(w.get('[data-carteira="aviso-vivo"]').text()).toContain(
      'Pronto. Bruno Dornelaz voltou para Farmácia Central.'
    );
  });

  it('se o servidor recusa, o diálogo fica aberto e diz por quê', async () => {
    CompanyAPI.searchContacts.mockResolvedValue({
      data: { payload: [{ id: 8, name: 'Bruno', company: null }] },
    });
    CompanyAPI.createContact.mockRejectedValue(
      Object.assign(new Error('422'), {
        response: { status: 422, data: { message: 'Não pode.' } },
      })
    );
    const w = await abrirEmpresa();
    await w.get(marca('por-pessoa')).trigger('click');
    const campo = w.get(`${marca('dialogo-por-pessoa')} ${marca('busca')}`);
    await campo.setValue('Bruno');
    await campo.trigger('keydown', { key: 'Enter' });
    await flushPromises();
    await w.get('[data-pessoa="8"]').setValue(true);
    await w.get(marca('confirmar-por')).trigger('submit');
    await flushPromises();
    expect(w.get(marca('por-falta')).text()).toBe('Não pode.');
  });
});

describe('notas, histórico, mídias e lembrete', () => {
  it('as notas são das pessoas da empresa: só para ler, e cada uma abre a pessoa', async () => {
    const w = await abrirEmpresa();
    const notas = w.get(marca('notas'));
    expect(notas.find('textarea').exists()).toBe(false);
    expect(notas.get(marca('explicacao-das-notas')).text()).toContain(
      'abra a ficha da pessoa'
    );
    expect(notas.text()).toContain('Prefere de manhã.');
    await notas.get(marca('pessoa-da-nota')).trigger('click');
    expect(contexto.empurrar).toHaveBeenCalledWith({
      name: 'relacionamentos_pessoa',
      params: { contactId: 7 },
      query: undefined,
    });
  });

  it('as mídias mostram as mais novas e "Ver todas" abre a tela de mídias', async () => {
    const w = await abrirEmpresa();
    expect(CompanyAPI.listMedia).toHaveBeenCalledWith(9, {
      per_page: 5,
      page: 1,
    });
    const midias = w.get(marca('midias'));
    expect(midias.text()).toContain('cardapio.pdf');
    expect(midias.text()).toContain('Ana Albuquerino');
    await midias.get(marca('ver-todas-as-midias')).trigger('click');
    expect(contexto.empurrar).toHaveBeenCalledWith({
      name: MIDIAS,
      params: { companyId: 9 },
      query: undefined,
    });
  });

  it('sem a chave das mídias, o bloco nem pede nada', async () => {
    conta.flags = ['companies'];
    const w = await abrirEmpresa();
    expect(w.find(marca('midias')).exists()).toBe(false);
    expect(CompanyAPI.listMedia).not.toHaveBeenCalled();
  });

  // #3078 (revisão) — quem lê a ficha lê a empresa no servidor, e a tela de
  // mídias pede o mesmo: quem só pode ver também tem "Ver todas".
  it('quem só pode ver também tem "Ver todas"', async () => {
    Object.assign(pode, { editar: false, apagar: false, lembrete: false });
    const w = await abrirEmpresa();
    expect(w.find(marca('ver-todas-as-midias')).exists()).toBe(true);
  });

  it('"Lembrete" abre a gaveta do calendário já com a empresa', async () => {
    const w = await abrirEmpresa();
    await w.get(marca('lembrete')).trigger('click');
    await flushPromises();
    const gaveta = w.get('[data-lembrete-gaveta]');
    expect(gaveta.attributes('data-empresa')).toBe('9');
    expect(gaveta.text()).toBe('Padaria Bom Dia | Falar com Padaria Bom Dia');
  });
});

describe('alterar informações', () => {
  it('a gaveta tem a foto, a cidade e "O que a empresa faz", e salva tudo no pedido', async () => {
    CompanyAPI.update.mockResolvedValue({ data: { payload: { id: 9 } } });
    const w = await abrirEmpresa();
    await w.get(`${marca('informacoes')} ${marca('alterar')}`).trigger('click');
    const gaveta = w.get(marca('gaveta-empresa'));
    expect(gaveta.find(marca('foto-da-empresa')).exists()).toBe(true);
    // Os atributos vão direto para o campo (CampoDeTexto).
    await gaveta.get('input[data-campo="cidade"]').setValue('Santos');
    await gaveta
      .get(`textarea${marca('sobre-a-empresa')}`)
      .setValue('Pães, bolos e café.');
    await w.get(marca('salvar-empresa')).trigger('click');
    await flushPromises();
    expect(CompanyAPI.update).toHaveBeenCalledWith(9, {
      company: {
        name: 'Padaria Bom Dia',
        domain: 'padaria.exemplo.com.br',
        description: 'Pães, bolos e café.',
        additional_attributes: { cnpj: '11222333000181', city: 'Santos' },
        custom_attributes: {},
      },
    });
    expect(useAlert).toHaveBeenCalledWith('Informações salvas.');
  });
});
