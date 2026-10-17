import { computed, defineComponent, ref } from 'vue';
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import Flow from '../../message/bubbles/RichMessage/types/Flow.vue';
import WhatsappFlowResponse from '../../message/bubbles/WhatsappFlowResponse.vue';
import { provideMessageContext } from '../../message/provider.js';
import {
  MESSAGE_STATUS,
  MESSAGE_TYPES,
  MESSAGE_VARIANTS,
} from '../../message/constants';
import { fornecerPele, PELES } from '../pele';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import ptBRConversa from 'dashboard/i18n/locale/pt_BR/conversaCanal.json';
import ptBRRica from 'dashboard/i18n/locale/pt_BR/richMessage.json';

const FORMULARIO = {
  type: 'flow',
  flowId: '123',
  cta: 'Fazer cotação',
  token: 'token-secreto',
  screen: 'INICIO',
  header: 'Seguro auto',
  footer: 'Leva um minuto',
  name: 'Cotação auto',
  data: { cpf: '000' },
};

const montar = (
  componente,
  { pele = PELES.WHATSAPP, contexto = {}, mensagens = [] } = {}
) => {
  const Host = defineComponent({
    components: { Componente: componente },
    setup() {
      fornecerPele(computed(() => pele));
      provideMessageContext({
        id: ref(5),
        content: ref('Preencha seus dados.'),
        status: ref(MESSAGE_STATUS.SENT),
        variant: ref(MESSAGE_VARIANTS.AGENT),
        inReplyTo: ref(null),
        contentAttributes: ref({}),
        ...contexto,
      });
    },
    template: '<Componente />',
  });
  const store = createStore({
    getters: { getSelectedChat: () => ({ id: 1, messages: mensagens }) },
  });
  const i18n = createI18n({
    legacy: false,
    locale: 'pt_BR',
    messages: { pt_BR: { ...ptBRConversa, ...ptBRRica } },
  });
  return mount(Host, {
    global: {
      plugins: [store, i18n],
      stubs: {
        BaseBubble: {
          props: ['hideMeta'],
          template: '<div data-balao><slot /></div>',
        },
        MessageMeta: { template: '<span data-hora />' },
        FormattedContent: {
          props: ['content'],
          template: '<p data-corpo>{{ content }}</p>',
        },
        Icon: { props: ['icon'], template: '<i :data-icone="icon" />' },
      },
    },
  });
};

describe('Formulário enviado com a pele do WhatsApp (#1702)', () => {
  const contexto = { contentAttributes: ref({ richMessage: FORMULARIO }) };

  it('mostra cabeçalho, corpo, rodapé e o botão verde com ícone, sem token nem dados', () => {
    const wrapper = montar(Flow, { contexto });
    expect(wrapper.find('[data-formulario-do-whatsapp]').exists()).toBe(true);
    expect(wrapper.text()).toContain('Seguro auto');
    expect(wrapper.find('[data-corpo]').text()).toBe('Preencha seus dados.');
    expect(wrapper.text()).toContain('Leva um minuto');
    const botao = wrapper.find('[data-botao-do-formulario]');
    expect(botao.text()).toContain('Fazer cotação');
    expect(botao.classes()).toContain('text-[#1A6B42]');
    expect(botao.find('[data-icone="i-ph-note-pencil"]').exists()).toBe(true);
    expect(wrapper.text()).toContain('Formulário: Cotação auto');
    expect(wrapper.html()).not.toContain('token-secreto');
    expect(wrapper.html()).not.toContain('000');
  });

  it('com falha no envio, o botão fica apagado', () => {
    const wrapper = montar(Flow, {
      contexto: { ...contexto, status: ref(MESSAGE_STATUS.FAILED) },
    });
    const botao = wrapper.find('[data-botao-do-formulario]');
    expect(botao.attributes('aria-disabled')).toBe('true');
    expect(botao.classes()).not.toContain('text-[#1A6B42]');
  });

  it('quando o cliente respondeu, "Respondido" leva à resposta', async () => {
    const ouvir = vi.fn();
    emitter.on(BUS_EVENTS.SCROLL_TO_MESSAGE, ouvir);
    const wrapper = montar(Flow, {
      contexto,
      mensagens: [
        {
          id: 9,
          message_type: MESSAGE_TYPES.INCOMING,
          content_attributes: {
            in_reply_to: 5,
            whatsapp_flow_response: { name: 'flow' },
          },
        },
      ],
    });
    await wrapper.find('[data-ir-para-resposta]').trigger('click');
    expect(ouvir).toHaveBeenCalledWith({ messageId: 9 });
    emitter.off(BUS_EVENTS.SCROLL_TO_MESSAGE, ouvir);
  });

  it('sem resposta carregada, não afirma nada', () => {
    const wrapper = montar(Flow, { contexto });
    expect(wrapper.find('[data-ir-para-resposta]').exists()).toBe(false);
  });

  it('sem a pele, a bolha de antes', () => {
    const wrapper = montar(Flow, { contexto, pele: null });
    expect(wrapper.find('[data-formulario-do-whatsapp]').exists()).toBe(false);
    expect(wrapper.text()).toContain('Fazer cotação');
  });
});

