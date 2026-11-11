import grapesjs from 'grapesjs';
import mjmlPlugin from 'grapesjs-mjml';
import EmailCampaignAssetsAPI from 'dashboard/api/emailCampaignAssets';
import {
  UPLOAD_TIMEOUT_MS,
  attachImageDrop,
  handleDrop,
  handlePaste,
  useImageDrop,
  waitForImageUploads,
} from '../composables/useImageDrop';
import { findBody } from '../canvasInsert';
import { UPLOAD_PLACEHOLDER_SRC } from '../sectionMarkup';

vi.mock('dashboard/api/emailCampaignAssets', () => ({
  default: { upload: vi.fn() },
}));
// The browser redraw (canvas) does not exist in jsdom; imageFile.spec.js covers it.
vi.mock('../imageFile', async importOriginal => ({
  ...(await importOriginal()),
  prepareImageFile: vi.fn(async file => file),
}));

const EMAIL =
  '<mjml><mj-body>' +
  '<mj-section css-class="topo"><mj-column><mj-text>Olá</mj-text></mj-column></mj-section>' +
  '<mj-section css-class="foto"><mj-column><mj-image src="https://cdn.exemplo.com.br/velha.png" alt="Velha"></mj-image></mj-column></mj-section>' +
  '<mj-section css-class="footer-locked"><mj-column><mj-text>Rodapé</mj-text></mj-column></mj-section>' +
  '</mj-body></mjml>';

const CAMPAIGN = 7;
const fileOf = (name, type = 'image/jpeg') => new File(['x'], name, { type });
const uploaded = url => ({ data: { url } });

let editor;
let container;

const blocks = () => findBody(editor).components().models;
const classesOf = () =>
  blocks().map(block => block.getAttributes()['css-class'] || 'novo');
const firstOfType = (component, type) => {
  if (component.get('type') === type) return component;
  return component
    .components()
    .map(child => firstOfType(child, type))
    .find(Boolean);
};
const blockImage = index => firstOfType(blocks()[index], 'mj-image');
const blockText = index => firstOfType(blocks()[index], 'mj-text');
const drop = (payload, component = null) =>
  handleDrop(editor, { payload, component, clientY: 0 }, CAMPAIGN);
const pasteEvent = ({ files = [], html = '', target = null }) => ({
  clipboardData: {
    files,
    getData: type => (type === 'text/html' ? html : ''),
  },
  target,
  preventDefault: vi.fn(),
});

beforeEach(() => {
  container = document.createElement('div');
  document.body.appendChild(container);
  // Headless: rendering the canvas frame under jsdom hangs on a busy machine. The drop logic works on
  // the component tree, which is the same.
  editor = grapesjs.init({
    headless: true,
    container,
    fromElement: false,
    storageManager: false,
    panels: { defaults: [] },
    plugins: [mjmlPlugin],
    pluginsOpts: { [mjmlPlugin]: { useCustomTheme: false, blocks: [] } },
  });
  editor.setComponents(EMAIL);
  EmailCampaignAssetsAPI.upload.mockReset();
  useImageDrop().dismissNotice();
});

afterEach(() => {
  editor.destroy();
  container.remove();
});

