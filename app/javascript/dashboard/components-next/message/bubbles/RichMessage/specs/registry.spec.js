import { richMessageBubbleFor } from '../registry.js';
import LinkButton from '../types/LinkButton.vue';

describe('richMessageBubbleFor', () => {
  it('acha a bolha pelo nome do tipo', () => {
    expect(richMessageBubbleFor({ richMessage: { type: 'link_button' } })).toBe(
      LinkButton
    );
  });

  it('devolve null quando a mensagem não tem formato rico', () => {
    expect(richMessageBubbleFor({})).toBeNull();
    expect(richMessageBubbleFor(undefined)).toBeNull();
    expect(richMessageBubbleFor({ richMessage: {} })).toBeNull();
  });

  it('devolve null para tipo que ainda não tem bolha', () => {
    expect(
      richMessageBubbleFor({ richMessage: { type: 'tipo_do_futuro' } })
    ).toBeNull();
  });

  it('devolve null para tipo que não é texto ou que é nome interno de objeto', () => {
    ['constructor', '__proto__', 'toString', '', 7, null, {}, ['link_button']]
      .map(type => richMessageBubbleFor({ richMessage: { type } }))
      .forEach(bubble => expect(bubble).toBeNull());
  });
});
