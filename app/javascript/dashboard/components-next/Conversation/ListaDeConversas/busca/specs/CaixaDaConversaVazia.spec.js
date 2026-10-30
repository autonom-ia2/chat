import { createStore } from 'vuex';
import { mount, enableAutoUnmount } from '@vue/test-utils';
import CaixaDaConversaVazia from '../CaixaDaConversaVazia.vue';
import { criarI18n } from '../../specs/apoio';
import conversaCanalPtBR from 'dashboard/i18n/locale/pt_BR/conversaCanal.json';

// #2211 (rodada 5) — a caixa da conversa vazia é a caixa de resposta de verdade, montada com
// as mesmas peças do ReplyBox: só "Responder" no topo, o editor e a barra de baixo. WhatsApp
// oficial pede o modelo no lugar da caixa; e-mail usa a caixa do e-mail novo, com o assunto.
const teclas = vi.hoisted(() => ({ atual: {} }));
vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: eventos => {
    teclas.atual = eventos;
  },
}));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    isEditorHotKeyEnabled: tecla => tecla === 'cmd_enter',
  }),
}));
vi.mock(
  'dashboard/components-next/conversa-canal/usePeleDaResposta',
  async () => {
    const { ref } = await import('vue');
    return {
      usePeleDaResposta: () => ({
        classesDaResposta: ref({ caixa: 'pele-caixa', campo: 'pele-campo' }),
        textoDoCampo: ref('Digite uma mensagem'),
      }),
    };
  }
);
vi.mock('dashboard/components/widgets/WootWriter/ReplyTopPanel.vue', () => ({
  default: {
    props: { soResposta: Boolean },
    template: '<div data-topo-falso :data-so-resposta="soResposta" />',
  },
}));
vi.mock('dashboard/components/widgets/WootWriter/ReplyBottomPanel.vue', () => ({
  default: {
    props: {
      onSend: Function,
      isSendDisabled: Boolean,
      semConversa: Boolean,
      showFileUpload: Boolean,
      showAudioRecorder: Boolean,
      inbox: Object,
    },
    template:
      '<button data-barra-falsa :disabled="isSendDisabled" :data-sem-conversa="semConversa" :data-arquivo="showFileUpload" :data-microfone="showAudioRecorder" @click="onSend()" />',
  },
}));
vi.mock('dashboard/components/widgets/WootWriter/Editor.vue', () => ({
  default: {
    props: ['placeholder'],
    emits: ['focus', 'blur'],
    template:
      '<div data-editor-falso :data-placeholder="placeholder" @click="$emit(\'focus\')" />',
  },
}));
vi.mock(
  'dashboard/components-next/NovaConversa/NovaConversaCaixaDoEmail.vue',
  () => ({
    default: {
      props: { comAssunto: Boolean, para: Object },
      template:
        '<div data-email-falso :data-com-assunto="comAssunto" :data-para="para?.nome" />',
    },
  })
);
vi.mock(
  'dashboard/components-next/NovaConversa/NovaConversaPronta.vue',
  () => ({
    default: {
      template: '<div data-pronta-falsa />',
      methods: { montar: () => null },
    },
  })
);
vi.mock(
  'dashboard/components-next/NewConversation/components/ContentTemplateSelector.vue',
  () => ({ default: { template: '<div />' } })
);

enableAutoUnmount(afterEach);

const montar = props => {
  const store = createStore({
    getters: {
      'inboxes/getConversationWhatsAppTemplates': () => () => [],
    },
  });
  return mount(CaixaDaConversaVazia, {
    props: { canal: { id: 1, name: 'Caixa' }, tipo: 'texto', ...props },
    global: {
      plugins: [criarI18n(conversaCanalPtBR), store],
      stubs: { NextButton: false },
    },
  });
};

describe('CaixaDaConversaVazia', () => {
  it('WhatsApp oficial: "Escolher o modelo" no lugar da caixa, com a linha que explica', async () => {
    const wrapper = montar({ tipo: 'whatsapp_pronta', comModelo: true });
    expect(wrapper.find('[data-linha-do-modelo]').text()).toBe(
      'No WhatsApp oficial, a primeira mensagem é um modelo já aprovado. Depois que a pessoa responder, você escreve à vontade.'
    );
    expect(wrapper.find('[data-caixa-de-resposta]').exists()).toBe(false);
    await wrapper.find('[data-escolher-modelo]').trigger('click');
    expect(
      wrapper.find('[data-painel-do-modelo] [data-pronta-falsa]').exists()
    ).toBe(true);
  });

  it('e-mail: a caixa do e-mail novo com o assunto, e "Enviar para" a pessoa', async () => {
    const wrapper = montar({
      tipo: 'email',
      para: { nome: 'Conceição Alves', email: 'c@x.test' },
      podeEnviar: true,
    });
    const caixa = wrapper.find('[data-email-falso]');
    expect(caixa.attributes('data-com-assunto')).toBe('true');
    expect(caixa.attributes('data-para')).toBe('Conceição Alves');
    const enviar = wrapper.find('[data-enviar]');
    expect(enviar.text()).toContain('Conceição Alves');
    await enviar.trigger('click');
    expect(wrapper.emitted('enviar')).toHaveLength(1);
  });

  it('texto: a caixa de resposta de verdade — só "Responder", o campo da pele e a barra sem conversa', async () => {
    const wrapper = montar({ podeEnviar: false });
    const caixa = wrapper.find('[data-caixa-de-resposta]');
    expect(caixa.classes()).toContain('pele-caixa');
    expect(
      wrapper.find('[data-topo-falso]').attributes('data-so-resposta')
    ).toBe('true');
    expect(
      wrapper.find('[data-editor-falso]').attributes('data-placeholder')
    ).toBe('Digite uma mensagem');
    const barra = wrapper.find('[data-barra-falsa]');
    expect(barra.attributes('data-sem-conversa')).toBe('true');
    expect(barra.attributes('disabled')).toBeDefined();
    await wrapper.setProps({ podeEnviar: true });
    await barra.trigger('click');
    expect(wrapper.emitted('enviar')).toHaveLength(1);
  });

  it('Ctrl/Cmd+Enter envia só com o campo em foco', async () => {
    const wrapper = montar({ podeEnviar: true });
    teclas.atual['$mod+Enter'].action();
    expect(wrapper.emitted('enviar')).toBeUndefined();
    await wrapper.find('[data-editor-falso]').trigger('click');
    teclas.atual['$mod+Enter'].action();
    expect(wrapper.emitted('enviar')).toHaveLength(1);
  });

  it('WhatsApp: anexo e microfone; pelo número reserva (só texto), nenhum dos dois', async () => {
    const wrapper = montar({ tipo: 'whatsapp_livre', caixaDoWhatsapp: true });
    const barra = () => wrapper.find('[data-barra-falsa]');
    expect(barra().attributes('data-arquivo')).toBe('true');
    expect(barra().attributes('data-microfone')).toBe('true');
    await wrapper.setProps({ soTexto: true });
    expect(barra().attributes('data-arquivo')).toBe('false');
    expect(barra().attributes('data-microfone')).toBe('false');
  });
});