describe('image dropped on the canvas (#2908)', () => {
  it('uploads it and adds an Image block right below the text it fell on, showing the upload', async () => {
    let finish;
    EmailCampaignAssetsAPI.upload.mockReturnValue(
      new Promise(resolve => {
        finish = resolve;
      })
    );
    const { uploadingCount } = useImageDrop();

    drop({ files: [fileOf('Fachada.jpg')] }, blockText(0));

    expect(uploadingCount.value).toBe(1);
    finish(uploaded('https://app.exemplo.com.br/a.jpg'));
    await waitForImageUploads();

    expect(uploadingCount.value).toBe(0);
    expect(EmailCampaignAssetsAPI.upload).toHaveBeenCalledWith(
      7,
      expect.any(File),
      { timeout: UPLOAD_TIMEOUT_MS }
    );
    expect(classesOf()).toEqual(['topo', 'novo', 'foto', 'footer-locked']);
    expect(blockImage(1).get('src')).toBe('https://app.exemplo.com.br/a.jpg');
    expect(blockImage(1).getAttributes().alt).toBe('Fachada');
  });

  it('replaces the picture when dropped on an existing image', async () => {
    EmailCampaignAssetsAPI.upload.mockResolvedValue(
      uploaded('https://app.exemplo.com.br/nova.jpg')
    );

    drop({ files: [fileOf('nova.jpg')] }, blockImage(1));
    await waitForImageUploads();

    expect(classesOf()).toEqual(['topo', 'foto', 'footer-locked']);
    expect(blockImage(1).get('src')).toBe(
      'https://app.exemplo.com.br/nova.jpg'
    );
    expect(editor.runCommand('mjml-code')).toContain(
      'src="https://app.exemplo.com.br/nova.jpg"'
    );
  });

  it('adds several images in the order they came, above the locked footer', async () => {
    EmailCampaignAssetsAPI.upload
      .mockResolvedValueOnce(uploaded('https://app.exemplo.com.br/1.jpg'))
      .mockResolvedValueOnce(uploaded('https://app.exemplo.com.br/2.jpg'));

    drop({ files: [fileOf('1.jpg'), fileOf('2.jpg')] });
    await waitForImageUploads();

    expect(classesOf()).toEqual([
      'topo',
      'foto',
      'novo',
      'novo',
      'footer-locked',
    ]);
    expect(blockImage(2).get('src')).toBe('https://app.exemplo.com.br/1.jpg');
    expect(blockImage(3).get('src')).toBe('https://app.exemplo.com.br/2.jpg');
  });

  it('puts an image dropped on the locked footer right above it, footer unchanged', async () => {
    EmailCampaignAssetsAPI.upload.mockResolvedValue(
      uploaded('https://app.exemplo.com.br/a.jpg')
    );
    const footerBefore = blocks()[2].toHTML();

    drop({ files: [fileOf('a.jpg')] }, blockText(2));
    await waitForImageUploads();

    expect(classesOf()).toEqual(['topo', 'foto', 'novo', 'footer-locked']);
    expect(blocks()[3].toHTML()).toBe(footerBefore);
  });

  it('refuses a PDF with the images-only notice and changes nothing', async () => {
    drop({ files: [fileOf('contrato.pdf', 'application/pdf')] });
    await waitForImageUploads();

    expect(EmailCampaignAssetsAPI.upload).not.toHaveBeenCalled();
    expect(useImageDrop().notice.value).toEqual({ key: 'ONLY_IMAGES' });
    expect(classesOf()).toEqual(['topo', 'foto', 'footer-locked']);
  });

  it('points a dropped video to the Video block', async () => {
    drop({ files: [fileOf('apresentacao.mp4', 'video/mp4')] });
    await waitForImageUploads();

    expect(EmailCampaignAssetsAPI.upload).not.toHaveBeenCalled();
    expect(useImageDrop().notice.value).toEqual({ key: 'ONLY_IMAGES_VIDEO' });
    expect(classesOf()).toEqual(['topo', 'foto', 'footer-locked']);
  });

  it('on a failed upload inserts nothing and offers "Tentar de novo", which then works', async () => {
    EmailCampaignAssetsAPI.upload
      .mockRejectedValueOnce(new Error('Network Error'))
      .mockResolvedValueOnce(uploaded('https://app.exemplo.com.br/a.jpg'));

    drop({ files: [fileOf('a.jpg')] }, blockText(0));
    await waitForImageUploads();

    const { notice } = useImageDrop();
    expect(notice.value).toMatchObject({ key: 'UPLOAD_FAILED', count: 1 });
    expect(classesOf()).toEqual(['topo', 'foto', 'footer-locked']);

    notice.value.retry();
    await waitForImageUploads();

    expect(notice.value).toBeNull();
    expect(classesOf()).toEqual(['topo', 'novo', 'foto', 'footer-locked']);
  });

  it('says the limit when the server refuses the size, without retry', async () => {
    EmailCampaignAssetsAPI.upload.mockRejectedValue({
      response: { data: { error: 'email_campaign.asset_too_large' } },
    });

    drop({ files: [fileOf('a.jpg')] });
    await waitForImageUploads();

    expect(useImageDrop().notice.value).toEqual({ key: 'TOO_LARGE' });
    expect(classesOf()).toEqual(['topo', 'foto', 'footer-locked']);
  });

  it('makes text and images dragged from a site into blocks, never loose HTML', async () => {
    drop(
      {
        html:
          '<p style="color:red">Promoção <b>hoje</b></p>' +
          '<img src="https://cdn.exemplo.com.br/p.png" alt="Produto">' +
          '<img src="blob:https://site/abc">',
      },
      blockText(0)
    );

    expect(classesOf()).toEqual([
      'topo',
      'novo',
      'novo',
      'novo',
      'foto',
      'footer-locked',
    ]);
    expect(blockText(1).toHTML()).toContain(
      '<p>Promoção <strong>hoje</strong></p>'
    );
    expect(blockImage(2).get('src')).toBe('https://cdn.exemplo.com.br/p.png');
    expect(blockImage(3).get('src')).toBe(UPLOAD_PLACEHOLDER_SRC);
    expect(useImageDrop().notice.value).toEqual({
      key: 'MISSING_PUBLIC',
      count: 1,
    });
    const saved = editor.runCommand('mjml-code');
    expect(saved).not.toContain('<img');
    expect(saved).not.toContain('<p style');
  });

  it('keeps the order on retry: the image that failed goes back to its place', async () => {
    EmailCampaignAssetsAPI.upload
      .mockResolvedValueOnce(uploaded('https://app.exemplo.com.br/1.jpg'))
      .mockRejectedValueOnce(new Error('timeout of 90000ms exceeded'))
      .mockResolvedValueOnce(uploaded('https://app.exemplo.com.br/3.jpg'))
      .mockResolvedValueOnce(uploaded('https://app.exemplo.com.br/2.jpg'));

    drop(
      { files: [fileOf('1.jpg'), fileOf('2.jpg'), fileOf('3.jpg')] },
      blockText(0)
    );
    await waitForImageUploads();
    useImageDrop().notice.value.retry();
    await waitForImageUploads();

    expect(classesOf()).toEqual([
      'topo',
      'novo',
      'novo',
      'novo',
      'foto',
      'footer-locked',
    ]);
    expect([1, 2, 3].map(index => blockImage(index).get('src'))).toEqual([
      'https://app.exemplo.com.br/1.jpg',
      'https://app.exemplo.com.br/2.jpg',
      'https://app.exemplo.com.br/3.jpg',
    ]);
  });

  it('keeps the order of two failed images in a row on retry', async () => {
    EmailCampaignAssetsAPI.upload
      .mockRejectedValueOnce(new Error('Network Error'))
      .mockRejectedValueOnce(new Error('Network Error'))
      .mockResolvedValueOnce(uploaded('https://app.exemplo.com.br/3.jpg'))
      .mockResolvedValueOnce(uploaded('https://app.exemplo.com.br/1.jpg'))
      .mockResolvedValueOnce(uploaded('https://app.exemplo.com.br/2.jpg'));

    drop(
      { files: [fileOf('1.jpg'), fileOf('2.jpg'), fileOf('3.jpg')] },
      blockText(0)
    );
    await waitForImageUploads();
    useImageDrop().notice.value.retry();
    await waitForImageUploads();

    expect([1, 2, 3].map(index => blockImage(index).get('src'))).toEqual([
      'https://app.exemplo.com.br/1.jpg',
      'https://app.exemplo.com.br/2.jpg',
      'https://app.exemplo.com.br/3.jpg',
    ]);
  });

  it('keeps a whole pasted e-mail in order: text, image, text', () => {
    drop(
      {
        html:
          '<p>Olá, cliente.</p><p><img src="https://cdn.exemplo.com.br/oferta.png" alt="Oferta"></p>' +
          '<p>Até logo.</p>',
      },
      blockText(0)
    );

    expect(classesOf()).toEqual([
      'topo',
      'novo',
      'novo',
      'novo',
      'foto',
      'footer-locked',
    ]);
    expect(blockText(1).toHTML()).toContain('<p>Olá, cliente.</p>');
    expect(blockImage(2).get('src')).toBe(
      'https://cdn.exemplo.com.br/oferta.png'
    );
    expect(blockText(3).toHTML()).toContain('<p>Até logo.</p>');
  });

  it('makes plain text dropped on the canvas a Text block', () => {
    drop({ text: 'Linha 1\nLinha 2' });

    expect(classesOf()).toEqual(['topo', 'foto', 'novo', 'footer-locked']);
    expect(blockText(2).toHTML()).toContain('<p>Linha 1</p><p>Linha 2</p>');
  });

  it('touches nothing when the upload ends after the editor closed', async () => {
    let finish;
    EmailCampaignAssetsAPI.upload.mockReturnValue(
      new Promise(resolve => {
        finish = resolve;
      })
    );
    const detach = attachImageDrop(editor, () => CAMPAIGN);

    drop({ files: [fileOf('a.jpg')] });
    detach();
    finish(uploaded('https://app.exemplo.com.br/a.jpg'));
    await waitForImageUploads();

    expect(classesOf()).toEqual(['topo', 'foto', 'footer-locked']);
    expect(useImageDrop().uploadingCount.value).toBe(0);
  });
});