describe('Resposta do formulário com a pele do WhatsApp (#1702)', () => {
  const resposta = responseJson => ({
    contentAttributes: ref({
      whatsappFlowResponse: { name: 'flow', body: 'Sent', responseJson },
    }),
    variant: ref(MESSAGE_VARIANTS.USER),
    inReplyTo: ref({
      id: 5,
      contentAttributes: { rich_message: { type: 'flow', name: 'Cotação' } },
    }),
  });

  it('balão "Resposta enviada" com o nome do formulário e os campos legíveis', () => {
    const wrapper = montar(WhatsappFlowResponse, {
      contexto: resposta({
        flow_token: 'token-secreto',
        screen_0_Nome_completo_0: 'Ana Souza',
        aceitou: true,
      }),
    });
    expect(wrapper.find('[data-resposta-do-formulario]').exists()).toBe(true);
    expect(wrapper.text()).toContain('Resposta enviada');
    expect(wrapper.text()).toContain('Formulário: Cotação');
    expect(wrapper.findAll('dt').map(item => item.text())).toEqual([
      'Nome completo',
      'Aceitou',
    ]);
    expect(wrapper.findAll('dd').map(item => item.text())).toEqual([
      'Ana Souza',
      'Sim',
    ]);
    expect(wrapper.html()).not.toContain('token-secreto');
  });

  it('"Ocultar resposta" fecha a lista e "Ver resposta" abre de novo', async () => {
    const wrapper = montar(WhatsappFlowResponse, {
      contexto: resposta({ destino: 'Recife' }),
    });
    const botao = wrapper.find('[data-ver-resposta]');
    expect(botao.attributes('aria-expanded')).toBe('true');
    expect(botao.text()).toBe('Ocultar resposta');
    await botao.trigger('click');
    expect(botao.attributes('aria-expanded')).toBe('false');
    expect(botao.text()).toBe('Ver resposta');
    expect(wrapper.find('dl').isVisible()).toBe(false);
  });

  it('resposta ilegível: avisa em vez de mostrar texto cru', () => {
    const wrapper = montar(WhatsappFlowResponse, {
      contexto: resposta('{quebrado'),
    });
    expect(wrapper.find('[data-resposta-ilegivel]').exists()).toBe(true);
    expect(wrapper.html()).not.toContain('{quebrado');
    expect(wrapper.find('[data-ver-resposta]').exists()).toBe(false);
  });

  it('sem a pele, a bolha de antes', () => {
    const wrapper = montar(WhatsappFlowResponse, {
      pele: null,
      contexto: resposta({ destino: 'Recife' }),
    });
    expect(wrapper.find('[data-resposta-do-formulario]').exists()).toBe(false);
    expect(wrapper.text()).toContain('Recife');
  });
});
