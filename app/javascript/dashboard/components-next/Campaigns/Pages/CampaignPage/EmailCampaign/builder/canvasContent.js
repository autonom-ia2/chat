// Whether the e-mail on the canvas already has content of its own (#1095): then the AI button adjusts it
// ("Ajustar com IA"); otherwise it creates one ("Criar com IA"). Content is any block besides the locked
// footer with an image, a button or social links, or with text other than the starter greeting — whatever
// it came from (AI, library, saved models or built by hand). DOM parsing and string methods — no regex.
import { STARTER_MJML } from './starterMjml';

const FOOTER = '[css-class~="footer-locked"]';
const RICH_CONTENT = 'mj-image, mj-button, mj-social';

const ownBlocks = mjml => {
  const doc = new DOMParser().parseFromString(mjml || '', 'text/html');
  const body = doc.querySelector('mj-body');
  if (!body) return [];
  return [...body.children].filter(
    block => !block.matches(FOOTER) && !block.querySelector(FOOTER)
  );
};

const compactText = blocks =>
  blocks
    .map(block => block.textContent)
    .join('')
    .split('')
    .filter(character => character.trim())
    .join('');

const STARTER_TEXT = compactText(ownBlocks(STARTER_MJML));

export const hasEmailContent = mjml => {
  const blocks = ownBlocks(mjml);
  if (blocks.some(block => block.querySelector(RICH_CONTENT))) return true;
  const text = compactText(blocks);
  return text !== '' && text !== STARTER_TEXT;
};

export default hasEmailContent;