describe('image pasted on the canvas (#2908)', () => {
  it('never replaces the selected image: a pasted print goes below it', async () => {
    EmailCampaignAssetsAPI.upload.mockResolvedValue(
      uploaded('https://app.exemplo.com.br/print.png')
    );
    editor.select(blockImage(1));
    const event = pasteEvent({ files: [fileOf('image.png', 'image/png')] });

    handlePaste(editor, event, CAMPAIGN);
    await waitForImageUploads();

    expect(event.preventDefault).toHaveBeenCalled();
    expect(classesOf()).toEqual(['topo', 'foto', 'novo', 'footer-locked']);
    expect(blockImage(1).get('src')).toBe(
      'https://cdn.exemplo.com.br/velha.png'
    );
    expect(blockImage(2).get('src')).toBe(
      'https://app.exemplo.com.br/print.png'
    );
  });

  it('adds a pasted print below the selected block when it is not an image', async () => {
    EmailCampaignAssetsAPI.upload.mockResolvedValue(
      uploaded('https://app.exemplo.com.br/print.png')
    );
    editor.select(blockText(0));

    handlePaste(
      editor,
      pasteEvent({ files: [fileOf('image.png', 'image/png')] }),
      CAMPAIGN
    );
    await waitForImageUploads();

    expect(classesOf()).toEqual(['topo', 'novo', 'foto', 'footer-locked']);
  });

  it('pastes Word text formatted inside the text and its images as blocks below', () => {
    const execCommand = vi.fn();
    const target = document.createElement('div');
    target.setAttribute('contenteditable', 'true');
    Object.defineProperty(target, 'ownerDocument', {
      value: { execCommand },
    });
    editor.select(blockText(0));
    const event = pasteEvent({
      // Word also puts a picture of the copied text on the clipboard: the text must win.
      files: [fileOf('image.png', 'image/png')],
      html: '<p class="MsoNormal">Olá <b>cliente</b><img src="file:///C:/x.png"></p>',
      target,
    });

    handlePaste(editor, event, CAMPAIGN);

    expect(event.preventDefault).toHaveBeenCalled();
    expect(execCommand).toHaveBeenCalledWith(
      'insertHTML',
      false,
      '<p>Olá <strong>cliente</strong></p>'
    );
    expect(EmailCampaignAssetsAPI.upload).not.toHaveBeenCalled();
    expect(classesOf()).toEqual(['topo', 'novo', 'foto', 'footer-locked']);
    expect(blockImage(1).get('src')).toBe(UPLOAD_PLACEHOLDER_SRC);
  });

  it('makes a text paste outside a text into blocks below the selected one', () => {
    editor.select(blockText(0));
    const event = pasteEvent({ html: '<p>Oi</p>' });

    handlePaste(editor, event, CAMPAIGN);

    expect(event.preventDefault).toHaveBeenCalled();
    expect(classesOf()).toEqual(['topo', 'novo', 'foto', 'footer-locked']);
  });

  it('leaves the paste to GrapesJS when it is pasting blocks copied in the editor', () => {
    editor.select(blockText(0));
    editor.getModel().set('clipboard', [blocks()[0]]);
    const event = pasteEvent({ html: '<p>Oi</p>' });

    handlePaste(editor, event, CAMPAIGN);

    expect(event.preventDefault).not.toHaveBeenCalled();
    expect(classesOf()).toEqual(['topo', 'foto', 'footer-locked']);
  });
});

