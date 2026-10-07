import grapesjs from 'grapesjs';
import mjmlPlugin from 'grapesjs-mjml';
import {
  prepareMjmlForEditor,
  restoreHeldHead,
} from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/editorMjml';
import {
  mjmlEditorPlugins,
  mjmlEditorPluginsOpts,
} from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/grapesMjmlSetup';
import aiEmail from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/specs/fixtures/aiEmail.mjml?raw';
import {
  compileEmailMjml,
  disposeEmailMjmlCompiler,
} from '../compileEmailMjml';

// What the e-mail editor sends for this MJML (useEmailEditor: setMjml, then getHtml), in a real,
// non-headless editor with a canvas.
const editorHtml = mjml => {
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
  const prepared = prepareMjmlForEditor(mjml);
  editor.setComponents(prepared.mjml);
  const exported = restoreHeldHead(
    editor.runCommand('mjml-code'),
    prepared.held
  );
  const { html } = editor.runCommand('mjml-code-to-html', { mjml: exported });
  editor.destroy();
  container.remove();
  return html;
};

const IMPORTED =
  '<mjml><mj-head><mj-title>Novidades</mj-title><mj-preview>Chegou outubro</mj-preview></mj-head>' +
  '<mj-body><mj-section><mj-column>' +
  '<mj-text>Oi, tudo bem?</mj-text>' +
  '<mj-image css-class="import-missing" src="https://example.test/a.png" alt="Banner"></mj-image>' +
  '</mj-column></mj-section></mj-body></mjml>';

afterEach(async () => {
  vi.restoreAllMocks();
  await disposeEmailMjmlCompiler();
});

describe('compileEmailMjml: the editor compiler, headless', () => {
  it('gives the same HTML the e-mail editor sends', async () => {
    const html = await compileEmailMjml(aiEmail);

    expect(html.length).toBeGreaterThan(1000);
    expect(html).toEqual(editorHtml(aiEmail));
  }, 60000);

  it('keeps title, inbox preview and the import marks', async () => {
    const html = await compileEmailMjml(IMPORTED);

    expect(html).toContain('<title>Novidades</title>');
    expect(html).toContain('Chegou outubro');
    expect(html).toContain('Oi, tudo bem?');
    expect(html).toContain('import-missing');
    expect(html).toEqual(editorHtml(IMPORTED));
  }, 60000);

  it('creates one headless editor for many previews, and a new one after dispose', async () => {
    const init = vi.spyOn(grapesjs, 'init');

    const [first, second] = await Promise.all([
      compileEmailMjml(IMPORTED),
      compileEmailMjml(aiEmail),
    ]);
    expect(init).toHaveBeenCalledTimes(1);
    expect(init.mock.calls[0][0]).toMatchObject({ headless: true });
    expect(first).toContain('Oi, tudo bem?');
    expect(second).not.toContain('Oi, tudo bem?');

    const editor = init.mock.results[0].value;
    const destroy = vi.spyOn(editor, 'destroy');
    await disposeEmailMjmlCompiler();
    expect(destroy).toHaveBeenCalledTimes(1);

    await compileEmailMjml(IMPORTED);
    expect(init).toHaveBeenCalledTimes(2);
  }, 60000);

  it('gives no preview, without throwing, when the compiler cannot load, and tries again later', async () => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    const init = vi.spyOn(grapesjs, 'init').mockImplementationOnce(() => {
      throw new Error('no canvas');
    });

    expect(await compileEmailMjml(IMPORTED)).toBe('');
    expect(await compileEmailMjml(IMPORTED)).toContain('Oi, tudo bem?');
    expect(init).toHaveBeenCalledTimes(2);
  }, 60000);

  it('gives no preview for an empty design', async () => {
    expect(await compileEmailMjml('')).toBe('');
    expect(await compileEmailMjml('   ')).toBe('');
    expect(await compileEmailMjml(null)).toBe('');
  });
});
