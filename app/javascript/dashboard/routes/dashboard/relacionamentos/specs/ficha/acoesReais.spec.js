import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { useAlert } from 'dashboard/composables';
import AccountActionsAPI from 'dashboard/api/accountActions';
import ContactNotesAPI from 'dashboard/api/contactNotes';
import ContactAPI from 'dashboard/api/contacts';
import LabelsAPI from 'dashboard/api/labels';
import RelacionamentosAPI from 'dashboard/api/relacionamentos';
import FichaDaPessoaPage from '../../pages/FichaDaPessoaPage.vue';

// #3071 — as ações que vieram da ficha antiga, fora da demonstração: cada uma
// escreve pelo endpoint que a ficha antiga usava, pergunta antes quando apaga
// ou restringe, diz o que aconteceu e, quando dá, oferece "Desfazer".
const contexto = vi.hoisted(() => ({ params: {}, empurrar: vi.fn() }));
const pode = vi.hoisted(() => ({ apagar: false, lembrete: false }));
const caixas = vi.hoisted(() => ({ lista: [] }));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('../../components/carteira/SegurosDaFicha.vue', () => ({
  default: { render: () => null },
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    currentAccount: { value: { carteira_seguros: false } },
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
    podeEditar: { value: true },
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
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({
    get value() {
      return caixas.lista;
    },
  }),
}));
vi.mock('dashboard/helper/inbox', () => ({
  isVoiceCallEnabled: caixa => Boolean(caixa.voz),
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
      props: ['show', 'contato'],
      template: '<div data-lembrete-gaveta>{{ contato.name }}</div>',
    },
  })
);
vi.mock('../../components/carteira/ConversaNova.vue', () => ({
  default: { render: () => null, methods: { abrir: async () => false } },
}));
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
    updateContactLabels: vi.fn(),
  },
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
  caixas.lista = [];
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
    expect(dialogo.text()).toContain(
      'Tudo o que é de Bruno Dornelaz (conversas, notas, etiquetas e cards) passa para a ficha de Ana Albuquerino.'
    );
    expect(dialogo.text()).toContain(
      'A ficha de Bruno Dornelaz deixa de existir. Não dá para desfazer.'
    );
    await w.get(marca('juntar-confirmar')).trigger('submit');
    await flushPromises();
    expect(AccountActionsAPI.merge).toHaveBeenCalledWith(7, 8);
    expect(useAlert).toHaveBeenCalledWith(
      'Pronto. Tudo de Bruno Dornelaz agora está na ficha de Ana Albuquerino.'
    );
    expect(w.find(marca('dialogo-juntar')).exists()).toBe(false);
    // A ficha relê tudo: as conversas da outra pessoa entram.
    expect(RelacionamentosAPI.conversasDaPessoa).toHaveBeenCalledTimes(2);
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
  it('pergunta antes, bloqueia, mostra a faixa e "Desfazer" desbloqueia', async () => {
    ContactAPI.update.mockResolvedValue({ data: {} });
    const w = await abrirPessoa();
    RelacionamentosAPI.pessoa.mockResolvedValue({
      data: { ...ANA, blocked: true },
    });
    await escolherNoMais(w, 'bloquear');
    expect(w.get('[data-carteira="confirmar-bloquear"]').text()).toContain(
      'O que Ana mandar chega fechado e ninguém da equipe é avisado.'
    );
    await confirmar(w, 'confirmar-bloquear');
    expect(ContactAPI.update).toHaveBeenCalledWith(7, { blocked: true });
    expect(w.get(marca('faixa-bloqueada')).text()).toContain(
      'A ficha de Ana Albuquerino está bloqueada.'
    );
    expect(w.get('[data-carteira="aviso-vivo"]').text()).toContain(
      'Pronto. A ficha de Ana Albuquerino está bloqueada.'
    );
    RelacionamentosAPI.pessoa.mockResolvedValue({ data: ANA });
    await desfazer(w);
    expect(ContactAPI.update).toHaveBeenLastCalledWith(7, { blocked: false });
    expect(w.find(marca('faixa-bloqueada')).exists()).toBe(false);
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
      'Não dá para desfazer.'
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
  it('abre com as da pessoa marcadas, salva a lista inteira e "Desfazer" volta como era', async () => {
    LabelsAPI.get.mockResolvedValue({
      data: {
        payload: [
          { title: 'site', color: '#0F766E' },
          { title: 'feira', color: '#1F6FEB' },
        ],
      },
    });
    ContactAPI.updateContactLabels.mockResolvedValue({ data: {} });
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
    await w
      .get('[data-carteira="dialogo-etiquetas"]')
      .element.closest('[data-dialogo-falso]')
      .querySelector('[data-carteira="dialogo-confirmar"]')
      .click();
    await flushPromises();
    expect(ContactAPI.updateContactLabels).toHaveBeenCalledWith(7, ['site']);
    expect(w.get(marca('cabecalho')).text()).toContain('site');
    RelacionamentosAPI.pessoa.mockResolvedValue({ data: ANA });
    await desfazer(w);
    expect(ContactAPI.updateContactLabels).toHaveBeenLastCalledWith(7, [
      'feira',
    ]);
    expect(w.get('[data-carteira="aviso-vivo"]').text()).toContain(
      'As etiquetas voltaram a ser como antes.'
    );
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

  it('marcar "não quer mensagens" pergunta, marca, mostra a faixa e "Desfazer" libera', async () => {
    ContactAPI.markOptOut.mockResolvedValue({ data: {} });
    ContactAPI.removeOptOut.mockResolvedValue({ data: {} });
    const w = await abrirPessoa();
    RelacionamentosAPI.pessoa.mockResolvedValue({
      data: { ...ANA, opted_out_at: AGORA, opt_out_source: 'manual' },
    });
    await escolherNoMais(w, 'naoQuer');
    await confirmar(w, 'confirmar-nao-quer');
    expect(ContactAPI.markOptOut).toHaveBeenCalledWith(7);
    expect(w.find(marca('faixa-nao-quer')).exists()).toBe(true);
    RelacionamentosAPI.pessoa.mockResolvedValue({ data: ANA });
    await desfazer(w);
    expect(ContactAPI.removeOptOut).toHaveBeenCalledWith(7);
    expect(w.find(marca('faixa-nao-quer')).exists()).toBe(false);
  });

  it('"Ver todas" mostra as 5 conversas, e cada uma abre a conversa dela', async () => {
    const w = await abrirPessoa();
    expect(w.findAll(`${marca('conversas')} li`)).toHaveLength(3);
    await w.get(marca('ver-todas')).trigger('click');
    expect(w.findAll(`${marca('conversas')} li`)).toHaveLength(5);
    await w.get('[data-conversa="5"]').trigger('click');
    expect(contexto.empurrar).toHaveBeenCalledWith({
      name: 'inbox_conversation',
      params: { conversation_id: 5 },
      query: undefined,
    });
  });
});

describe('Ligar e Lembrete', () => {
  it('Ligar só aparece com caixa de voz na conta e telefone na pessoa', async () => {
    const semVoz = await abrirPessoa();
    expect(semVoz.find('[data-ligar]').exists()).toBe(false);
    semVoz.unmount();
    caixas.lista = [{ id: 1, voz: true }];
    const comVoz = await abrirPessoa();
    expect(comVoz.get('[data-ligar]').attributes('data-fone')).toBe(
      '+5511910310001'
    );
    comVoz.unmount();
    servidorResponde({ ...ANA, phone_number: null });
    const semTelefone = await abrirPessoa();
    expect(semTelefone.find('[data-ligar]').exists()).toBe(false);
  });

  it('Lembrete, com a permissão, abre a gaveta do lembrete já com a pessoa', async () => {
    pode.lembrete = true;
    const w = await abrirPessoa();
    expect(w.find('[data-lembrete-gaveta]').exists()).toBe(false);
    await w.get(marca('lembrete')).trigger('click');
    await flushPromises();
    expect(w.get('[data-lembrete-gaveta]').text()).toBe('Ana Albuquerino');
  });

  it('sem a permissão, não tem Lembrete', async () => {
    const w = await abrirPessoa();
    expect(w.find(marca('lembrete')).exists()).toBe(false);
  });
});
