import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { useAlert } from 'dashboard/composables';
import AccountActionsAPI from 'dashboard/api/accountActions';
import ContactNotesAPI from 'dashboard/api/contactNotes';
import ContactAPI from 'dashboard/api/contacts';
import EtiquetasDoContatoAPI from 'dashboard/api/etiquetasDoContato';
import LabelsAPI from 'dashboard/api/labels';
import RelacionamentosAPI from 'dashboard/api/relacionamentos';
import FichaDaPessoaPage from '../../pages/FichaDaPessoaPage.vue';

// #3071 — as ações que vieram da ficha antiga, fora da demonstração: cada uma
// escreve pelo endpoint que a ficha antiga usava, pergunta antes quando apaga
// ou restringe, diz o que aconteceu e, quando dá, oferece "Desfazer".
const contexto = vi.hoisted(() => ({ params: {}, empurrar: vi.fn() }));
const pode = vi.hoisted(() => ({
  apagar: false,
  lembrete: false,
  editar: true,
}));
const daConta = vi.hoisted(() => ({ definicoes: [] }));
const conta = vi.hoisted(() => ({ carteira: false, flags: [] }));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
// O bloco Seguros conta 2 seguros da pessoa (o "Apagar" diz quantos saem).
vi.mock('../../components/carteira/SegurosDaFicha.vue', () => ({
  __esModule: true,
  default: {
    emits: ['quantos'],
    mounted() {
      this.$emit('quantos', 2);
    },
    render: () => null,
  },
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    currentAccount: {
      get value() {
        return { carteira_seguros: conta.carteira };
      },
    },
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
vi.mock('../../ficha/usePermissoesDaFicha', () => ({
  usePermissoesDaFicha: () => ({
    podeEditar: {
      get value() {
        return pode.editar;
      },
    },
    podeCriarCards: { value: true },
    podeExportar: { value: false },
    podeApagar: {
      get value() {
        return pode.apagar;
      },
    },
    podeCriarLembrete: {
      get value() {
        return pode.lembrete;
      },
    },
  }),
}));
vi.mock('dashboard/components-next/Contacts/VoiceCallButton.vue', () => ({
  default: {
    props: ['phone', 'contactId', 'label'],
    template: '<button data-ligar :data-fone="phone">{{ label }}</button>',
  },
}));
vi.mock(
  'dashboard/routes/dashboard/crm/components/lembrete/LembreteGaveta.vue',
  () => ({
    __esModule: true,
    default: {
      props: ['show', 'contato', 'titulo', 'dia'],
      template:
        '<div data-lembrete-gaveta :data-dia="dia.toDateString()">{{ contato.name }} | {{ titulo }}</div>',
    },
  })
);
vi.mock('../../components/carteira/ConversaNova.vue', () => ({
  default: { render: () => null, methods: { abrir: async () => false } },
}));
// #3075 — os campos personalizados da conta vêm do store.
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({
    get value() {
      return daConta.definicoes;
    },
  }),
}));
// #3075 — "Este contato é" é a escolha da ficha antiga; aqui só se vê se veio.
vi.mock(
  'dashboard/components-next/contato-relacao/EscolhaDaRelacao.vue',
  () => ({
    default: {
      props: ['contactId', 'podeEditar'],
      template:
        '<p data-escolha-da-relacao :data-pessoa="contactId" :data-pode-editar="String(podeEditar)" />',
    },
  })
);
vi.mock('dashboard/api/relacionamentos', () => ({
  default: {
    pessoa: vi.fn(),
    conversasDaPessoa: vi.fn(),
    cardsDaPessoa: vi.fn(),
    notasDaPessoa: vi.fn(),
    arquivosDaPessoa: vi.fn(),
    origemDaPessoa: vi.fn(),
    pessoas: vi.fn(),
  },
}));
vi.mock('dashboard/api/contacts', () => ({
  default: {
    update: vi.fn(),
    delete: vi.fn(),
    markOptOut: vi.fn(),
    removeOptOut: vi.fn(),
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

withFullI18n('pt_BR');
vi.setConfig({ testTimeout: 30000 });

const marca = nome => `[data-relacionamentos="${nome}"]`;
const AGORA = Math.floor(Date.now() / 1000);
const DIA = 86_400;

const ANA = {
  id: 7,
  name: 'Ana Albuquerino',
  email: 'ana@exemplo.com.br',
  phone_number: '+5511910310001',
  thumbnail: '',
  blocked: false,
  contact_type: 'lead',
  customer_since: null,
  last_activity_at: AGORA - DIA,
  created_at: AGORA - 90 * DIA,
  additional_attributes: {},
  custom_attributes: {},
  labels: ['feira'],
  opted_out_at: null,
  opt_out_source: null,
};
const BRUNO = {
  ...ANA,
  id: 8,
  name: 'Bruno Dornelaz',
  email: 'bruno@exemplo.com.br',
  phone_number: '+5511910310002',
};
const conversa = id => ({
  id,
  canal: 'whatsapp',
  trecho: `Trecho ${id}`,
  quando: AGORA - id * DIA,
  situacao: 'resolvida',
});
const NOTA = { id: 1, autor: 'Sônia', quando: AGORA - DIA, texto: 'Ligar.' };

const servidorResponde = (pessoa = ANA) => {
  RelacionamentosAPI.pessoa.mockResolvedValue({ data: pessoa });
  RelacionamentosAPI.conversasDaPessoa.mockResolvedValue({
    data: [1, 2, 3, 4, 5].map(conversa),
  });
  RelacionamentosAPI.cardsDaPessoa.mockResolvedValue({ data: [] });
  RelacionamentosAPI.notasDaPessoa.mockResolvedValue({ data: [NOTA] });
  RelacionamentosAPI.arquivosDaPessoa.mockResolvedValue({ data: [] });
  RelacionamentosAPI.origemDaPessoa.mockResolvedValue({ data: null });
};
const erroHttp = (status, data = {}) =>
  Object.assign(new Error(`Request failed with status code ${status}`), {
    response: { status, data },
  });

let aberta;
const abrirPessoa = async () => {
  contexto.params = { contactId: '7' };
  aberta = mount(FichaDaPessoaPage, {
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
const desfazer = async w => {
  await w.get('[data-carteira="desfazer"]').trigger('click');
  await flushPromises();
};

beforeEach(() => {
  pode.apagar = false;
  pode.lembrete = false;
  pode.editar = true;
  daConta.definicoes = [];
  conta.carteira = false;
  conta.flags = [];
  servidorResponde();
});

afterEach(() => {
  aberta?.unmount();
  aberta = null;
  vi.resetAllMocks();
});

describe('juntar com outra pessoa', () => {
  const buscar = async (w, termo) => {
    const campo = w.get(`${marca('dialogo-juntar')} ${marca('busca')}`);
    await campo.setValue(termo);
    await campo.trigger('keydown', { key: 'Enter' });
    await flushPromises();
  };

  it('busca a outra ficha, confirma o que acontece e junta: a pessoa da ficha fica', async () => {
    RelacionamentosAPI.pessoas.mockResolvedValue({
      data: { itens: [ANA, BRUNO], total: 2, tem_mais: false },
    });
    AccountActionsAPI.merge.mockResolvedValue({ data: {} });
    const w = await abrirPessoa();
    await escolherNoMais(w, 'juntar');
    // Abre já procurando pelo nome da pessoa, e diz qual ficha fica.
    expect(RelacionamentosAPI.pessoas).toHaveBeenCalledWith({
      busca: 'Ana Albuquerino',
    });
    expect(w.get(marca('dialogo-juntar')).text()).toContain(
      'A ficha de Ana Albuquerino fica; a que você escolher deixa de existir.'
    );
    await buscar(w, 'Dornelaz');
    expect(RelacionamentosAPI.pessoas).toHaveBeenCalledWith({
      busca: 'Dornelaz',
    });
    // A própria pessoa não aparece na lista.
    expect(
      w.findAll('[data-pessoa]').map(r => r.attributes('data-pessoa'))
    ).toEqual(['8']);
    await w.get('[data-pessoa="8"]').setValue(true);
    await w.get(marca('juntar-confirmar')).trigger('submit');
    const dialogo = w.get(marca('dialogo-juntar'));
    expect(dialogo.get(marca('juntar-fica')).text()).toContain(
      'Ana Albuquerino'
    );
    expect(dialogo.get(marca('juntar-sai')).text()).toContain('Bruno Dornelaz');
    expect(dialogo.get(marca('juntar-sai')).text()).toContain(
      'bruno@exemplo.com.br'
    );
    expect(dialogo.get('[data-juntar-telefone="fica"]').text()).toBe(
      '+55 11 91031-0001'
    );
    expect(dialogo.text()).toContain(
      'Tudo o que é de Bruno Dornelaz passa para Ana Albuquerino: conversas, notas, etiquetas e cards.'
    );
    // O telefone e o e-mail de quem sai são outros: somem, e a tela avisa.
    expect(dialogo.get('[data-juntar-perde="telefone"]').text()).toBe(
      'O telefone +55 11 91031-0002 de Bruno Dornelaz não fica na ficha. Anote antes, se precisar.'
    );
    expect(dialogo.get('[data-juntar-perde="email"]').text()).toBe(
      'O e-mail bruno@exemplo.com.br de Bruno Dornelaz não fica na ficha. Anote antes, se precisar.'
    );
    expect(dialogo.text()).toContain(
      'A ficha de Bruno Dornelaz deixa de existir. Não dá para desfazer.'
    );
    await w.get(marca('juntar-confirmar')).trigger('submit');
    await flushPromises();
    expect(AccountActionsAPI.merge).toHaveBeenCalledWith(7, 8);
    // O mesmo aviso das outras ações (com o × para fechar), sem "Desfazer".
    expect(w.get('[data-carteira="aviso-vivo"]').text()).toContain(
      'Pronto. Tudo de Bruno Dornelaz agora está na ficha de Ana Albuquerino.'
    );
    expect(w.find('[data-carteira="desfazer"]').exists()).toBe(false);
    expect(w.find(marca('dialogo-juntar')).exists()).toBe(false);
    // A ficha relê tudo: as conversas da outra pessoa entram.
    expect(RelacionamentosAPI.conversasDaPessoa).toHaveBeenCalledTimes(2);
  });

  it('na conta com a carteira, a confirmação diz que os seguros também passam', async () => {
    conta.carteira = true;
    RelacionamentosAPI.pessoas.mockResolvedValue({
      data: { itens: [BRUNO], total: 1, tem_mais: false },
    });
    const w = await abrirPessoa();
    await escolherNoMais(w, 'juntar');
    await w.get('[data-pessoa="8"]').setValue(true);
    await w.get(marca('juntar-confirmar')).trigger('submit');
    expect(w.get(marca('dialogo-juntar')).text()).toContain(
      'passa para Ana Albuquerino: conversas, notas, etiquetas, cards e seguros.'
    );
  });

  it('com o mesmo telefone e o mesmo e-mail, não avisa que algo se perde', async () => {
    RelacionamentosAPI.pessoas.mockResolvedValue({
      data: {
        itens: [
          {
            ...BRUNO,
            phone_number: ANA.phone_number,
            email: 'ANA@exemplo.com.br',
          },
        ],
        total: 1,
        tem_mais: false,
      },
    });
    const w = await abrirPessoa();
    await escolherNoMais(w, 'juntar');
    await w.get('[data-pessoa="8"]').setValue(true);
    await w.get(marca('juntar-confirmar')).trigger('submit');
    expect(w.find('[data-juntar-perde]').exists()).toBe(false);
  });

  it('uma busca nova que não traz a escolhida desfaz a escolha', async () => {
    RelacionamentosAPI.pessoas.mockResolvedValue({
      data: { itens: [BRUNO], total: 1, tem_mais: false },
    });
    const w = await abrirPessoa();
    await escolherNoMais(w, 'juntar');
    await w.get('[data-pessoa="8"]').setValue(true);
    RelacionamentosAPI.pessoas.mockResolvedValue({
      data: {
        itens: [{ ...BRUNO, id: 9, name: 'Carla Pires' }],
        total: 1,
        tem_mais: false,
      },
    });
    await buscar(w, 'Carla');
    await w.get(marca('juntar-confirmar')).trigger('submit');
    expect(w.get(marca('juntar-falta')).text()).toBe(
      'Escolha a outra ficha na lista.'
    );
    expect(w.find(marca('juntar-sai')).exists()).toBe(false);
  });

  it('sem escolher ninguém, Continuar diz o que falta e não avança', async () => {
    const w = await abrirPessoa();
    await escolherNoMais(w, 'juntar');
    await w.get(marca('juntar-confirmar')).trigger('submit');
    expect(w.get(marca('juntar-falta')).text()).toBe(
      'Escolha a outra ficha na lista.'
    );
    expect(w.find(marca('juntar-fica')).exists()).toBe(false);
  });

  it('busca sem resultado diz o que foi procurado', async () => {
    RelacionamentosAPI.pessoas.mockResolvedValue({
      data: { itens: [ANA], total: 1, tem_mais: false },
    });
    const w = await abrirPessoa();
    await escolherNoMais(w, 'juntar');
    await buscar(w, 'Zélia');
    expect(w.get(marca('ninguem')).text()).toBe(
      'Não achei ninguém com “Zélia”. Confira o que você digitou.'
    );
  });

  it('se o servidor recusa, o diálogo fica aberto e diz que não juntou', async () => {
    RelacionamentosAPI.pessoas.mockResolvedValue({
      data: { itens: [BRUNO], total: 1, tem_mais: false },
    });
    AccountActionsAPI.merge.mockRejectedValue(erroHttp(500));
    const w = await abrirPessoa();
    await escolherNoMais(w, 'juntar');
    await buscar(w, 'Bruno');
    await w.get('[data-pessoa="8"]').setValue(true);
    await w.get(marca('juntar-confirmar')).trigger('submit');
    await w.get(marca('juntar-confirmar')).trigger('submit');
    await flushPromises();
    expect(w.get(marca('alerta-do-juntar')).text()).toBe(
      'Não consegui juntar as fichas. Tente de novo.'
    );
  });
});

describe('bloquear e desbloquear', () => {
  it('pergunta antes, bloqueia, diz que deu certo e leva o foco à faixa, que tem "Desbloquear"', async () => {
    ContactAPI.update.mockResolvedValue({ data: {} });
    const w = await abrirPessoa();
    RelacionamentosAPI.pessoa.mockResolvedValue({
      data: { ...ANA, blocked: true },
    });
    await escolherNoMais(w, 'bloquear');
    expect(w.get('[data-carteira="confirmar-bloquear"]').text()).toContain(
      'Se Ana mandar mensagem, a mensagem fica guardada e ninguém da equipe é avisado.'
    );
    await confirmar(w, 'confirmar-bloquear');
    expect(ContactAPI.update).toHaveBeenCalledWith(7, { blocked: true });
    const faixa = w.get(marca('faixa-bloqueada'));
    expect(faixa.text()).toContain(
      'A ficha de Ana Albuquerino está bloqueada.'
    );
    expect(faixa.find(marca('desbloquear')).exists()).toBe(true);
    expect(document.activeElement).toBe(faixa.element);
    expect(useAlert).toHaveBeenCalledWith(
      'Pronto. A ficha de Ana Albuquerino está bloqueada.'
    );
    // A faixa já tem "Desbloquear": o aviso não repete com "Desfazer".
    expect(w.find('[data-carteira="desfazer"]').exists()).toBe(false);
  });

  it('a faixa de quem está bloqueado desbloqueia direto', async () => {
    servidorResponde({ ...ANA, blocked: true });
    ContactAPI.update.mockResolvedValue({ data: {} });
    const w = await abrirPessoa();
    RelacionamentosAPI.pessoa.mockResolvedValue({ data: ANA });
    await w.get(marca('desbloquear')).trigger('click');
    await flushPromises();
    expect(ContactAPI.update).toHaveBeenCalledWith(7, { blocked: false });
    expect(useAlert).toHaveBeenCalledWith(
      'Pronto. A ficha de Ana Albuquerino está desbloqueada.'
    );
  });
});

describe('apagar a pessoa', () => {
  it('sem a permissão de apagar, o "⋯" não tem Apagar', async () => {
    const w = await abrirPessoa();
    await w.get(marca('mais-acoes')).trigger('click');
    expect(w.find('[data-mais="apagar"]').exists()).toBe(false);
  });

  it('pergunta, apaga pelo contato e volta para a lista com o aviso', async () => {
    pode.apagar = true;
    ContactAPI.delete.mockResolvedValue({ data: {} });
    const w = await abrirPessoa();
    await escolherNoMais(w, 'apagar');
    expect(w.get('[data-carteira="confirmar-apagar"]').text()).toContain(
      'A ficha de Ana Albuquerino sai do sistema, com as conversas, as mensagens e as notas. Não dá para desfazer.'
    );
    await confirmar(w, 'confirmar-apagar');
    expect(ContactAPI.delete).toHaveBeenCalledWith(7);
    expect(useAlert).toHaveBeenCalledWith(
      'A ficha de Ana Albuquerino foi apagada.'
    );
    expect(contexto.empurrar).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'relationships_home' })
    );
  });

  it('diz quantos seguros saem e o que acontece com os cards, como o servidor faz', async () => {
    pode.apagar = true;
    conta.carteira = true;
    RelacionamentosAPI.cardsDaPessoa.mockResolvedValue({
      data: [
        {
          id: 3,
          titulo: 'Seguro auto',
          funil: 'Vendas',
          etapa: 'Novo',
          valor: 0,
          situacao: 'aberto',
        },
      ],
    });
    const w = await abrirPessoa();
    await escolherNoMais(w, 'apagar');
    const aviso = w.get('[data-carteira="confirmar-apagar"]').text();
    expect(aviso).toContain(
      'Os 2 seguros de Ana Albuquerino também saem, com o PDF.'
    );
    expect(aviso).toContain('Os cards continuam no funil, sem a pessoa.');
  });

  it('com a flag crm_arquivados, diz que os cards ficam sem os dados e as reuniões são canceladas', async () => {
    pode.apagar = true;
    conta.flags = ['crm_arquivados'];
    RelacionamentosAPI.cardsDaPessoa.mockResolvedValue({
      data: [
        {
          id: 3,
          titulo: 'Seguro auto',
          funil: 'Vendas',
          etapa: 'Novo',
          valor: 0,
          situacao: 'aberto',
        },
      ],
    });
    const w = await abrirPessoa();
    await escolherNoMais(w, 'apagar');
    const aviso = w.get('[data-carteira="confirmar-apagar"]').text();
    expect(aviso).toContain(
      'Os cards continuam no funil, sem os dados da pessoa, e as reuniões marcadas são canceladas.'
    );
    expect(aviso).not.toContain('seguro');
  });

  it('se o servidor diz por que não apagou, a frase dele aparece no diálogo', async () => {
    pode.apagar = true;
    ContactAPI.delete.mockRejectedValue(
      erroHttp(422, { message: 'Ana Albuquerino está Online, tente depois' })
    );
    const w = await abrirPessoa();
    await escolherNoMais(w, 'apagar');
    await confirmar(w, 'confirmar-apagar');
    expect(w.get('[data-carteira="alerta-do-dialogo"]').text()).toBe(
      'Ana Albuquerino está Online, tente depois'
    );
    expect(contexto.empurrar).not.toHaveBeenCalled();
  });
});

describe('etiquetas', () => {
  const ETIQUETAS_DA_CONTA = {
    data: {
      payload: [
        { title: 'site', color: '#0F766E' },
        { title: 'feira', color: '#1F6FEB' },
      ],
    },
  };
  const salvarNoDialogo = async w => {
    await w
      .get('[data-carteira="dialogo-etiquetas"]')
      .element.closest('[data-dialogo-falso]')
      .querySelector('[data-carteira="dialogo-confirmar"]')
      .click();
    await flushPromises();
  };

  it('o cabeçalho mostra cada etiqueta com a cor dela', async () => {
    LabelsAPI.get.mockResolvedValue(ETIQUETAS_DA_CONTA);
    const w = await abrirPessoa();
    const feira = w.get('[data-etiqueta-da-pessoa="feira"]');
    expect(feira.text()).toBe('feira');
    expect(feira.find('span').attributes('style')).toContain(
      'background: rgb(31, 111, 235)'
    );
  });

  it('salva só o que mudou, diz o que entrou e saiu, e "Desfazer" faz o contrário', async () => {
    LabelsAPI.get.mockResolvedValue(ETIQUETAS_DA_CONTA);
    EtiquetasDoContatoAPI.alterar.mockResolvedValue({ data: {} });
    const w = await abrirPessoa();
    await w.get(marca('mudar-etiquetas')).trigger('click');
    await flushPromises();
    const caixa = nome => w.get(`[data-etiqueta="${nome}"] input`);
    expect(caixa('feira').element.checked).toBe(true);
    expect(caixa('site').element.checked).toBe(false);
    await caixa('feira').setValue(false);
    await caixa('site').setValue(true);
    RelacionamentosAPI.pessoa.mockResolvedValue({
      data: { ...ANA, labels: ['site'] },
    });
    await salvarNoDialogo(w);
    expect(EtiquetasDoContatoAPI.alterar).toHaveBeenCalledWith(7, {
      por: ['site'],
      tirar: ['feira'],
    });
    expect(w.get(marca('cabecalho')).text()).toContain('site');
    expect(w.get('[data-carteira="aviso-vivo"]').text()).toContain(
      'Pronto. Entrou: site. Saiu: feira.'
    );
    RelacionamentosAPI.pessoa.mockResolvedValue({ data: ANA });
    await desfazer(w);
    expect(EtiquetasDoContatoAPI.alterar).toHaveBeenLastCalledWith(7, {
      por: ['feira'],
      tirar: ['site'],
    });
    expect(w.get('[data-carteira="aviso-vivo"]').text()).toContain(
      'As etiquetas voltaram a ser como antes.'
    );
  });

  it('se o servidor recusa, a frase dele aparece no diálogo', async () => {
    LabelsAPI.get.mockResolvedValue(ETIQUETAS_DA_CONTA);
    EtiquetasDoContatoAPI.alterar.mockRejectedValue(
      erroHttp(422, { message: 'no máximo 50 etiquetas por vez' })
    );
    const w = await abrirPessoa();
    await w.get(marca('mudar-etiquetas')).trigger('click');
    await flushPromises();
    await w.get('[data-etiqueta="site"] input').setValue(true);
    await salvarNoDialogo(w);
    expect(w.get('[data-carteira="alerta-do-dialogo"]').text()).toBe(
      'no máximo 50 etiquetas por vez'
    );
  });

  it('o × fecha o aviso', async () => {
    LabelsAPI.get.mockResolvedValue(ETIQUETAS_DA_CONTA);
    EtiquetasDoContatoAPI.alterar.mockResolvedValue({ data: {} });
    const w = await abrirPessoa();
    await w.get(marca('mudar-etiquetas')).trigger('click');
    await flushPromises();
    await w.get('[data-etiqueta="site"] input').setValue(true);
    await salvarNoDialogo(w);
    await w.get('[data-carteira="fechar-aviso"]').trigger('click');
    expect(w.get('[data-carteira="aviso-vivo"]').text()).toBe('');
  });
});

describe('notas, "não quer mensagens" e conversas', () => {
  it('apagar nota pergunta antes, com o texto dela, e a nota sai', async () => {
    ContactNotesAPI.delete.mockResolvedValue({ data: {} });
    const w = await abrirPessoa();
    await w.get(marca('apagar-nota')).trigger('click');
    await flushPromises();
    expect(w.get('[data-carteira="confirmar-apagar-nota"]').text()).toContain(
      '“Ligar.” sai da ficha de Ana Albuquerino.'
    );
    await confirmar(w, 'confirmar-apagar-nota');
    expect(ContactNotesAPI.delete).toHaveBeenCalledWith(7, 1);
    expect(w.find(marca('nota')).exists()).toBe(false);
    expect(useAlert).toHaveBeenCalledWith('Nota apagada.');
  });

  it('marcar "não quer mensagens" pergunta, marca, diz que deu certo e leva o foco à faixa', async () => {
    ContactAPI.markOptOut.mockResolvedValue({ data: {} });
    const w = await abrirPessoa();
    RelacionamentosAPI.pessoa.mockResolvedValue({
      data: { ...ANA, opted_out_at: AGORA, opt_out_source: 'manual' },
    });
    await w.get(marca('mais-acoes')).trigger('click');
    expect(w.get('[data-mais="naoQuer"]').text()).toBe(
      'Marcar que não quer mensagens'
    );
    await w.get('[data-mais="naoQuer"]').trigger('click');
    await flushPromises();
    await confirmar(w, 'confirmar-nao-quer');
    expect(ContactAPI.markOptOut).toHaveBeenCalledWith(7);
    const faixa = w.get(marca('faixa-nao-quer'));
    expect(faixa.text()).toContain('Marcado pela equipe nesta ficha.');
    expect(document.activeElement).toBe(faixa.element);
    expect(useAlert).toHaveBeenCalledWith(
      'Pronto. Ana Albuquerino não vai mais receber campanhas nem mensagens automáticas.'
    );
    expect(w.find('[data-carteira="desfazer"]').exists()).toBe(false);
  });

  it('"Ver todas" mostra as 5 conversas, e cada uma abre a conversa dela', async () => {
    const w = await abrirPessoa();
    expect(w.findAll(`${marca('conversas')} li`)).toHaveLength(3);
    await w.get(marca('ver-todas')).trigger('click');
    expect(w.findAll(`${marca('conversas')} li`)).toHaveLength(5);
    // "Ver menos" também embaixo; fechar por ele devolve o foco ao de cima.
    await w.get(marca('ver-menos-embaixo')).trigger('click');
    await flushPromises();
    expect(w.findAll(`${marca('conversas')} li`)).toHaveLength(3);
    expect(document.activeElement).toBe(w.get(marca('ver-todas')).element);
    await w.get(marca('ver-todas')).trigger('click');
    await w.get('[data-conversa="5"]').trigger('click');
    expect(contexto.empurrar).toHaveBeenCalledWith({
      name: 'inbox_conversation',
      params: { conversation_id: 5 },
      query: undefined,
    });
  });
});

describe('Ligar e Lembrete', () => {
  it('Ligar é o VoiceCallButton da casa, que decide pela caixa de voz e pelo telefone', async () => {
    const w = await abrirPessoa();
    expect(w.get('[data-ligar]').attributes('data-fone')).toBe(
      '+5511910310001'
    );
  });

  it('Lembrete, com a permissão, abre a gaveta do lembrete já com a pessoa', async () => {
    pode.lembrete = true;
    const w = await abrirPessoa();
    expect(w.find('[data-lembrete-gaveta]').exists()).toBe(false);
    await w.get(marca('lembrete')).trigger('click');
    await flushPromises();
    const gaveta = w.get('[data-lembrete-gaveta]');
    expect(gaveta.text()).toBe('Ana Albuquerino | Falar com Ana');
    const amanha = new Date();
    amanha.setDate(amanha.getDate() + 1);
    expect(gaveta.attributes('data-dia')).toBe(amanha.toDateString());
  });

  it('sem a permissão, não tem Lembrete', async () => {
    const w = await abrirPessoa();
    expect(w.find(marca('lembrete')).exists()).toBe(false);
  });
});

describe('#3075 — os dados da ficha antiga', () => {
  const definicao = (id, chave, tipo, nome) => ({
    id,
    attribute_model: 'contact_attribute',
    attribute_key: chave,
    attribute_display_name: nome,
    attribute_display_type: tipo,
    attribute_values: [],
  });
  const COMPLETA = {
    ...ANA,
    company_id: 3,
    additional_attributes: {
      city: 'Santos',
      company_name: 'Padaria Dornelaz',
      country_code: 'BR',
      country: 'Brazil',
      description: 'Prefere conversar à tarde.',
    },
    custom_attributes: {
      aniversario: '1990-05-12',
      vip: true,
      site: 'https://padariadornelaz.com.br',
    },
  };
  beforeEach(() => {
    daConta.definicoes = [
      definicao(1, 'aniversario', 'date', 'Aniversário'),
      definicao(2, 'vip', 'checkbox', 'Cliente VIP'),
      definicao(3, 'site', 'link', 'Site da padaria'),
      definicao(4, 'apelido', 'text', 'Apelido'),
    ];
    servidorResponde(COMPLETA);
  });
  const informacao = (w, chave) => w.get(`[data-informacao="${chave}"]`);
  const valor = (w, chave) => informacao(w, chave).get('dd').text();
  const nome = (w, chave) => informacao(w, chave).get('dt').text();

  it('Informações mostra país, "Sobre a pessoa" e os campos com o nome e o tipo', async () => {
    const w = await abrirPessoa();
    expect([nome(w, 'pais'), valor(w, 'pais')]).toEqual(['País', 'Brasil']);
    expect([nome(w, 'sobre'), valor(w, 'sobre')]).toEqual([
      'Sobre a pessoa',
      'Prefere conversar à tarde.',
    ]);
    expect([
      nome(w, 'conta:aniversario'),
      valor(w, 'conta:aniversario'),
    ]).toEqual(['Aniversário', '12/05/1990']);
    expect([nome(w, 'conta:vip'), valor(w, 'conta:vip')]).toEqual([
      'Cliente VIP',
      'Sim',
    ]);
    expect(informacao(w, 'conta:site').get('a').attributes('href')).toBe(
      'https://padariadornelaz.com.br/'
    );
    // Sem valor e fora da escolha do configurador: não aparece.
    expect(w.find('[data-informacao="conta:apelido"]').exists()).toBe(false);
  });

  it('quem só pode ver lê tudo e o aviso, sem nenhum botão de mudar', async () => {
    pode.editar = false;
    const w = await abrirPessoa();
    expect(w.get(marca('so-leitura')).text()).toBe(
      'Você pode ver estas informações, mas não pode mudar.'
    );
    expect(valor(w, 'conta:vip')).toBe('Sim');
    expect(w.find(marca('alterar')).exists()).toBe(false);
    expect(w.find(marca('mais-acoes')).exists()).toBe(false);
    expect(w.find(marca('mudar-etiquetas')).exists()).toBe(false);
    expect(w.find(marca('escolher-campos')).exists()).toBe(false);
    expect(w.find(marca('empresa-da-pessoa')).text()).toBe('Padaria Dornelaz');
  });

  it('"Este contato é" só com a chave `contato_relacao`, e só lê para quem só vê', async () => {
    let w = await abrirPessoa();
    expect(w.find(marca('este-contato-e')).exists()).toBe(false);
    w.unmount();

    conta.flags = ['contato_relacao'];
    pode.editar = false;
    w = await abrirPessoa();
    const secao = w.get(marca('este-contato-e'));
    expect(secao.text()).toContain('Este contato é');
    expect(secao.get('[data-escolha-da-relacao]').attributes()).toMatchObject({
      'data-pessoa': '7',
      'data-pode-editar': 'false',
    });
  });

  it('a gaveta abre com a foto, o país, "Sobre a pessoa" e os campos da conta', async () => {
    const w = await abrirPessoa();
    await w.get(marca('alterar')).trigger('click');
    await flushPromises();
    const gaveta = document.body.querySelector(
      '[data-relacionamentos="gaveta-informacoes"]'
    );
    expect(
      gaveta.querySelector('[data-relacionamentos="foto-da-pessoa"]')
    ).not.toBeNull();
    expect(
      gaveta.querySelector('[data-relacionamentos="pais-da-pessoa"]')
        .textContent
    ).toContain('Brasil');
    expect(
      gaveta.querySelector('textarea[data-relacionamentos="sobre-a-pessoa"]')
        .value
    ).toBe('Prefere conversar à tarde.');
    expect(
      [...gaveta.querySelectorAll('[data-atributo]')].map(
        campo => campo.dataset.atributo
      )
    ).toEqual(['aniversario', 'vip', 'site', 'apelido']);
  });
});
