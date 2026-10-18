import { ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import NovaConversaBarraDoEmail from '../NovaConversaBarraDoEmail.vue';
import NovaConversaMensagem from '../NovaConversaMensagem.vue';
import BotaoDeAudio from '../../conversa-canal/email/BotaoDeAudio.vue';
import { TIPOS } from '../novaConversa';

// #1809 — a gaveta "Escrever" do e-mail com a barra da resposta de e-mail nova:
// "+", emoji, microfone e assinatura, na mesma ordem, inserindo no editor da gaveta.
const estado = vi.hoisted(() => ({
  setSignatureFlagForInbox: vi.fn(),
  listar: vi.fn(),
  ditadoDisponivel: vi.fn(),
  ditar: vi.fn(),
  chave: true,
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useMapGetter: nome => {
    const getters = {
      getCurrentAccountId: 7,
      'inboxes/getInbox': id =>
        id === 4 ? { channel_type: INBOX_TYPES.EMAIL } : {},
      'accounts/isFeatureEnabledonAccount': (_conta, flag) =>
        flag === 'conversa_email_nova' && estado.chave,
      'inboxes/getConversationWhatsAppTemplates': () => [],
      'globalConfig/get': { directUploadsEnabled: false },
      getSelectedChat: {},
    };
    return ref(getters[nome]);
  },
}));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    setSignatureFlagForInbox: estado.setSignatureFlagForInbox,
    fetchSignatureFlagFromUISettings: () => false,
  }),
}));
vi.mock('dashboard/composables/useFileUpload', () => ({
  useFileUpload: ({ attachFile }) => ({
    onFileUpload: file => attachFile({ file }),
  }),
}));
vi.mock('dashboard/api/modelosDeEmail', () => ({
  default: { listar: estado.listar },
}));
vi.mock('dashboard/api/conversaEmail', () => ({
  default: {
    ditadoDisponivel: estado.ditadoDisponivel,
    ditar: estado.ditar,
  },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-router', () => ({ useRouter: () => ({ push: vi.fn() }) }));

const EMAIL = {
  id: 4,
  name: 'Comercial',
  channelType: INBOX_TYPES.EMAIL,
  email: 'comercial@loja.com',
};

const GLOBAL = {
  stubs: {
    Icon: true,
    OndaAoVivo: true,
    TeleportWithDirection: { template: '<slot />' },
  },
};

const montarBarra = (props = {}) =>
  mount(NovaConversaBarraDoEmail, {
    props: { canal: EMAIL, comAssinatura: false, anexos: [], ...props },
    global: { ...GLOBAL },
  });

beforeEach(() => {
  estado.chave = true;
  estado.setSignatureFlagForInbox.mockReset();
  estado.listar.mockReset().mockResolvedValue({ data: { payload: [] } });
  estado.ditadoDisponivel
    .mockReset()
    .mockResolvedValue({ data: { disponivel: true, traducao: false } });
});

describe('NovaConversaBarraDoEmail (#1809)', () => {
  it('tem +, emoji, microfone e assinatura, nessa ordem, como na resposta', async () => {
    const wrapper = montarBarra();
    await flushPromises();
    const ordem = wrapper
      .findAll('[role=toolbar] > *')
      .map(item =>
        [
          'data-mais-do-email',
          'data-emoji-do-email',
          'data-ditar',
          'data-assinatura-do-email',
        ].find(
          marca =>
            item.attributes(marca) !== undefined ||
            item.find(`[${marca}]`).exists()
        )
      );
    expect(ordem).toEqual([
      'data-mais-do-email',
      'data-emoji-do-email',
      'data-ditar',
      'data-assinatura-do-email',
    ]);
  });

  it('o "+" não oferece Modelo de e-mail nem busca os modelos (não há conversa)', async () => {
    const wrapper = montarBarra();
    await flushPromises();
    await wrapper.find('[data-mais-do-email]').trigger('click');
    const itens = wrapper
      .findAll('[data-item-do-mais]')
      .map(item => item.attributes('data-item-do-mais'));
    expect(itens).toEqual(['documento', 'fotos']);
    expect(estado.listar).not.toHaveBeenCalled();
  });

  it('o arquivo escolhido no "+" entra nos anexos da gaveta, com id próprio', async () => {
    const wrapper = montarBarra();
    const seletor = wrapper.find('[data-seletor-do-mais]');
    const arquivo = new File(['oi'], 'proposta.pdf', {
      type: 'application/pdf',
    });
    Object.defineProperty(seletor.element, 'files', { value: [arquivo] });
    await seletor.trigger('change');
    await vi.waitFor(() =>
      expect(wrapper.emitted('update:anexos')).toBeTruthy()
    );
    const [[anexos]] = wrapper.emitted('update:anexos');
    expect(anexos).toHaveLength(1);
    expect(anexos[0].resource.name).toBe('proposta.pdf');
    expect(anexos[0].resource.file).toBe(arquivo);
    expect(anexos[0].resource.id).toBeTruthy();
  });

  it('o emoji abre a janela, e o escolhido vai para o editor da gaveta', async () => {
    const wrapper = montarBarra();
    expect(wrapper.find('[data-janela-de-emojis]').exists()).toBe(false);
    await wrapper.find('[data-emoji-do-email]').trigger('click');
    expect(wrapper.find('[data-janela-de-emojis]').exists()).toBe(true);
    const primeiro = wrapper.find('[data-janela-de-emojis] .grid button');
    await primeiro.trigger('click');
    expect(wrapper.emitted('inserir')).toEqual([[primeiro.text()]]);
  });

  it('a assinatura liga e desliga pela mesma chave da resposta', async () => {
    const desligada = montarBarra();
    const botao = desligada.find('[data-assinatura-do-email]');
    expect(botao.attributes('data-ligado')).toBeUndefined();
    expect(botao.attributes('aria-pressed')).toBe('false');
    await botao.trigger('click');
    expect(estado.setSignatureFlagForInbox).toHaveBeenCalledWith(
      INBOX_TYPES.EMAIL,
      true
    );

    const ligada = montarBarra({ comAssinatura: true });
    const acesa = ligada.find('[data-assinatura-do-email]');
    expect(acesa.attributes('data-ligado')).toBeDefined();
    await acesa.trigger('click');
    expect(estado.setSignatureFlagForInbox).toHaveBeenLastCalledWith(
      INBOX_TYPES.EMAIL,
      false
    );
  });
});

describe('BotaoDeAudio: para onde vai o texto ditado (#1809)', () => {
  const ditarAte = async props => {
    const parar = vi.fn();
    const pista = { stop: parar };
    const fluxo = { getTracks: () => [pista] };
    navigator.mediaDevices = { getUserMedia: vi.fn(async () => fluxo) };
    globalThis.MediaRecorder = class {
      constructor(stream) {
        this.stream = stream;
        this.state = 'inactive';
      }

      start() {
        this.state = 'recording';
      }

      stop() {
        this.state = 'inactive';
        this.ondataavailable?.({ data: new Blob(['a']) });
        this.onstop?.();
      }
    };
    estado.ditar.mockResolvedValue({ data: { texto: 'bom dia' } });
    const wrapper = mount(BotaoDeAudio, {
      props,
      global: { ...GLOBAL },
    });
    await flushPromises();
    await wrapper.find('[data-ditar]').trigger('click');
    await flushPromises();
    await wrapper.find('[data-parar-ditado]').trigger('click');
    await flushPromises();
  };

  it('na gaveta, o texto vai para quem a gaveta mandou (não para a resposta aberta)', async () => {
    const inserir = vi.fn();
    const ouvinte = vi.fn();
    emitter.on(BUS_EVENTS.INSERT_INTO_RICH_EDITOR, ouvinte);
    await ditarAte({ inserir });
    emitter.off(BUS_EVENTS.INSERT_INTO_RICH_EDITOR, ouvinte);
    expect(inserir).toHaveBeenCalledWith('bom dia ');
    expect(ouvinte).not.toHaveBeenCalled();
  });

  it('na resposta (sem `inserir`), segue pelo editor da resposta', async () => {
    const ouvinte = vi.fn();
    emitter.on(BUS_EVENTS.INSERT_INTO_RICH_EDITOR, ouvinte);
    await ditarAte({});
    emitter.off(BUS_EVENTS.INSERT_INTO_RICH_EDITOR, ouvinte);
    expect(ouvinte).toHaveBeenCalledWith('bom dia ');
  });
});

describe('NovaConversaMensagem: a barra só no e-mail com a chave (#1809)', () => {
  const montarMensagem = () =>
    mount(NovaConversaMensagem, {
      props: { canal: EMAIL, tipo: TIPOS.EMAIL },
      global: {
        ...GLOBAL,
        stubs: {
          ...GLOBAL.stubs,
          MessageEditor: true,
          EmailOptions: true,
          NovaConversaBarraDoEmail: true,
          NovaConversaAnexo: true,
        },
      },
    });

  it('com a chave: a barra da resposta, sem o "Anexar arquivo" solto', () => {
    const wrapper = montarMensagem();
    expect(
      wrapper.findComponent({ name: 'NovaConversaBarraDoEmail' }).exists()
    ).toBe(true);
    expect(wrapper.findComponent({ name: 'NovaConversaAnexo' }).exists()).toBe(
      false
    );
  });

  it('sem a chave: como antes, com o "Anexar arquivo"', () => {
    estado.chave = false;
    const wrapper = montarMensagem();
    expect(
      wrapper.findComponent({ name: 'NovaConversaBarraDoEmail' }).exists()
    ).toBe(false);
    expect(wrapper.findComponent({ name: 'NovaConversaAnexo' }).exists()).toBe(
      true
    );
  });
});
