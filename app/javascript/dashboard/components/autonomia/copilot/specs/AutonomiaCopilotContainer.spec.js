import { nextTick, ref, watch } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import AutonomiaCopilotAPI from 'dashboard/api/autonomiaCopilot';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { menuEGuia } from 'dashboard/components-next/sidebar/menuEGuia';
import { useAutonomiaCopilotStore } from 'dashboard/store/modules/autonomiaCopilot';
import AutonomiaCopilotContainer from '../AutonomiaCopilotContainer.vue';

const currentAccountId = ref(1);
const uiSettings = ref({ is_autonomia_copilot_panel_open: true });
const updateUISettings = vi.fn();
const selectedChat = ref({ id: 42 });

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
  useTrack: vi.fn(),
}));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    uiSettings,
    updateUISettings,
  }),
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: getter => {
    if (getter === 'globalConfig/get') {
      return ref({ crmKanbanEnabled: true, crmCopilotEnabled: true });
    }
    if (getter === 'getSelectedChat') return selectedChat;
    if (getter === 'getCurrentAccountId') return currentAccountId;
    return ref(null);
  },
}));
vi.mock('dashboard/api/autonomiaCopilot', () => ({
  default: { listAgents: vi.fn(), chat: vi.fn() },
}));

const mountCopilot = async () => {
  const wrapper = mount(AutonomiaCopilotContainer, {
    attachTo: document.body,
    global: {
      mocks: { $t: key => key },
      directives: { onClickOutside: {}, onClickaway: {}, dompurifyHtml: {} },
    },
  });
  await flushPromises();
  return wrapper;
};

const send = async (textarea, text) => {
  await textarea.setValue(text);
  await textarea.trigger('keydown', { key: 'Enter' });
  await flushPromises();
};

