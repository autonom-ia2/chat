import { richMessageBubbleFor } from '../registry.js';
import LinkButton from '../types/LinkButton.vue';
import { MESSAGE_TYPES } from '../../../constants';

const message = (type, extra = {}) => ({
  messageType: MESSAGE_TYPES.OUTGOING,
  private: false,
  contentAttributes: { richMessage: { type } },
  ...extra,
});

describe('richMessageBubbleFor', () => {
  it('acha a bolha pelo nome do tipo', () => {
    expect(richMessageBubbleFor(message('link_button'))).toBe(LinkButton);
  });

  it('vale para mensagem de modelo, que também vai ao canal', () => {
    expect(
      richMessageBubbleFor(
        message('link_button', { messageType: MESSAGE_TYPES.TEMPLATE })
      )
    ).toBe(LinkButton);
  });

  it('devolve null para nota privada: ninguém recebeu o botão', () => {
    expect(
      richMessageBubbleFor(message('link_button', { private: true }))
    ).toBeNull();
  });

  it.each([MESSAGE_TYPES.INCOMING, MESSAGE_TYPES.ACTIVITY])(
    'devolve null para mensagem que não foi enviada ao cliente (tipo %s)',
    messageType => {
      expect(
        richMessageBubbleFor(message('link_button', { messageType }))
      ).toBeNull();
    }
  );

  it('devolve null quando a mensagem não tem formato rico', () => {
    const outgoing = { messageType: MESSAGE_TYPES.OUTGOING, private: false };

    expect(richMessageBubbleFor(outgoing)).toBeNull();
    expect(
      richMessageBubbleFor({ ...outgoing, contentAttributes: {} })
    ).toBeNull();
    expect(
      richMessageBubbleFor({
        ...outgoing,
        contentAttributes: { richMessage: {} },
      })
    ).toBeNull();
  });

  it('devolve null para tipo que ainda não tem bolha', () => {
    expect(richMessageBubbleFor(message('tipo_do_futuro'))).toBeNull();
  });

  it.each([
    'linkButton',
    'LinkButton',
    'Link_Button',
    'LINK_BUTTON',
    'link__button',
    '_link_button',
    'link_button_',
    ' link_button',
  ])('só aceita o tipo escrito como o envio aceita: %s não vale', type => {
    expect(richMessageBubbleFor(message(type))).toBeNull();
  });

  it('devolve null para tipo que não é texto ou que é nome interno de objeto', () => {
    ['constructor', '__proto__', 'toString', '', 7, null, {}, ['link_button']]
      .map(type => richMessageBubbleFor(message(type)))
      .forEach(bubble => expect(bubble).toBeNull());
  });
});
