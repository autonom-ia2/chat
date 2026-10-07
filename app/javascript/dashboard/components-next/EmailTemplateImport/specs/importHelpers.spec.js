import { chipSegments } from '../chipSegments';
import {
  classifyError,
  errorCode,
  fileProblem,
  pasteProblem,
  sizeLabel,
  sourceOf,
} from '../importErrors';
import { cssString, withImportMarks } from 'dashboard/helper/compileEmailMjml';
import { progressLines, progressPercent } from '../importProgress';
import { uniqueName } from '../uniqueName';

describe('importErrors', () => {
  it('reads the code the server answers', () => {
    expect(
      errorCode({
        response: { data: { error: 'email_template_import.too_large' } },
      })
    ).toBe('too_large');
    expect(errorCode({ response: { data: { error: 'other' } } })).toBe('');
    expect(errorCode(new Error('network'))).toBe('');
  });

  it('gives each code one screen', () => {
    expect(classifyError('url_not_https').kind).toBe('inline');
    expect(classifyError('unsupported_file').kind).toBe('not_email');
    expect(classifyError('zip_too_large').kind).toBe('too_big');
    expect(classifyError('stalled').kind).toBe('failed');
    expect(classifyError('').kind).toBe('failed');
    expect(classifyError('rate_limited').kind).toBe('other');
  });

  it('keeps an address that did not open under the field, not on an error screen', () => {
    expect(classifyError('url_unreachable').kind).toBe('inline');
  });

  it('knows how the model came in, so errors speak of a file, a code or an address', () => {
    expect(['file', 'paste', 'url'].map(sourceOf)).toEqual([
      'file',
      'paste',
      'url',
    ]);
    expect(sourceOf(undefined)).toBe('file');
  });

  it('checks the file and the pasted code before sending', () => {
    const file = (name, size) => ({ name, size });
    expect(fileProblem(file('modelo.HTML', 10))).toBe('');
    expect(fileProblem(file('modelo.zip', 3 * 1024 * 1024))).toBe(
      'zip_too_large'
    );
    expect(fileProblem(file('modelo.html', 600 * 1024))).toBe('too_large');
    expect(fileProblem(file('campanha.pdf', 10))).toBe('unsupported_file');
    expect(pasteProblem('   ')).toBe('empty');
    expect(pasteProblem('x'.repeat(501 * 1024))).toBe('too_large');
    expect(pasteProblem('<p>Oi</p>')).toBe('');
  });

  it('writes sizes the way people read them', () => {
    expect(sizeLabel(10)).toBe('1 KB');
    expect(sizeLabel(38 * 1024)).toBe('38 KB');
    expect(sizeLabel(48 * 1024 * 1024)).toBe('48 MB');
    expect(sizeLabel(1.5 * 1024 * 1024)).toBe('1.5 MB');
  });
});

describe('importProgress', () => {
  it('moves the three sentences with the step of the job', () => {
    expect(progressLines({}, 'queued').map(line => line.state)).toEqual([
      'now',
      'wait',
      'wait',
    ]);
    const images = progressLines(
      { step: 'images', images_done: 2, images_total: 4 },
      'processing'
    );
    expect(images.map(line => line.state)).toEqual(['done', 'now', 'wait']);
    expect(images[1]).toEqual({
      key: 'IMAGES_COUNT',
      state: 'now',
      params: { done: 2, total: 4 },
    });
    expect(progressLines({ step: 'checking' }, 'processing')[1].key).toBe(
      'IMAGES'
    );
    expect(progressLines({}, 'ready').map(line => line.state)).toEqual([
      'done',
      'done',
      'done',
    ]);
  });

  it('fills the bar as it goes', () => {
    expect(progressPercent({}, 'queued')).toBe(10);
    expect(
      progressPercent(
        { step: 'images', images_done: 2, images_total: 4 },
        'processing'
      )
    ).toBe(50);
    expect(progressPercent({ step: 'checking' }, 'processing')).toBe(77);
    expect(progressPercent({}, 'ready')).toBe(100);
  });
});

describe('chipSegments', () => {
  it('cuts a sentence into text and fields, never HTML', () => {
    const t = (key, params) => `Troquei ${params.from} por ${params.to}.`;
    expect(
      chipSegments(t, 'k', { from: '{{lead.nome}}', to: '<b>{{ nome }}</b>' })
    ).toEqual([
      { text: 'Troquei ' },
      { text: '{{lead.nome}}', chip: true },
      { text: ' por ' },
      { text: '<b>{{ nome }}</b>', chip: true },
      { text: '.' },
    ]);
  });
});

describe('withImportMarks', () => {
  const html =
    '<html><head></head><body><a href="https://x.example">x</a></body></html>';

  it('tags what is still to solve and keeps links from opening, with CSS only', () => {
    const out = withImportMarks(html, {
      unresolved: 'Ficou como imagem',
      missing: 'Imagem não veio',
    });
    const style = out.slice(out.indexOf('<style>'), out.indexOf('</head>'));

    expect(style).toContain('a{pointer-events:none');
    expect(style).toContain(
      '.import-unresolved::before{content:"Ficou como imagem"'
    );
    expect(style).toContain(
      '.import-missing::before{content:"Imagem não veio"'
    );
    expect(style).not.toContain('<script');
    expect(withImportMarks('')).toBe('');
  });

  it('writes a tag as a CSS string that cannot close the rule or the style', () => {
    expect(cssString('a"b\\c</style>')).toBe('"a\\"b\\\\c\\3c /style>"');
  });
});

describe('uniqueName', () => {
  it('keeps the title, or adds a number when the account already has it', () => {
    expect(uniqueName('Outubro', ['Clube'])).toBe('Outubro');
    expect(uniqueName('Outubro', ['outubro', 'Outubro (2)'])).toBe(
      'Outubro (3)'
    );
  });
});
