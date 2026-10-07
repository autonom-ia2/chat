import { KeepAlive, h, nextTick, reactive, ref } from 'vue';
import { config, flushPromises, mount } from '@vue/test-utils';
import EmailTemplateImportPage from '../pages/EmailTemplateImportPage.vue';

const api = vi.hoisted(() => ({
  latest: vi.fn(),
  start: vi.fn(),
  show: vi.fn(),
  fix: vi.fn(),
  save: vi.fn(),
}));
const templatesIndex = vi.hoisted(() => vi.fn());
const router = vi.hoisted(() => ({ push: vi.fn(), replace: vi.fn() }));
const route = vi.hoisted(() => ({
  name: 'campaigns_email_template_import',
  params: { accountId: '9' },
  query: {},
}));

vi.mock('dashboard/api/emailCampaignTemplateImports', () => ({ default: api }));
vi.mock('dashboard/api/emailCampaignTemplates', () => ({
  default: { index: templatesIndex },
}));
vi.mock('dashboard/helper/compileEmailMjml', () => ({
  compileEmailMjml: vi.fn(async mjml =>
    mjml ? '<html><body>ok</body></html>' : ''
  ),
  withImportMarks: html => html,
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ getters: {} }),
  useMapGetter: () => ref(false),
}));
vi.mock('vue-router', () => ({
  useRoute: () => route,
  useRouter: () => router,
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, locale: { value: 'pt_BR' } }),
}));

const ready = (extra = {}) => ({
  id: 7,
  status: 'ready',
  progress: { step: 'done' },
  report: { title: 'Novidades de outubro', warnings: [] },
  result_mjml: '<mjml></mjml>',
  preview_html: '<html><body>antes</body></html>',
  blocking: [],
  fixes: [],
  targets: { images: [], parts: [], fields: [] },
  ...extra,
});
const failure = code => ({
  response: { data: { error: `email_template_import.${code}` } },
});

const defaultPlugins = config.global.plugins;
let wrapper;

beforeAll(() => {
  config.global.plugins = [];
  HTMLDialogElement.prototype.showModal = function showModal() {
    this.setAttribute('open', '');
  };
  HTMLDialogElement.prototype.close = function close() {
    this.removeAttribute('open');
  };
  Element.prototype.scrollIntoView = vi.fn();
});

afterAll(() => {
  config.global.plugins = defaultPlugins;
});

beforeEach(() => {
  Object.values(api).forEach(fn => fn.mockReset());
  router.push.mockReset();
  router.replace.mockReset();
  route.params = reactive({ accountId: '9' });
  route.query = {};
  templatesIndex.mockResolvedValue({
    data: [{ id: 1, account_id: 9, name: 'Novidades de outubro' }],
  });
});

afterEach(() => wrapper?.unmount());

const mountPage = async () => {
  wrapper = mount(EmailTemplateImportPage, { attachTo: document.body });
  await flushPromises();
  return wrapper;
};

const buttonWith = label =>
  wrapper.findAll('button').find(button => button.text().includes(label));

it('brings a pasted model, shows before and after, names it and goes back to the library', async () => {
  api.start.mockResolvedValue({ data: { id: 7, status: 'queued' } });
  api.show.mockResolvedValue({ data: ready() });
  api.save.mockResolvedValue({ data: { id: 55 } });
  await mountPage();

  expect(
    wrapper.findAll('[data-mode]').map(card => card.attributes('data-mode'))
  ).toEqual(['file', 'paste', 'url']);
  await wrapper.find('[data-mode="paste"]').trigger('click');
  await wrapper
    .find('textarea')
    .setValue('<table><tr><td>Oi</td></tr></table>');
  await wrapper.find('form').trigger('submit');
  await flushPromises();

  expect(api.start).toHaveBeenCalledWith({
    kind: 'paste',
    content: '<table><tr><td>Oi</td></tr></table>',
  });
  expect(router.replace).toHaveBeenCalledWith(
    expect.objectContaining({
      params: expect.objectContaining({ importId: 7 }),
    })
  );
  const frames = wrapper.findAll('iframe');
  expect(frames).toHaveLength(2);
  frames.forEach(frame => expect(frame.attributes('sandbox')).toBe(''));
  expect(frames[0].attributes('srcdoc')).toContain('antes');
  expect(wrapper.text()).toContain('EMAIL_IMPORT.SCREEN.RESULT.TITLE_READY');

  await buttonWith('EMAIL_IMPORT.SCREEN.RESULT.CONTINUE').trigger('click');
  await flushPromises();
  expect(wrapper.find('input[type="text"]').element.value).toBe(
    'Novidades de outubro (2)'
  );

  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(api.save).toHaveBeenCalledWith(7, 'Novidades de outubro (2)');
  expect(router.push).toHaveBeenCalledWith(
    expect.objectContaining({
      name: 'campaigns_email_templates',
      query: { novo: 55 },
    })
  );
});

