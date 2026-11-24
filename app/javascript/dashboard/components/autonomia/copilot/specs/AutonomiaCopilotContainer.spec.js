import { nextTick, ref, watch } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import AutonomiaCopilotAPI from 'dashboard/api/autonomiaCopilot';
import AutonomiaGuideAPI from 'dashboard/api/autonomiaGuide';
import { useAlert } from 'dashboard/composables';
import GuideComposer from 'dashboard/components/autonomia/guide/GuideComposer.vue';
import CopilotHeader from '../CopilotHeader.vue';
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
vi.mock('dashboard/api/autonomiaGuide', () => ({
  default: { enviarArquivo: vi.fn(), transcrever: vi.fn() },
}));
URL.createObjectURL = vi.fn(() => 'blob:previa');
URL.revokeObjectURL = vi.fn();

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

    it('o campo diz a quem se pergunta e tem clipe (#3198)', async () => {
      wrapper = await mountCopilot();

      expect(wrapper.get('textarea').attributes('placeholder')).toBe(
        'AUTONOMIA_COPILOT.PLACEHOLDER'
      );
      expect(
        wrapper
          .find('button[aria-label="AUTONOMIA_GUIDE.FILE.ATTACH"]')
          .exists()
      ).toBe(true);
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

  // #3198 — a equipe manda arquivo e áudio ao copiloto, como no Guia.
  describe('arquivos e voz', () => {
    const composer = () => wrapper.findComponent(GuideComposer);
    const anexar = async nome => {
      composer().vm.$emit(
        'anexar',
        new File(['x'], nome, { type: 'application/pdf' })
      );
      await flushPromises();
    };
    // Como no gravador de verdade: o composer avisa `gravando` antes de entregar o áudio, e a
    // gravação continua ligada no momento da entrega.
    const gravar = async () => {
      composer().vm.$emit('gravando', true);
      await nextTick();
      composer().props('onEnviarVoz')({
        audio: new Blob(['x'], { type: 'audio/webm' }),
        duracao: 3,
      });
      composer().vm.$emit('gravando', false);
      await flushPromises();
    };

    beforeEach(() => {
      AutonomiaCopilotAPI.chat.mockResolvedValue({
        data: { available: true, text: 'Feito.' },
      });
    });

    it('o arquivo sobe pelo Guia e vai com cada pergunta do assunto', async () => {
      AutonomiaGuideAPI.enviarArquivo.mockResolvedValue({
        data: { signed_id: 'assinado-1', nome: 'apolice.pdf' },
      });
      wrapper = await mountCopilot();

      await anexar('apolice.pdf');
      await send(wrapper.find('textarea'), 'O que diz a apólice?');
      await send(wrapper.find('textarea'), 'E a vigência?');

      expect(AutonomiaCopilotAPI.chat).toHaveBeenNthCalledWith(
        1,
        42,
        expect.objectContaining({ arquivos: ['assinado-1'] })
      );
      expect(AutonomiaCopilotAPI.chat).toHaveBeenNthCalledWith(
        2,
        42,
        expect.objectContaining({ arquivos: ['assinado-1'] })
      );
      expect(useAutonomiaCopilotStore().messages[0].anexos).toHaveLength(1);
    });

    it('só o arquivo, sem texto, vai com a frase padrão', async () => {
      AutonomiaGuideAPI.enviarArquivo.mockResolvedValue({
        data: { signed_id: 'assinado-1' },
      });
      wrapper = await mountCopilot();

      await anexar('apolice.pdf');
      composer().props('onSend')('');
      await flushPromises();

      expect(AutonomiaCopilotAPI.chat).toHaveBeenCalledWith(
        42,
        expect.objectContaining({
          message: 'AUTONOMIA_GUIDE.FILE.DEFAULT_MESSAGE',
        })
      );
    });

    it('arquivo recusado vira aviso com o motivo e não vai na pergunta', async () => {
      AutonomiaGuideAPI.enviarArquivo.mockRejectedValue({
        response: { data: { error: 'Esse tipo de arquivo não é aceito.' } },
      });
      wrapper = await mountCopilot();

      await anexar('planilha.numbers');
      await send(wrapper.find('textarea'), 'Leia');

      expect(useAlert).toHaveBeenCalledWith(
        'Esse tipo de arquivo não é aceito.'
      );
      expect(AutonomiaCopilotAPI.chat).toHaveBeenCalledWith(
        42,
        expect.objectContaining({ arquivos: [] })
      );
    });

    it('o áudio vira texto e só então o agente é chamado', async () => {
      AutonomiaGuideAPI.transcrever.mockResolvedValue({
        data: { texto: 'Qual o próximo passo?' },
      });
      wrapper = await mountCopilot();

      await gravar();

      expect(AutonomiaCopilotAPI.chat).toHaveBeenCalledWith(
        42,
        expect.objectContaining({ message: 'Qual o próximo passo?' })
      );
      const [voz] = useAutonomiaCopilotStore().messages;
      expect(voz.voz.estado).toBe('pronta');
      expect(voz.voz.texto).toBe('Qual o próximo passo?');
    });

    it('a transcrição falhou: o balão mostra o erro e nada é pedido', async () => {
      AutonomiaGuideAPI.transcrever.mockResolvedValue({ data: { texto: '' } });
      wrapper = await mountCopilot();

      await gravar();

      expect(AutonomiaCopilotAPI.chat).not.toHaveBeenCalled();
      expect(useAutonomiaCopilotStore().messages[0].voz.estado).toBe('erro');
      expect(wrapper.find('textarea').attributes('readonly')).toBeUndefined();
    });

    it('com gravação no campo, o texto espera e avisa', async () => {
      wrapper = await mountCopilot();

      composer().vm.$emit('gravando', true);
      await nextTick();
      const aceitou = composer().props('onSend')('Resuma');

      expect(aceitou).toBe(false);
      expect(AutonomiaCopilotAPI.chat).not.toHaveBeenCalled();
      expect(useAlert).toHaveBeenCalledWith(
        'AUTONOMIA_GUIDE.VOICE.FINISH_FIRST'
      );
    });

    it('trocar de agente no meio da transcrição destrava o indicador', async () => {
      let transcrever;
      AutonomiaGuideAPI.transcrever.mockReturnValue(
        new Promise(resolve => {
          transcrever = resolve;
        })
      );
      AutonomiaCopilotAPI.listAgents.mockResolvedValue({
        data: {
          agents: [
            { id: 7, name: 'Lia' },
            { id: 8, name: 'Bruno' },
          ],
        },
      });
      AutonomiaCopilotAPI.chat.mockReturnValue(new Promise(() => {}));
      wrapper = await mountCopilot();

      await gravar();
      wrapper
        .findComponent(CopilotHeader)
        .vm.$emit('trocar', { id: 8, name: 'Bruno' });
      await flushPromises();
      transcrever({ data: { texto: 'atrasado' } });
      await flushPromises();
      await send(wrapper.find('textarea'), 'Nova pergunta');

      expect(wrapper.text()).toContain('AUTONOMIA_COPILOT.THINKING');
    });

    it('"Novo assunto" esquece os arquivos', async () => {
      AutonomiaGuideAPI.enviarArquivo.mockResolvedValue({
        data: { signed_id: 'assinado-1' },
      });
      wrapper = await mountCopilot();
      await anexar('apolice.pdf');
      await send(wrapper.find('textarea'), 'Leia');

      await wrapper.get('[data-novo-assunto]').trigger('click');
      await send(wrapper.find('textarea'), 'Outra coisa');

      expect(AutonomiaCopilotAPI.chat).toHaveBeenLastCalledWith(
        42,
        expect.objectContaining({ arquivos: [] })
      );
    });
  });
});
