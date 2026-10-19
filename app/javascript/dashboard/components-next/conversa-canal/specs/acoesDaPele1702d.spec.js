// Ações da pele ligadas ao contrato do Híbrido (#1702 com o #1709): enquete no "+" e
// reação pela rota da mensagem. O álbum do WAHA fica no PR do #1831b, com os testes dele.
/* eslint-disable vue/one-component-per-file */
import { defineComponent, h } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import MaisDoWhatsapp from '../mais/MaisDoWhatsapp.vue';
import JanelaDoMais from '../mais/JanelaDoMais.vue';
import PreviaDoMais from '../mais/PreviaDoMais.vue';
import {
  AVISO_DE_VARIAS,
  LIMITES,
  montarEnquete,
  textoParaQuemNaoTemFormato,
} from '../mais/montarMensagem';
import { ENQUETE, comoSaiAEnquete } from '../mais/enqueteNoMais';
import { estadoDaReacao } from '../reacaoDoAtendente';

const i18n = () =>
  createI18n({ legacy: false, locale: 'en', missingWarn: false });

describe('montarEnquete (#1702 com o #1709)', () => {
  const campos = extras => ({
    pergunta: ' Qual dia? ',
    opcoes: ['Segunda', ' Terça ', ''],
    variasRespostas: false,
    ...extras,
  });

  it('monta o rich_message poll do contrato, pergunta no content', () => {
    expect(montarEnquete(campos())).toEqual({
      pedido: {
        content: 'Qual dia?',
        richMessage: {
          type: 'poll',
          multiple: false,
          options: [
            { id: 'opcao_1', title: 'Segunda' },
            { id: 'opcao_2', title: 'Terça' },
          ],
        },
      },
    });
    expect(
      montarEnquete(campos({ variasRespostas: true })).pedido.richMessage
        .multiple
    ).toBe(true);
  });

  it('recusa na hora o que o servidor recusaria (limites do motor)', () => {
    const erro = extras => montarEnquete(campos(extras)).erros;
    expect(erro({ pergunta: '  ' })).toEqual({ pergunta: 'pergunta' });
    expect(erro({ pergunta: 'x'.repeat(256) })).toEqual({
      pergunta: 'perguntaLonga',
    });
    expect(erro({ opcoes: ['Só uma'] })).toEqual({ opcoes: 'opcoes' });
    expect(
      erro({ opcoes: Array.from({ length: 13 }, (_, i) => `O${i}`) })
    ).toEqual({ opcoes: 'opcoesDaEnqueteDemais' });
    expect(erro({ opcoes: ['a', 'b'.repeat(101)] })).toEqual({
      opcoes: 'opcaoDaEnqueteLonga',
    });
    expect(erro({ opcoes: ['Sim', ' Sim'] })).toEqual({
      opcoes: 'opcoesRepetidas',
    });
  });

  it('em texto: a pergunta e as opções numeradas (Poll#fallback_text)', () => {
    const { pedido } = montarEnquete(campos());
    expect(textoParaQuemNaoTemFormato(pedido)).toBe(
      'Qual dia?\n\n1. Segunda\n2. Terça'
    );
  });

  it('em texto com mais de uma resposta: a linha do servidor no fim', () => {
    const { pedido } = montarEnquete(campos({ variasRespostas: true }));
    expect(AVISO_DE_VARIAS).toBe('Pode escolher mais de uma');
    expect(textoParaQuemNaoTemFormato(pedido)).toBe(
      'Qual dia?\n\n1. Segunda\n2. Terça\nPode escolher mais de uma'
    );
  });
});

describe('comoSaiAEnquete', () => {
  it('sem a flag não há enquete', () => {
    expect(
      comoSaiAEnquete({
        flagLigada: false,
        conversa: { whatsapp_api_rich_native: ['poll'] },
      })
    ).toBeNull();
  });

  it('nativa quando a conversa lista poll; senão, texto', () => {
    expect(
      comoSaiAEnquete({
        flagLigada: true,
        conversa: { whatsapp_api_rich_native: ['location', 'poll'] },
      })
    ).toBe(ENQUETE.NATIVA);
    expect(comoSaiAEnquete({ flagLigada: true, conversa: {} })).toBe(
      ENQUETE.TEXTO
    );
  });
});

