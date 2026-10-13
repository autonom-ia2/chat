import { montarMensagem, AGORA } from './montarMensagem';
import { MESSAGE_STATUS } from '../constants';

const LINK_BUTTON = {
  type: 'link_button',
  label: 'Escolher horário',
  url: 'https://exemplo.com.br/agendar',
};
const MOTIVO = 'O texto do botão de link passa de 20 caracteres.';

const bubbleNames = wrapper =>
  wrapper
    .findAll('[data-bubble-name]')
    .map(node => node.attributes('data-bubble-name'));

describe('Message', () => {
  describe('mensagem comum (sem formato rico e sem falha)', () => {
    it('continua na bolha de texto, sem botão de link e sem aviso de falha', () => {
      const wrapper = montarMensagem();

      expect(bubbleNames(wrapper)).toEqual(['text']);
      expect(wrapper.text()).toContain('Olá, tudo bem?');
      expect(wrapper.find('a').exists()).toBe(false);
      expect(wrapper.find('button').exists()).toBe(false);
      expect(wrapper.text()).not.toContain('CHAT_LIST.FAILED_TO_SEND');
      expect(wrapper.text()).not.toContain('RICH_MESSAGE');
    });

    it('continua escolhendo a bolha pelo anexo', () => {
      const wrapper = montarMensagem({
        content: null,
        attachments: [{ id: 1, fileType: 'image', dataUrl: 'https://x/a.png' }],
      });

      expect(bubbleNames(wrapper)).toEqual(['image']);
    });

    it('sem texto e sem anexo continua sem aparecer', () => {
      expect(montarMensagem({ content: null }).find('div').exists()).toBe(
        false
      );
    });
  });

  describe('formato rico', () => {
    it('mostra a bolha do botão de link', () => {
      const wrapper = montarMensagem({
        content: 'Você escolhe pelo site.',
        contentAttributes: { richMessage: LINK_BUTTON },
      });

      expect(bubbleNames(wrapper)).toEqual(['rich-link-button']);
      expect(wrapper.text()).toContain('Você escolhe pelo site.');
      expect(wrapper.get('a').text()).toBe('Escolher horário');
      expect(wrapper.get('a').attributes('href')).toBe(LINK_BUTTON.url);
    });

    it('tipo sem bolha cai na bolha de texto, sem erro', () => {
      const wrapper = montarMensagem({
        content: 'Mensagem de um tipo que ainda não tem bolha.',
        contentAttributes: { richMessage: { type: 'tipo_do_futuro' } },
      });

      expect(bubbleNames(wrapper)).toEqual(['text']);
      expect(wrapper.text()).toContain(
        'Mensagem de um tipo que ainda não tem bolha.'
      );
    });

    it('tipo sem bolha continua escolhendo a bolha pelo anexo', () => {
      const wrapper = montarMensagem({
        content: null,
        contentAttributes: { richMessage: { type: 'tipo_do_futuro' } },
        attachments: [{ id: 1, fileType: 'image', dataUrl: 'https://x/a.png' }],
      });

      expect(bubbleNames(wrapper)).toEqual(['image']);
    });

    it('tipo com bolha aparece mesmo sem corpo', () => {
      const wrapper = montarMensagem({
        content: null,
        contentAttributes: { richMessage: LINK_BUTTON },
      });

      expect(bubbleNames(wrapper)).toEqual(['rich-link-button']);
    });
  });

  describe('falha', () => {
    it('escreve o motivo embaixo da mensagem e reenvia pelo botão', async () => {
      const wrapper = montarMensagem({
        status: MESSAGE_STATUS.FAILED,
        contentAttributes: { externalError: MOTIVO },
      });

      expect(bubbleNames(wrapper)).toEqual(['text']);
      expect(wrapper.text()).toContain(MOTIVO);

      await wrapper.get('button').trigger('click');
      expect(wrapper.emitted('retry')).toHaveLength(1);
    });

    it('vale também para a mensagem com formato rico', () => {
      const wrapper = montarMensagem({
        status: MESSAGE_STATUS.FAILED,
        contentAttributes: { richMessage: LINK_BUTTON, externalError: MOTIVO },
      });

      expect(bubbleNames(wrapper)).toEqual(['rich-link-button']);
      expect(wrapper.text()).toContain(MOTIVO);
      expect(wrapper.find('button').exists()).toBe(true);
    });

    it('quem não pode reenviar (mais de um dia) vê o motivo, sem o botão', () => {
      const wrapper = montarMensagem({
        status: MESSAGE_STATUS.FAILED,
        createdAt: AGORA - 2 * 24 * 60 * 60,
        contentAttributes: { externalError: MOTIVO },
      });

      expect(wrapper.text()).toContain(MOTIVO);
      expect(wrapper.find('button').exists()).toBe(false);
    });

    it('falha sem motivo gravado segue como antes: bolha de erro, sem linha de motivo', () => {
      const wrapper = montarMensagem({ status: MESSAGE_STATUS.FAILED });

      expect(bubbleNames(wrapper)).toEqual(['text']);
      expect(wrapper.get('[data-bubble-name]').classes()).toContain(
        'bg-n-ruby-4'
      );
      expect(wrapper.find('button').exists()).toBe(false);
      expect(wrapper.text()).not.toContain('CHAT_LIST.FAILED_TO_SEND');
    });
  });
});
