import { reactive, ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import conversaActions from 'dashboard/store/modules/conversations/actions';
import { useAlert } from 'dashboard/composables';
import { useNovaConversa } from '../useNovaConversa';
import { TIPOS } from '../novaConversa';
import NovaConversaRodape from '../NovaConversaRodape.vue';

// #2067 (decisão 5 do Rodrigo, 22/10): na gaveta "Enviar mensagem" de Relacionamentos,
// a conversa que já existe mostra o mesmo ícone "ficar com a conversa ao enviar" e o envio
// leva o mesmo pedido da caixa de resposta: texto, modelo e cada parte do WhatsApp. O envio
// é o de verdade (sendMessageWithData → MessageApi.create): só o axios é de mentira.
const estado = vi.hoisted(() => ({
  dispatch: null,
  axios: null,
  rascunho: {},
  ligada: true,
}));

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: chave => chave }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: estado.dispatch }),
  useMapGetter: nome => {
    const getters = {
      getCurrentUser: { id: 3 },
      getCurrentAccountId: 7,
      'globalConfig/get': { directUploadsEnabled: false },
      getMessageSignature: '',
      'inboxes/getInbox': () => ({}),
      'accounts/isFeatureEnabledonAccount': (_conta, flag) =>
        estado.ligada && flag === 'ficar_com_a_conversa_ao_enviar',
      'draftMessages/get': chave => estado.rascunho[chave] || '',
    };
    return ref(getters[nome]);
  },
}));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({ fetchSignatureFlagFromUISettings: () => false }),
}));

const ANA = { id: 1, name: 'Ana' };
const COLEGA = { assignee: { id: 9, name: 'Bia' }, assignee_type: 'User' };
const COM_IA = { assignee: { id: 30, name: 'Lia' }, assignee_type: 'AgentBot' };
const EMAIL = {
  id: 4,
  name: 'Contato',
  channelType: INBOX_TYPES.EMAIL,
  email: 'oi@loja.com',
};
const WHATSAPP = {
  id: 5,
  name: 'WhatsApp',
  channelType: INBOX_TYPES.WHATSAPP,
  provider: 'whatsapp_cloud',
};

const montar = ({ meta = COM_IA, canal = EMAIL, conversa = true } = {}) => {
  const contato = ref(ANA);
  const daCaixa = ref(canal);
  const continuar = {
    conversa: ref(conversa ? { displayId: 77, visible: true } : null),
    tipo: ref(canal === EMAIL ? TIPOS.EMAIL : TIPOS.WHATSAPP_LIVRE),
    esperando: ref(false),
    oculta: ref(false),
    assunto: ref(''),
    ultimoEmail: ref(null),
    soTexto: ref(false),
    meta: ref({ sender: { id: 2 }, ...meta }),
    carregar: vi.fn(),
  };
  return {
    contato,
    ...useNovaConversa({ contato, canal: daCaixa, continuar }),
  };
};

const pedidos = () => estado.axios.mock.calls.map(([pedido]) => pedido);
const campo = (pedido, nome) =>
  pedido.data instanceof FormData ? pedido.data.get(nome) : pedido.data[nome];