describe('MaisDoWhatsapp: item Enquete', () => {
  const CLOUD = {
    id: 1,
    channel_type: 'Channel::Whatsapp',
    provider: 'whatsapp_cloud',
  };
  const montar = ({ flag, conversa = {} }) => {
    const store = createStore({
      getters: {
        getSelectedChat: () => conversa,
        getCurrentAccountId: () => 3,
        'accounts/isFeatureEnabledonAccount': () => (conta, nome) =>
          flag && conta === 3 && nome === 'whatsapp_rich_native',
      },
    });
    return mount(MaisDoWhatsapp, {
      props: { caixa: CLOUD, enviar: vi.fn() },
      global: {
        plugins: [store, i18n()],
        stubs: { JanelaDoMais: true, Icon: true },
      },
    });
  };
  const abrir = async wrapper => {
    await wrapper.find('[data-mais-do-whatsapp]').trigger('click');
    return wrapper;
  };

  it('sem a flag o item não aparece', async () => {
    const wrapper = await abrir(montar({ flag: false }));
    expect(wrapper.find('[data-item="enquete"]').exists()).toBe(false);
  });

  it('com a flag na Cloud aparece e a janela sabe que vai em texto', async () => {
    const wrapper = await abrir(montar({ flag: true }));
    expect(wrapper.find('[data-item="enquete"]').exists()).toBe(true);
    expect(
      wrapper.findComponent({ name: 'JanelaDoMais' }).props('enqueteEmTexto')
    ).toBe(true);
  });

  it('com poll nos tipos nativos da conversa, a janela não promete texto', async () => {
    const wrapper = await abrir(
      montar({ flag: true, conversa: { whatsapp_api_rich_native: ['poll'] } })
    );
    expect(
      wrapper.findComponent({ name: 'JanelaDoMais' }).props('enqueteEmTexto')
    ).toBe(false);
  });
});

describe('PreviaDoMais: enquete', () => {
  const CAMPOS = {
    pergunta: 'Qual dia?',
    opcoes: ['Segunda', 'Terça'],
    variasRespostas: false,
  };
  const montar = (viraTexto, campos = CAMPOS) =>
    mount(PreviaDoMais, {
      props: { tipo: 'enquete', campos, viraTexto },
      global: { plugins: [i18n()], stubs: { Icon: true } },
    });

  it('em texto, enquete que ainda não passa: diz o que falta', () => {
    const wrapper = montar(true, { ...CAMPOS, opcoes: ['Segunda', ''] });
    const vazia = wrapper.find('[data-previa-vazia]');
    expect(vazia.text()).toBe('CONVERSA_CANAL.PREVIA.ENQUETE_INCOMPLETA');
    expect(wrapper.text()).not.toContain('Qual dia?');
    expect(wrapper.text()).not.toContain('1. Segunda');
  });

  it('em texto com mais de uma resposta: mostra a linha do aviso', () => {
    const wrapper = montar(true, { ...CAMPOS, variasRespostas: true });
    expect(wrapper.find('[data-previa-vazia]').exists()).toBe(false);
    expect(wrapper.text()).toContain('Pode escolher mais de uma');
  });

  it('nativa: pergunta e opções para votar', () => {
    const wrapper = montar(false);
    const previa = wrapper.find('[data-previa-enquete]');
    expect(previa.text()).toContain('Qual dia?');
    expect(previa.findAll('li').map(li => li.text())).toEqual([
      'Segunda',
      'Terça',
    ]);
  });

  it('em texto: avisa e mostra a versão numerada', () => {
    const wrapper = montar(true);
    expect(wrapper.find('[data-previa-enquete]').exists()).toBe(false);
    expect(wrapper.text()).toContain(
      'CONVERSA_CANAL.PREVIA.ENQUETE_VIRA_TEXTO'
    );
    expect(wrapper.text()).toContain('1. Segunda');
    expect(wrapper.text()).toContain('2. Terça');
  });
});

