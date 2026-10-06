import grapesjs from 'grapesjs';
import mjmlPlugin from 'grapesjs-mjml';
import { prepareMjmlForEditor } from '../editorMjml';
import { mjmlEditorPlugins, mjmlEditorPluginsOpts } from '../grapesMjmlSetup';
import aiEmail from './fixtures/aiEmail.mjml?raw';

// The canvas compiles each block from getMjmlAttributes(); the sent e-mail compiles the exported
// MJML. Both must decide the same paddings (#1081).
const loadEditor = mjml => {
  const container = document.createElement('div');
  document.body.appendChild(container);
  const editor = grapesjs.init({
    container,
    fromElement: false,
    storageManager: false,
    panels: { defaults: [] },
    plugins: mjmlEditorPlugins(mjmlPlugin),
    pluginsOpts: mjmlEditorPluginsOpts(mjmlPlugin),
  });
  editor.setComponents(mjml);
  return {
    editor,
    done: () => {
      editor.destroy();
      container.remove();
    },
  };
};

const ENDING_TYPES = ['mj-text', 'mj-button'];

// The MJML the canvas renders: each component with the attributes its view compiles.
const canvasMjml = component => {
  // Text nodes and head-only types (mj-head) are not compiled by a canvas view.
  if (!component.getMjmlAttributes) return '';
  const type = component.get('type');
  const tag = component.get('tagName');
  const attrs = Object.entries(component.getMjmlAttributes())
    .filter(([, value]) => value !== undefined && value !== '')
    .map(([name, value]) => ` ${name}="${value}"`)
    .join('');
  const inner = ENDING_TYPES.includes(type)
    ? component.getInnerHTML()
    : component
        .components()
        .map(child => canvasMjml(child))
        .join('');
  return `<${tag}${attrs}>${inner}</${tag}>`;
};

const SIDES = ['paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft'];

const paddingsOf = html => {
  const doc = new DOMParser().parseFromString(html, 'text/html');
  return [...doc.body.querySelectorAll('[style]')]
    .filter(el => el.getAttribute('style').includes('padding'))
    .map(el => [el.tagName, ...SIDES.map(side => el.style[side])].join(' '));
};

const findType = (component, type) => {
  if (component.get('type') === type) return component;
  return component
    .components()
    .map(child => findType(child, type))
    .find(Boolean);
};

describe('grapesjs-mjml setup: canvas = sent e-mail', () => {
  it('keeps the padding shorthand alone: no per-side defaults injected', () => {
    const { editor, done } = loadEditor(
      '<mjml><mj-body><mj-section padding="0"><mj-column><mj-text padding="0">Oi</mj-text>' +
        '</mj-column></mj-section></mj-body></mjml>'
    );
    const root = editor.getWrapper().components().at(0);
    const section = findType(root, 'mj-section').getMjmlAttributes();
    const text = findType(root, 'mj-text').getMjmlAttributes();
    const exported = editor.runCommand('mjml-code');
    done();

    expect(section.padding).toBe('0');
    expect(text.padding).toBe('0');
    expect(Object.keys(section).filter(k => k.startsWith('padding-'))).toEqual(
      []
    );
    expect(Object.keys(text).filter(k => k.startsWith('padding-'))).toEqual([]);
    expect(exported).toContain('<mj-section padding="0">');
    expect(exported).toContain('<mj-text padding="0">');
    expect(exported).not.toContain('padding-top');
  }, 30000);

  it('keeps the plugin defaults when the element has no padding of its own', () => {
    const { editor, done } = loadEditor(
      '<mjml><mj-body><mj-section><mj-column><mj-text>Oi</mj-text></mj-column></mj-section></mj-body></mjml>'
    );
    const text = findType(
      editor.getWrapper().components().at(0),
      'mj-text'
    ).getMjmlAttributes();
    done();

    expect(text['padding-left']).toBe('25px');
  }, 30000);

  it('adds no canvas-only padding to columns', () => {
    const { editor, done } = loadEditor('<mjml><mj-body></mj-body></mjml>');
    const columnView = editor.Components.getType('mj-column').view;
    done();

    expect(columnView.prototype.attributes.style).toBe('');
  }, 30000);

  it('compiles the AI fixture with the same paddings in the canvas and in the sent HTML', () => {
    const { editor, done } = loadEditor(prepareMjmlForEditor(aiEmail).mjml);
    const root = editor.getWrapper().components().at(0);
    const compile = mjml =>
      String(editor.runCommand('mjml-code-to-html', { mjml }).html);
    const canvas = paddingsOf(compile(canvasMjml(root)));
    const sent = paddingsOf(compile(editor.runCommand('mjml-code')));
    done();

    expect(canvas.length).toBeGreaterThan(40);
    expect(canvas).toEqual(sent);
  }, 60000);
});