describe('useNovaConversa — ficar com a conversa (#2067)', () => {
  beforeEach(() => {
    estado.ligada = true;
    // O rascunho é reativo, como o da loja de verdade.
    estado.rascunho = reactive({});
    useAlert.mockClear();
    estado.axios = vi.fn(async () => ({ data: { id: 900 } }));
    globalThis.axios = estado.axios;
    window.history.pushState({}, '', '/app/accounts/7/contacts/1');
    estado.dispatch = vi.fn(async (acao, dados) => {
      if (acao === 'sendMessageWithData') {
        return conversaActions.sendMessageWithData({ commit: vi.fn() }, dados);
      }
      if (acao === 'draftMessages/set')
        estado.rascunho[dados.key] = dados.message;
      if (acao === 'draftMessages/delete') delete estado.rascunho[dados.key];
      return null;
    });
  });

  it('conversa com a IA: o ícone vem ligado e o texto leva o pedido e o dono visto', async () => {
    const envio = montar();
    expect(envio.ficar).toMatchObject({ aplica: true, ligada: true });
    envio.form.mensagem = 'Oi, sou a Ana';

    await envio.enviar(() => null);
    await flushPromises();

    const [pedido] = pedidos();
    expect(pedido.url).toBe('/api/v1/accounts/7/conversations/77/messages');
    expect(campo(pedido, 'ficar_com_a_conversa')).toBe(true);
    expect(campo(pedido, 'ficar_com_a_conversa_de')).toEqual({ tipo: 'ia' });
  });

  it('conversa de colega: vem desligado e o envio diz que continua com ela', async () => {
    const envio = montar({ meta: COLEGA });
    expect(envio.ficar.ligada).toBe(false);
    envio.form.mensagem = 'Oi';

    await envio.enviar(() => null);
    await flushPromises();

    expect(campo(pedidos()[0], 'ficar_com_a_conversa')).toBe(false);
    expect(campo(pedidos()[0], 'ficar_com_a_conversa_de')).toEqual({
      tipo: 'pessoa',
      id: 9,
    });
  });

  it('modelo segue a regra do texto', async () => {
    const envio = montar({ meta: COLEGA, canal: WHATSAPP });
    envio.ficar.alternar();

    await envio.enviarPronta({
      message: 'Olá',
      templateParams: { name: 'oi' },
    });
    await flushPromises();

    expect(campo(pedidos()[0], 'template_params')).toEqual({ name: 'oi' });
    expect(campo(pedidos()[0], 'ficar_com_a_conversa')).toBe(true);
    expect(envio.ficar.ligada).toBe(false);
  });

  // Pega o aviso falso "Não deu para ficar" nas partes seguintes (a 1ª já ficou com a conversa).
  it('envio em partes (WhatsApp, um anexo por mensagem): só a 1ª pede para ficar', async () => {
    const envio = montar({ canal: WHATSAPP });
    Object.assign(envio.form, {
      mensagem: 'Seguem as fotos',
      anexos: [
        { resource: { file: new File(['a'], 'a.jpg') } },
        { resource: { file: new File(['b'], 'b.jpg') } },
      ],
    });

    await envio.enviar(() => null);
    await flushPromises();

    expect(pedidos()).toHaveLength(2);
    expect(pedidos().map(p => campo(p, 'ficar_com_a_conversa'))).toEqual([
      'true',
      'false',
    ]);
    pedidos().forEach(pedido => {
      expect(campo(pedido, 'ficar_com_a_conversa_de[tipo]')).toBe('ia');
    });
  });

  it('conversa nova: nada vai no envio (a regra da caixa decide)', async () => {
    const envio = montar({ conversa: false });
    expect(envio.ficar.aplica).toBe(false);
  });

  it('flag da conta desligada: sem ícone e sem pedido', async () => {
    estado.ligada = false;
    const envio = montar();
    expect(envio.ficar.aplica).toBe(false);
    envio.form.mensagem = 'Oi';

    await envio.enviar(() => null);
    await flushPromises();

    expect(campo(pedidos()[0], 'ficar_com_a_conversa')).toBeUndefined();
  });

  it('o envio falhou: a escolha do ícone volta', async () => {
    estado.axios = vi.fn(async () => {
      throw new Error('fora do ar');
    });
    globalThis.axios = estado.axios;
    const envio = montar();
    envio.ficar.alternar();
    envio.form.mensagem = 'Oi';

    await envio.enviar(() => null);
    await flushPromises();

    expect(envio.erro.value).not.toBe('');
    expect(envio.ficar.ligada).toBe(false);
  });

  it('o servidor não conseguiu ficar com a conversa: avisa', async () => {
    estado.axios = vi.fn(async () => ({
      data: { id: 901, ficar_com_a_conversa_nao_deu: true },
    }));
    globalThis.axios = estado.axios;
    const envio = montar();
    envio.form.mensagem = 'Oi';

    await envio.enviar(() => null);
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith('CONVERSA_CANAL.FICAR.NAO_DEU');
  });
});

describe('NovaConversaRodape — o ícone ao lado do Enviar (#2067)', () => {
  const montarRodape = ficar =>
    mount(NovaConversaRodape, {
      props: { modo: 'enviar', ficar },
      global: { mocks: { $t: chave => chave }, directives: { tooltip: {} } },
    });

  it('aparece com a conversa que já existe e some sem ela', () => {
    const ficar = { ligada: true, frase: 'x', alternar: vi.fn() };
    expect(
      montarRodape(ficar).find('[data-ficar-com-a-conversa]').exists()
    ).toBe(true);
    expect(
      montarRodape(null).find('[data-ficar-com-a-conversa]').exists()
    ).toBe(false);
  });
});