it('tells the step while the model is being prepared', async () => {
  route.params.importId = '7';
  api.show.mockResolvedValue({
    data: {
      id: 7,
      status: 'processing',
      progress: { step: 'images', images_done: 2, images_total: 4 },
    },
  });
  vi.useFakeTimers();
  try {
    await mountPage();
    const lines = wrapper.findAll('li[data-state]');
    expect(lines.map(line => line.attributes('data-state'))).toEqual([
      'done',
      'now',
      'wait',
    ]);
    expect(lines[1].text()).toBe('EMAIL_IMPORT.SCREEN.PREPARING.IMAGES_COUNT');

    api.show.mockResolvedValue({ data: ready() });
    await vi.advanceTimersByTimeAsync(1600);
    await flushPromises();
    expect(wrapper.text()).toContain('EMAIL_IMPORT.SCREEN.RESULT.TITLE_READY');
  } finally {
    vi.useRealTimers();
  }
});

it('solves a field that does not exist here with the choice list, never a native select', async () => {
  route.params.importId = '7';
  api.show.mockResolvedValue({
    data: ready({
      blocking: [{ code: 'unknown_fields', items: ['cupom'] }],
      targets: { images: [], parts: [], fields: ['cupom'] },
    }),
  });
  api.fix.mockResolvedValue({
    data: ready({
      fixes: [
        {
          code: 'unknown_fields',
          choice: 'field',
          target: 'cupom',
          value: 'primeiro_nome',
        },
      ],
    }),
  });
  await mountPage();

  expect(wrapper.text()).toContain('EMAIL_IMPORT.SCREEN.RESULT.TITLE_PENDING');
  await buttonWith('EMAIL_IMPORT.SCREEN.ROWS.CHOOSE').trigger('click');
  await flushPromises();

  const dialog = document.body.querySelector('dialog[open]');
  expect(dialog).not.toBeNull();
  expect(dialog.querySelector('select')).toBeNull();
  const combobox = dialog.querySelector('[role="combobox"]');
  combobox.click();
  await flushPromises();
  const option = Array.from(dialog.querySelectorAll('[role="option"]')).find(
    item => item.textContent.includes('FIELDS.PRIMEIRO_NOME')
  );
  option.click();
  await flushPromises();
  Array.from(dialog.querySelectorAll('button'))
    .find(button => button.textContent.includes('FIELD_DIALOG.CHOOSE'))
    .click();
  await flushPromises();

  expect(api.fix).toHaveBeenCalledWith(7, {
    kind: 'field',
    target: 'cupom',
    choice: 'field',
    value: 'primeiro_nome',
  });
  expect(wrapper.text()).toContain('EMAIL_IMPORT.SCREEN.RESULT.TITLE_READY');
  expect(wrapper.find('[data-tone="ok"]').text()).toContain(
    'FIXED.FIELD_FIELD'
  );
});

it('says in one sentence that a file is not an e-mail, before sending it', async () => {
  await mountPage();
  await wrapper.find('[data-mode="file"]').trigger('click');
  const input = wrapper.find('input[type="file"]');
  Object.defineProperty(input.element, 'files', {
    value: [
      new File(['%PDF'], 'campanha-outubro.pdf', { type: 'application/pdf' }),
    ],
  });
  await input.trigger('change');
  await wrapper.find('form').trigger('submit');
  await flushPromises();

  expect(api.start).not.toHaveBeenCalled();
  expect(wrapper.text()).toContain(
    'EMAIL_IMPORT.SCREEN.ERROR.NOT_EMAIL.FILE_TITLE'
  );
  expect(wrapper.text()).toContain('campanha-outubro.pdf');
  await buttonWith('EMAIL_IMPORT.SCREEN.ERROR.TRY_OTHER').trigger('click');
  expect(wrapper.findAll('[data-mode]')).toHaveLength(3);
});

it('keeps an address problem under the field and resumes an import already running', async () => {
  api.start.mockRejectedValueOnce(failure('url_not_https'));
  await mountPage();
  await wrapper.find('[data-mode="url"]').trigger('click');
  await wrapper
    .find('input[type="url"]')
    .setValue('http://news.example.com/ver');
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(wrapper.find('[role="alert"]').text()).toBe(
    'EMAIL_IMPORT.ERRORS.URL_NOT_HTTPS'
  );

  api.start.mockRejectedValueOnce(failure('in_progress'));
  api.latest.mockResolvedValue({
    data: { payload: [{ id: 3, status: 'processing' }] },
  });
  api.show.mockResolvedValue({ data: ready({ id: 3 }) });
  await wrapper
    .find('input[type="url"]')
    .setValue('https://news.example.com/ver');
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(api.show).toHaveBeenCalledWith(3);
  expect(wrapper.text()).toContain('EMAIL_IMPORT.SCREEN.RESULT.TITLE_READY');
});