describe('JanelaDoMais: enquete', () => {
  // O Dialog de verdade usa <dialog>; aqui ele só mostra o conteúdo, a descrição
  // (ajuda) e o botão que confirma.
  const DialogFalso = defineComponent({
    name: 'DialogFalso',
    props: { description: { type: String, default: '' } },
    emits: ['confirm', 'close'],
    setup(props, { emit, expose, slots }) {
      expose({ open: () => {}, close: () => emit('close') });
      return () =>
        h('div', { 'data-ajuda': props.description }, [
          slots.default?.(),
          h('button', { 'data-confirmar': '', onClick: () => emit('confirm') }),
        ]);
    },
  });
  const campoFalso = tag =>
    defineComponent({
      props: { modelValue: { type: String, default: '' } },
      emits: ['update:modelValue'],
      setup(props, { emit }) {
        return () =>
          h(tag, {
            value: props.modelValue,
            'data-campo': '',
            onInput: evento => emit('update:modelValue', evento.target.value),
          });
      },
    });
  const BotaoFalso = defineComponent({
    props: { label: { type: String, default: '' } },
    setup(props, { attrs }) {
      return () =>
        h('button', { ...attrs, 'data-botao': props.label }, props.label);
    },
  });

  const montar = ({ enqueteEmTexto = false, enviar = vi.fn() } = {}) => {
    const wrapper = mount(JanelaDoMais, {
      props: { enqueteEmTexto, enviar },
      global: {
        plugins: [i18n()],
        stubs: {
          Dialog: DialogFalso,
          Input: campoFalso('input'),
          TextArea: campoFalso('textarea'),
          Button: BotaoFalso,
          Checkbox: true,
          PreviaDoMais: true,
          CampoDeBusca: true,
          CampoDeTelefone: true,
          ChoiceSelect: true,
        },
      },
    });
    return { wrapper, enviar };
  };
  const abrirEnquete = async wrapper => {
    wrapper.vm.abrir('enquete');
    await flushPromises();
  };
  const MAIS_UMA = '[data-botao="CONVERSA_CANAL.JANELA.ENQUETE.MAIS_UMA"]';

  it('chega a 12 opções e o "Mais uma opção" some', async () => {
    const { wrapper } = montar();
    await abrirEnquete(wrapper);
    // A janela abre com 3 opções (a pergunta é o textarea).
    expect(wrapper.findAll('input[data-campo]')).toHaveLength(3);
    while (wrapper.find(MAIS_UMA).exists()) {
      // eslint-disable-next-line no-await-in-loop
      await wrapper.find(MAIS_UMA).trigger('click');
    }
    expect(wrapper.findAll('input[data-campo]')).toHaveLength(
      LIMITES.opcoesDaEnquete
    );
    expect(LIMITES.opcoesDaEnquete).toBe(12);
  });

  it('a ajuda diz que vai em texto quando a conversa não tem enquete', async () => {
    const emTexto = montar({ enqueteEmTexto: true }).wrapper;
    await abrirEnquete(emTexto);
    expect(emTexto.find('[data-ajuda]').attributes('data-ajuda')).toBe(
      'CONVERSA_CANAL.JANELA.ENQUETE.AJUDA_TEXTO'
    );
    const nativa = montar({ enqueteEmTexto: false }).wrapper;
    await abrirEnquete(nativa);
    expect(nativa.find('[data-ajuda]').attributes('data-ajuda')).toBe(
      'CONVERSA_CANAL.JANELA.ENQUETE.AJUDA'
    );
  });

  it('enviar manda o rich_message poll com a pergunta e as opções', async () => {
    const enviar = vi.fn().mockResolvedValue({});
    const { wrapper } = montar({ enviar });
    await abrirEnquete(wrapper);
    await wrapper.find('textarea[data-campo]').setValue('Qual dia?');
    const opcoes = wrapper.findAll('input[data-campo]');
    await opcoes[0].setValue('Segunda');
    await opcoes[1].setValue('Terça');
    await wrapper.find('[data-confirmar]').trigger('click');
    await flushPromises();
    expect(enviar).toHaveBeenCalledTimes(1);
    const [pedido] = enviar.mock.calls[0];
    expect(pedido.content).toBe('Qual dia?');
    expect(pedido.richMessage.type).toBe('poll');
    expect(pedido.richMessage.options.map(opcao => opcao.title)).toEqual([
      'Segunda',
      'Terça',
    ]);
  });

  it('enquete incompleta não chama enviar', async () => {
    const { wrapper, enviar } = montar();
    await abrirEnquete(wrapper);
    await wrapper.find('[data-confirmar]').trigger('click');
    await flushPromises();
    expect(enviar).not.toHaveBeenCalled();
  });
});

