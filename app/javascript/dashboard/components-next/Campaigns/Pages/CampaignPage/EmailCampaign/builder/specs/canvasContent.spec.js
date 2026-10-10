import { hasEmailContent } from '../canvasContent';
import { STARTER_MJML } from '../starterMjml';
import { LOCKED_FOOTER_MJML } from '../lockedFooter';

const email = blocks =>
  `<mjml><mj-body>${blocks}${LOCKED_FOOTER_MJML}</mj-body></mjml>`;
const text = body =>
  `<mj-section><mj-column><mj-text>${body}</mj-text></mj-column></mj-section>`;

// #1095: "Criar com IA" on an empty editor, "Ajustar com IA" once the e-mail has content of its own.
describe('hasEmailContent', () => {
  it.each([
    ['nothing', ''],
    ['an empty body', '<mjml><mj-body></mj-body></mjml>'],
    ['only the locked footer', email('')],
    ['the starter e-mail', STARTER_MJML],
    ['an empty section', email(text(''))],
  ])('is empty with %s', (_, mjml) => {
    expect(hasEmailContent(mjml)).toBe(false);
  });

  it.each([
    ['text written by hand', email(text('Promoção de outubro'))],
    [
      'an image from the library',
      email(
        '<mj-section><mj-column><mj-image src="https://x.com/a.png"></mj-image></mj-column></mj-section>'
      ),
    ],
    [
      'a button',
      email(
        '<mj-section><mj-column><mj-button href="https://x.com">Comprar</mj-button></mj-column></mj-section>'
      ),
    ],
    [
      'the starter greeting plus more text',
      email(text('Olá {{ nome }}, temos novidades')),
    ],
  ])('has content with %s', (_, mjml) => {
    expect(hasEmailContent(mjml)).toBe(true);
  });
});