it('offers to try again when the preparation fails in the middle', async () => {
  route.params.importId = '7';
  api.show.mockResolvedValue({
    data: { id: 7, status: 'failed', error_code: 'stalled' },
  });
  await mountPage();

  expect(wrapper.text()).toContain(
    'EMAIL_IMPORT.SCREEN.ERROR.FAILED.FILE_TITLE'
  );
  expect(buttonWith('EMAIL_IMPORT.SCREEN.ERROR.TRY_AGAIN').exists()).toBe(true);
});

it('speaks of the pasted code, not of a file, when pasting fails', async () => {
  api.start.mockRejectedValue(failure('malformed_mjml'));
  await mountPage();
  await wrapper.find('[data-mode="paste"]').trigger('click');
  await wrapper.find('textarea').setValue('<mjml><mj-body>');
  await wrapper.find('form').trigger('submit');
  await flushPromises();

  expect(wrapper.text()).toContain(
    'EMAIL_IMPORT.SCREEN.ERROR.NOT_EMAIL.PASTE_TITLE'
  );
  expect(wrapper.text()).toContain(
    'EMAIL_IMPORT.SCREEN.ERROR.NOT_EMAIL.PASTE_TEXT'
  );
  expect(wrapper.text()).not.toContain('FILE_');
});

it('brings an address that did not open back under the field, still typed', async () => {
  api.start.mockResolvedValue({ data: { id: 7, status: 'queued' } });
  api.show.mockResolvedValue({
    data: { id: 7, status: 'failed', error_code: 'url_unreachable' },
  });
  await mountPage();
  await wrapper.find('[data-mode="url"]').trigger('click');
  await wrapper
    .find('input[type="url"]')
    .setValue('https://news.example.com/ver');
  await wrapper.find('form').trigger('submit');
  await flushPromises();

  expect(wrapper.find('[role="alert"]').text()).toBe(
    'EMAIL_IMPORT.ERRORS.URL_UNREACHABLE'
  );
  expect(wrapper.find('input[type="url"]').element.value).toBe(
    'https://news.example.com/ver'
  );
});

it('keeps following when one check fails on the network', async () => {
  route.params.importId = '7';
  api.show
    .mockResolvedValueOnce({ data: { id: 7, status: 'processing' } })
    .mockRejectedValueOnce(new Error('Network Error'))
    .mockResolvedValue({ data: ready() });
  vi.useFakeTimers();
  try {
    await mountPage();
    await vi.advanceTimersByTimeAsync(1600);
    expect(wrapper.text()).not.toContain('ERROR.FAILED');
    await vi.advanceTimersByTimeAsync(1600);
    await flushPromises();
    expect(wrapper.text()).toContain('EMAIL_IMPORT.SCREEN.RESULT.TITLE_READY');
  } finally {
    vi.useRealTimers();
  }
});

it('drops an answer that arrives after the kept-alive page left, and stops asking', async () => {
  route.params.importId = '7';
  let answer;
  api.show.mockReturnValue(
    new Promise(resolve => {
      answer = resolve;
    })
  );
  const shown = ref(true);
  const Host = {
    render: () =>
      h(KeepAlive, null, shown.value ? h(EmailTemplateImportPage) : null),
  };
  vi.useFakeTimers();
  try {
    wrapper = mount(Host, { attachTo: document.body });
    await flushPromises();
    shown.value = false;
    await nextTick();
    answer({
      data: { id: 7, status: 'saved', email_campaign_template_id: 55 },
    });
    await vi.advanceTimersByTimeAsync(5000);

    expect(api.show).toHaveBeenCalledTimes(1);
    expect(router.replace).not.toHaveBeenCalledWith(
      expect.objectContaining({ name: 'campaigns_email_templates' })
    );

    // Coming back starts a new visit from the address.
    api.show.mockResolvedValue({ data: ready() });
    shown.value = true;
    await nextTick();
    await flushPromises();
    expect(api.show).toHaveBeenCalledTimes(2);
    expect(wrapper.text()).toContain('EMAIL_IMPORT.SCREEN.RESULT.TITLE_READY');
  } finally {
    vi.useRealTimers();
  }
});

it('ignores an answer about another import', async () => {
  route.params.importId = '7';
  api.show.mockResolvedValue({ data: ready({ id: 3 }) });
  await mountPage();

  expect(wrapper.text()).not.toContain(
    'EMAIL_IMPORT.SCREEN.RESULT.TITLE_READY'
  );
});

it('says when the preview could not be shown, with a way out', async () => {
  route.params.importId = '7';
  api.show.mockResolvedValue({ data: ready({ result_mjml: '' }) });
  await mountPage();

  const empty = wrapper.find('[data-no-preview]');
  expect(empty.text()).toContain('EMAIL_IMPORT.SCREEN.RESULT.NO_PREVIEW');
  await empty.find('button').trigger('click');
  expect(wrapper.findAll('[data-mode]')).toHaveLength(3);
});