describe('estadoDaReacao com as ações do motor (#1709)', () => {
  const WAHA = { channel_type: 'Channel::Api', waha_provider: 'waha' };
  const conversa = { whatsapp_api_message_actions: ['react', 'edit'] };
  const mensagem = extras => ({
    messageType: 0,
    isPrivate: false,
    status: 'sent',
    sourceId: null,
    contentAttributes: {},
    ...extras,
  });

  it('com react: reage sem sourceId, recebida ou enviada, pela caixa', () => {
    expect(
      estadoDaReacao({ caixa: WAHA, conversa, mensagem: mensagem() })
    ).toEqual({ visivel: true, bloqueado: false, pelaCaixa: true });
    expect(
      estadoDaReacao({
        caixa: WAHA,
        conversa,
        mensagem: mensagem({ messageType: 1 }),
      }).visivel
    ).toBe(true);
  });

  it('com react: falhada, com erro, nota, apagada e aviso de visualização única não reagem', () => {
    const casos = [
      mensagem({ status: 'failed' }),
      mensagem({ contentAttributes: { externalError: 'x' } }),
      mensagem({ isPrivate: true }),
      mensagem({ contentAttributes: { deleted: true } }),
      mensagem({ status: 'progress' }),
      mensagem({ contentAttributes: { viewOnceUnavailable: true } }),
      mensagem({ messageType: 2 }),
    ];
    casos.forEach(caso =>
      expect(
        estadoDaReacao({ caixa: WAHA, conversa, mensagem: caso }).visivel
      ).toBe(false)
    );
  });

  it('id provisório do WAHA (waha-native-pending-…) não reage, por nenhum caminho', () => {
    const pendente = mensagem({ sourceId: 'waha-native-pending-abc123' });
    expect(
      estadoDaReacao({ caixa: WAHA, conversa, mensagem: pendente }).visivel
    ).toBe(false);
    const HIBRIDA = {
      channel_type: 'Channel::Whatsapp',
      provider: 'whatsapp_cloud',
    };
    expect(
      estadoDaReacao({
        caixa: HIBRIDA,
        conversa: { can_reply: true },
        mensagem: pendente,
      }).visivel
    ).toBe(false);
    // O id definitivo, com o mesmo trecho no meio, reage.
    expect(
      estadoDaReacao({
        caixa: WAHA,
        conversa,
        mensagem: mensagem({ sourceId: 'true_x@c.us_waha-native-pending-1' }),
      }).visivel
    ).toBe(true);
  });

  it('sem react nas ações: a regra de antes (WAHA exige sourceId)', () => {
    const estado = estadoDaReacao({
      caixa: WAHA,
      conversa: {},
      mensagem: mensagem(),
    });
    expect(estado.visivel).toBe(false);
    expect(
      estadoDaReacao({
        caixa: WAHA,
        conversa: {},
        mensagem: mensagem({ sourceId: 'true_x@c.us_1' }),
      }).pelaCaixa
    ).toBeUndefined();
  });
});