describe('AutonomiaCopilotContainer', () => {
  let wrapper;

  beforeEach(() => {
    currentAccountId.value = 1;
    selectedChat.value = { id: 42 };
    uiSettings.value = { is_autonomia_copilot_panel_open: true };
    AutonomiaCopilotAPI.listAgents.mockResolvedValue({
      data: { agents: [{ id: 7, name: 'Lia' }] },
    });
  });

  afterEach(() => {
    wrapper?.unmount();
    useAutonomiaCopilotStore().reset();
    vi.clearAllMocks();
  });

  it('clears the input as soon as the question enters the thread', async () => {
    let resolveChat;
    AutonomiaCopilotAPI.chat.mockReturnValue(
      new Promise(resolve => {
        resolveChat = resolve;
      })
    );
    wrapper = await mountCopilot();
    const textarea = wrapper.find('textarea');

    await send(textarea, 'Resuma a conversa');

    expect(AutonomiaCopilotAPI.chat).toHaveBeenCalledWith(
      42,
      expect.objectContaining({ agentId: 7, message: 'Resuma a conversa' })
    );
    expect(textarea.element.value).toBe('');

    resolveChat({ data: { available: true, text: 'Resumo.' } });
    await flushPromises();
    expect(useAutonomiaCopilotStore().messages).toHaveLength(2);
  });

  it('keeps the text when a reply is still loading', async () => {
    AutonomiaCopilotAPI.chat.mockReturnValue(new Promise(() => {}));
    wrapper = await mountCopilot();
    const textarea = wrapper.find('textarea');

    await send(textarea, 'Primeira');
    await send(textarea, 'Segunda');

    expect(AutonomiaCopilotAPI.chat).toHaveBeenCalledOnce();
    expect(textarea.element.value).toBe('Segunda');
  });

  it('ignores a reply that settles after the panel unmounts', async () => {
    let resolveChat;
    AutonomiaCopilotAPI.chat.mockReturnValue(
      new Promise(resolve => {
        resolveChat = resolve;
      })
    );
    wrapper = await mountCopilot();
    await send(wrapper.find('textarea'), 'Resuma a conversa');

    wrapper.unmount();
    resolveChat({ data: { available: true, text: 'Resposta tardia.' } });
    await flushPromises();

    expect(useAutonomiaCopilotStore().messages).toHaveLength(1);
  });

  it('ignores an agent list that settles after the account changes', async () => {
    let resolveAccountA;
    AutonomiaCopilotAPI.listAgents
      .mockReturnValueOnce(
        new Promise(resolve => {
          resolveAccountA = resolve;
        })
      )
      .mockResolvedValueOnce({
        data: { agents: [{ id: 8, name: 'Bia' }] },
      });

    wrapper = await mountCopilot();
    currentAccountId.value = 2;
    await nextTick();
    await flushPromises();

    resolveAccountA({ data: { agents: [{ id: 7, name: 'Lia' }] } });
    await flushPromises();

    expect(wrapper.text()).toContain('Bia');
    expect(wrapper.text()).not.toContain('Lia');
  });

  it('keeps a reply alive when the panel is closed and reopened', async () => {
    let resolveChat;
    AutonomiaCopilotAPI.chat.mockReturnValue(
      new Promise(resolve => {
        resolveChat = resolve;
      })
    );
    wrapper = await mountCopilot();
    await send(wrapper.find('textarea'), 'Resuma a conversa');

    uiSettings.value = { is_autonomia_copilot_panel_open: false };
    await nextTick();
    uiSettings.value = { is_autonomia_copilot_panel_open: true };
    await nextTick();
    await flushPromises();

    resolveChat({ data: { available: true, text: 'Resumo.' } });
    await flushPromises();

    expect(useAutonomiaCopilotStore().messages).toHaveLength(2);
    expect(wrapper.text()).not.toContain('AUTONOMIA_COPILOT.THINKING');
  });

  describe('desenho do Guia (#3191)', () => {
    it('assina com o nome do agente, nunca com o do Captain', async () => {
      AutonomiaCopilotAPI.chat.mockResolvedValue({
        data: { available: true, text: 'Resumo.' },
      });
      wrapper = await mountCopilot();

      await send(wrapper.find('textarea'), 'Resuma a conversa');

      expect(wrapper.get('h2').text()).toBe('Lia');
      expect(wrapper.text()).not.toContain('CAPTAIN.NAME');
      expect(wrapper.find('[data-resposta]').text()).toContain('Lia');
    });

    it('o campo diz a quem se pergunta e não tem clipe', async () => {
      wrapper = await mountCopilot();

      expect(wrapper.get('textarea').attributes('placeholder')).toBe(
        'AUTONOMIA_COPILOT.PLACEHOLDER'
      );
      expect(
        wrapper
          .find('button[aria-label="AUTONOMIA_GUIDE.FILE.ATTACH"]')
          .exists()
      ).toBe(false);
    });

    it('uma sugestão manda o pedido num toque', async () => {
      AutonomiaCopilotAPI.chat.mockReturnValue(new Promise(() => {}));
      wrapper = await mountCopilot();

      await wrapper.findAll('[data-sugestao]')[0].trigger('click');
      await flushPromises();

      expect(AutonomiaCopilotAPI.chat).toHaveBeenCalledWith(
        42,
        expect.objectContaining({
          message: 'AUTONOMIA_COPILOT.SUGGESTIONS.SUMMARY',
        })
      );
    });

    it('"Usar esta resposta" leva a última resposta para a caixa de resposta', async () => {
      const emit = vi.spyOn(emitter, 'emit');
      AutonomiaCopilotAPI.chat.mockResolvedValue({
        data: { available: true, text: 'Olá, Ana!', reply_suggestion: true },
      });
      wrapper = await mountCopilot();
      await send(wrapper.find('textarea'), 'Escreva uma resposta');

      const usar = wrapper.get('[data-usar-resposta]');
      expect(usar.classes()).toContain('min-h-11');
      await usar.trigger('click');

      expect(emit).toHaveBeenCalledWith(
        BUS_EVENTS.INSERT_INTO_RICH_EDITOR,
        'Olá, Ana!'
      );
      emit.mockRestore();
    });

    it('"Usar esta resposta" só na última fala, e some enquanto espera', async () => {
      let resolveSegunda;
      AutonomiaCopilotAPI.chat
        .mockResolvedValueOnce({
          data: { available: true, text: 'Olá, Ana!', reply_suggestion: true },
        })
        .mockReturnValueOnce(
          new Promise(resolve => {
            resolveSegunda = resolve;
          })
        );
      wrapper = await mountCopilot();
      await send(wrapper.find('textarea'), 'Escreva uma resposta');
      expect(wrapper.findAll('[data-usar-resposta]')).toHaveLength(1);

      await send(wrapper.find('textarea'), 'Outra, mais curta');
      expect(wrapper.findAll('[data-usar-resposta]')).toHaveLength(0);

      resolveSegunda({
        data: { available: true, text: 'Oi, Ana!', reply_suggestion: true },
      });
      await flushPromises();
      const respostas = wrapper.findAll('[data-resposta]');
      expect(wrapper.findAll('[data-usar-resposta]')).toHaveLength(1);
      expect(
        respostas[respostas.length - 1].find('[data-usar-resposta]').exists()
      ).toBe(true);
    });

    it('voltar a uma conversa não recolhe de novo o menu', async () => {
      wrapper = await mountCopilot();
      expect(menuEGuia.copilotoAberto.value).toBe(true);
      menuEGuia.copilotoAberto.value = true;
      const mudancas = [];
      const parar = watch(menuEGuia.copilotoAberto, valor =>
        mudancas.push(valor)
      );

      selectedChat.value = null;
      await nextTick();
      selectedChat.value = { id: 42 };
      await nextTick();
      await flushPromises();

      expect(mudancas).toEqual([]);
      parar();
    });

    it('sem resposta pronta para o cliente, não oferece usar', async () => {
      AutonomiaCopilotAPI.chat.mockResolvedValue({
        data: { available: true, text: 'O cliente quer desconto.' },
      });
      wrapper = await mountCopilot();
      await send(wrapper.find('textarea'), 'Resuma a conversa');

      expect(wrapper.find('[data-usar-resposta]').exists()).toBe(false);
    });

    it('aberto, avisa o menu para recolher; fechado, deixa de avisar', async () => {
      wrapper = await mountCopilot();
      expect(menuEGuia.copilotoAberto.value).toBe(true);

      wrapper.unmount();
      wrapper = null;
      expect(menuEGuia.copilotoAberto.value).toBe(false);
    });

    it('o Guia abrir fecha o copiloto sem reabrir o contato', async () => {
      wrapper = await mountCopilot();

      uiSettings.value = {
        is_autonomia_copilot_panel_open: true,
        is_autonomia_guide_panel_open: true,
      };
      await nextTick();

      expect(updateUISettings).toHaveBeenCalledWith({
        is_autonomia_copilot_panel_open: false,
      });
    });
  });
});
