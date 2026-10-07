import EmailCampaignTemplateImportsAPI from '../emailCampaignTemplateImports';

describe('Email template imports API', () => {
  const originalAxios = window.axios;
  const axiosMock = {
    get: vi.fn(() => Promise.resolve()),
    post: vi.fn(() => Promise.resolve()),
  };
  const base = '/api/v1/accounts/85/email_campaigns/template_imports';

  beforeEach(() => {
    window.history.pushState({}, '', '/app/accounts/85/email_campaigns');
    window.axios = axiosMock;
  });

  afterEach(() => {
    vi.clearAllMocks();
    window.axios = originalAxios;
  });

  it('starts a pasted or address import as JSON', () => {
    EmailCampaignTemplateImportsAPI.start({
      kind: 'paste',
      content: '<p>Oi</p>',
    });
    EmailCampaignTemplateImportsAPI.start({
      kind: 'url',
      url: 'https://x.example.com',
    });

    expect(axiosMock.post).toHaveBeenNthCalledWith(1, base, {
      source_kind: 'paste',
      content: '<p>Oi</p>',
      url: undefined,
    });
    expect(axiosMock.post).toHaveBeenNthCalledWith(2, base, {
      source_kind: 'url',
      content: undefined,
      url: 'https://x.example.com',
    });
  });

  it('sends a file as multipart', () => {
    const file = new File(['<p>Oi</p>'], 'modelo.html', { type: 'text/html' });
    EmailCampaignTemplateImportsAPI.start({ kind: 'file', file });

    const [url, form, options] = axiosMock.post.mock.calls[0];
    expect(url).toBe(base);
    expect(form.get('source_kind')).toBe('file');
    expect(form.get('file').name).toBe('modelo.html');
    expect(options.headers['Content-Type']).toBe('multipart/form-data');
  });

  it('follows, fixes and saves an import', () => {
    const file = new File(['x'], 'troca.png', { type: 'image/png' });
    EmailCampaignTemplateImportsAPI.latest();
    EmailCampaignTemplateImportsAPI.show(7);
    EmailCampaignTemplateImportsAPI.fix(7, {
      kind: 'field',
      target: 'cupom',
      choice: 'text',
      value: 'OUTUBRO10',
    });
    EmailCampaignTemplateImportsAPI.fix(7, {
      kind: 'image',
      target: 0,
      choice: 'upload',
      file,
    });
    EmailCampaignTemplateImportsAPI.save(7, 'Outubro');

    expect(axiosMock.get).toHaveBeenNthCalledWith(1, base);
    expect(axiosMock.get).toHaveBeenNthCalledWith(2, `${base}/7`);
    expect(axiosMock.post).toHaveBeenNthCalledWith(1, `${base}/7/fix`, {
      kind: 'field',
      target: 'cupom',
      choice: 'text',
      value: 'OUTUBRO10',
    });
    const [, form] = axiosMock.post.mock.calls[1];
    expect(form.get('target')).toBe('0');
    expect(form.get('file').name).toBe('troca.png');
    expect(axiosMock.post).toHaveBeenNthCalledWith(3, `${base}/7/save`, {
      name: 'Outubro',
    });
  });

  it('asks the AI to rebuild one part', () => {
    EmailCampaignTemplateImportsAPI.rebuild(7, 'trecho-2');

    expect(axiosMock.post).toHaveBeenCalledWith(`${base}/7/rebuild`, {
      target: 'trecho-2',
    });
  });
});
