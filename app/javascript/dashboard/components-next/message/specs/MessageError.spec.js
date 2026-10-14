import { defineComponent, ref } from 'vue';
import { config, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import MessageError from '../MessageError.vue';
import chatlist from 'dashboard/i18n/locale/pt_BR/chatlist.json';
import richMessage from 'dashboard/i18n/locale/pt_BR/richMessage.json';
import { provideMessageContext } from '../provider.js';
import { MESSAGE_STATUS, ORIENTATION } from '../constants';

const AGORA = Math.floor(Date.now() / 1000);
const DOIS_DIAS = 2 * 24 * 60 * 60;
const MOTIVO =
  'Fora da janela de 24 horas: o cliente não escreve há mais de um dia.';

// Troca o i18n vazio do setup global pelos catálogos de verdade.
const i18n = createI18n({
  legacy: false,
  locale: 'pt_BR',
  messages: { pt_BR: { ...chatlist, ...richMessage } },
});
config.global.plugins = [i18n];

const MOTIVO_SEM_ESPACO = `https://graph.exemplo.com/v21.0/${'a1b2c3d4e5'.repeat(9)}`;

const mountError = (context = {}, error = MOTIVO) => {
  const onRetry = vi.fn();
  const TestHost = defineComponent({
    components: { MessageError },
    setup() {
      provideMessageContext({
        orientation: ref(ORIENTATION.RIGHT),
        status: ref(MESSAGE_STATUS.FAILED),
        createdAt: ref(AGORA),
        content: ref('Temos estes horários livres.'),
        attachments: ref([]),
        ...context,
      });
      return { onRetry, error };
    },
    template: '<MessageError :error="error" @retry="onRetry" />',
  });

  const wrapper = mount(TestHost);

  return { wrapper, onRetry };
};

describe('motivo da falha na conversa', () => {
  it('escreve o motivo embaixo da mensagem, sem depender de passar o mouse', () => {
    const { wrapper } = mountError();
    const reason = wrapper
      .findAll('span')
      .find(node => node.text() === `Falha ao enviar. ${MOTIVO}`);

    expect(reason.exists()).toBe(true);
    expect(wrapper.html()).not.toContain('group-hover');
    expect(wrapper.html()).not.toContain('invisible');
  });

  it('quebra em qualquer ponto o motivo com trecho longo sem espaço', () => {
    const { wrapper } = mountError({}, MOTIVO_SEM_ESPACO);
    const reason = wrapper
      .findAll('span')
      .find(node => node.text() === `Falha ao enviar. ${MOTIVO_SEM_ESPACO}`);

    expect(reason.classes()).toContain('[overflow-wrap:anywhere]');
    expect(reason.classes()).toContain('min-w-0');
  });

  it('a pontuação do título vem do catálogo do fork', () => {
    const original = i18n.global.getLocaleMessage('pt_BR');
    i18n.global.setLocaleMessage('pt_BR', {
      ...original,
      RICH_MESSAGE: {
        ...original.RICH_MESSAGE,
        FAILURE: { ...original.RICH_MESSAGE.FAILURE, TITLE: '{title} —' },
      },
    });

    const { wrapper } = mountError();
    i18n.global.setLocaleMessage('pt_BR', original);

    expect(wrapper.text()).toContain(`Falha ao enviar — ${MOTIVO}`);
    expect(richMessage.RICH_MESSAGE.FAILURE.TITLE).toBe('{title}.');
  });

  it('tem o botão Enviar de novo com rótulo e alvo de toque de 44 px', async () => {
    const { wrapper, onRetry } = mountError();
    const button = wrapper.get('button');

    expect(button.text()).toBe('Enviar de novo');
    expect(button.classes()).toContain('min-h-11');
    expect(button.attributes('disabled')).toBeUndefined();

    await button.trigger('click');
    expect(onRetry).toHaveBeenCalledTimes(1);
  });

  it('trava o botão enquanto a mensagem não está como falha (reenvio em andamento)', async () => {
    const { wrapper, onRetry } = mountError({
      status: ref(MESSAGE_STATUS.PROGRESS),
    });
    const button = wrapper.get('button');

    expect(button.attributes('disabled')).toBeDefined();
    await button.trigger('click');
    expect(onRetry).not.toHaveBeenCalled();
  });

  it('depois de um dia mostra o motivo, sem o botão', () => {
    const { wrapper } = mountError({ createdAt: ref(AGORA - DOIS_DIAS) });

    expect(wrapper.text()).toContain(MOTIVO);
    expect(wrapper.find('button').exists()).toBe(false);
  });

  it('sem texto e sem anexo mostra o motivo, sem o botão', () => {
    const { wrapper } = mountError({ content: ref(null) });

    expect(wrapper.text()).toContain(MOTIVO);
    expect(wrapper.find('button').exists()).toBe(false);
  });

  it('só com anexo ainda dá para enviar de novo', () => {
    const { wrapper } = mountError({
      content: ref(null),
      attachments: ref([{ id: 1, fileType: 'image' }]),
    });

    expect(wrapper.find('button').exists()).toBe(true);
  });

  it('acompanha o lado da mensagem', () => {
    const right = mountError().wrapper;
    const left = mountError({ orientation: ref(ORIENTATION.LEFT) }).wrapper;

    expect(right.get('div').classes()).toContain('items-end');
    expect(left.get('div').classes()).toContain('items-start');
  });
});
