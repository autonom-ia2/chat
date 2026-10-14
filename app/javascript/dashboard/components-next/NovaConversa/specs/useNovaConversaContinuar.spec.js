import { nextTick, ref } from 'vue';
import { flushPromises } from '@vue/test-utils';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import conversaActions from 'dashboard/store/modules/conversations/actions';
import { useNovaConversa } from '../useNovaConversa';
import { TIPOS } from '../novaConversa';

// #1505 — o envio dentro de uma conversa que já existe, pela ação de verdade
// da caixa de resposta (sendMessageWithData → MessageApi.create): só o axios
// é de mentira, para conferir o formato que sai (anexos, cópias).
const estado = vi.hoisted(() => ({ dispatch: null, axios: null }));

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: chave => chave }) }));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: estado.dispatch }),
  useMapGetter: nome => {
    const getters = {
      getCurrentUser: { id: 3 },
      getCurrentAccountId: 7,
      'globalConfig/get': { directUploadsEnabled: false },
      getMessageSignature: '',
    };
    return ref(getters[nome]);
  },
}));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({ fetchSignatureFlagFromUISettings: () => false }),
}));

const ANA = { id: 1, name: 'Ana' };
const BIA = { id: 2, name: 'Bia' };
const EMAIL = {
  id: 4,
  name: 'Contato',
  channelType: INBOX_TYPES.EMAIL,
  email: 'oi@loja.com',
};

const montar = () => {
  const contato = ref(ANA);
  const canal = ref(EMAIL);
  const continuar = {
    conversa: ref({ displayId: 77, visible: true }),
    tipo: ref(TIPOS.EMAIL),
    esperando: ref(false),
    oculta: ref(false),
  };
  return {
    contato,
    canal,
    ...useNovaConversa({ contato, canal, continuar }),
  };
};

const pedidos = () => estado.axios.mock.calls.map(([pedido]) => pedido);

describe('useNovaConversa — continuar a conversa', () => {
  beforeEach(() => {
    estado.axios = vi.fn(async () => ({ data: { id: 900 } }));
    globalThis.axios = estado.axios;
    window.history.pushState({}, '', '/app/accounts/7/contacts/1');
    estado.dispatch = vi.fn(async (acao, dados) =>
      acao === 'sendMessageWithData'
        ? conversaActions.sendMessageWithData({ commit: vi.fn() }, dados)
        : null
    );
  });

  it('e-mail continuado leva anexo e cópias, sem assunto e sem criar conversa', async () => {
    const envio = montar();
    const arquivo = new File(['oi'], 'proposta.pdf');
    Object.assign(envio.form, {
      mensagem: 'Segue a proposta',
      cc: 'chefe@ana.com',
      bcc: 'oculto@ana.com',
      anexos: [{ resource: { file: arquivo } }],
    });

    expect(envio.falta.value).toBe('');
    await envio.enviar(() => null);
    await flushPromises();

    expect(
      estado.dispatch.mock.calls.some(
        ([acao]) => acao === 'contactConversations/create'
      )
    ).toBe(false);
    const [pedido] = pedidos();
    expect(pedido.url).toBe('/api/v1/accounts/7/conversations/77/messages');
    expect(pedido.data).toBeInstanceOf(FormData);
    expect(pedido.data.get('content')).toBe('Segue a proposta');
    expect(pedido.data.getAll('attachments[]')).toEqual([arquivo]);
    expect(pedido.data.get('cc_emails')).toBe('chefe@ana.com');
    expect(pedido.data.get('bcc_emails')).toBe('oculto@ana.com');
    expect(pedido.data.get('private')).toBe('false');
    expect(envio.enviada.value).toMatchObject({ id: 77, numero: 77 });
    expect(envio.enviada.value.assunto).toBe('');
  });

  it('troca de contato no meio do envio: confirma o que saiu e guarda o rascunho novo', async () => {
    let responder;
    estado.axios = vi.fn(
      () =>
        new Promise(resolve => {
          responder = resolve;
        })
    );
    globalThis.axios = estado.axios;
    const envio = montar();
    envio.form.mensagem = 'Para a Ana';

    const enviando = envio.enviar(() => null);
    envio.contato.value = BIA;
    await nextTick();
    envio.form.mensagem = 'Rascunho da Bia';
    responder({ data: { id: 901 } });
    await enviando;
    await flushPromises();

    expect(envio.enviada.value).toMatchObject({
      nome: 'Ana',
      texto: 'Para a Ana',
      caixa: 'Contato',
      numero: 77,
    });
    expect(envio.form.mensagem).toBe('Rascunho da Bia');
  });
});