describe('drop wiring on the canvas frame (#2908)', () => {
  const transfer = text => ({
    files: [],
    getData: type => (type === 'text/plain' ? text : ''),
  });
  const frameEvent = (name, dt) => {
    const event = new Event(name, { cancelable: true });
    Object.defineProperty(event, 'dataTransfer', { value: dt });
    return event;
  };
  const tick = () =>
    new Promise(resolve => {
      setTimeout(resolve, 0);
    });
  let frame;
  let detach;

  beforeEach(() => {
    frame = new EventTarget();
    detach = attachImageDrop(editor, () => CAMPAIGN);
    editor.trigger('canvas:frame:load', { window: frame });
  });
  afterEach(() => detach());

  const dropOnFrame = text => {
    const dt = transfer(text);
    frame.dispatchEvent(frameEvent('drop', dt));
    const result = { setContent: vi.fn() };
    editor.trigger('canvas:dragdata', dt, result);
    return result;
  };

  it('cancels the GrapesJS drop and inserts a block itself', async () => {
    const result = dropOnFrame('De outra aba');
    await tick();

    expect(result.setContent).toHaveBeenCalledWith('');
    expect(classesOf()).toEqual(['topo', 'foto', 'novo', 'footer-locked']);
  });

  it('leaves a drag that started inside the canvas (moving selected text) untouched', async () => {
    frame.dispatchEvent(new Event('dragstart'));
    const dt = transfer('texto movido');
    const event = frameEvent('drop', dt);
    frame.dispatchEvent(event);
    const result = { setContent: vi.fn() };
    editor.trigger('canvas:dragdata', dt, result);
    await tick();

    expect(event.defaultPrevented).toBe(false);
    expect(result.setContent).not.toHaveBeenCalled();
    expect(classesOf()).toEqual(['topo', 'foto', 'footer-locked']);
  });

  it('does nothing for a GrapesJS read without a drop of ours, nor twice for one drop', async () => {
    const stale = { setContent: vi.fn() };
    editor.trigger('canvas:dragdata', transfer('x'), stale);
    dropOnFrame('Uma vez');
    const again = { setContent: vi.fn() };
    editor.trigger('canvas:dragdata', transfer('x'), again);
    await tick();

    expect(stale.setContent).not.toHaveBeenCalled();
    expect(again.setContent).not.toHaveBeenCalled();
    expect(classesOf()).toEqual(['topo', 'foto', 'novo', 'footer-locked']);
  });

  it('inserts nothing when the editor closes right after the drop', async () => {
    dropOnFrame('Tarde demais');
    detach();
    await tick();

    expect(classesOf()).toEqual(['topo', 'foto', 'footer-locked']);
  });
});
