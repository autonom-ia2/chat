import { plainTextToHtml, sanitizePastedHtml } from '../pastedHtml';

describe('sanitizePastedHtml (#2908)', () => {
  it('keeps paragraphs, bold, italic, lists and safe links, drops styles and classes', () => {
    const { html, images } = sanitizePastedHtml(
      '<p class="MsoNormal" style="color:red">Olá <b>cliente</b> e <i>amigo</i></p>' +
        '<ul><li>Um</li><li><a href="https://exemplo.com.br" style="x">Dois</a></li></ul>' +
        '<p><a href="javascript:alert(1)">perigo</a></p>'
    );

    expect(html).toBe(
      '<p>Olá <strong>cliente</strong> e <em>amigo</em></p>' +
        '<ul><li>Um</li><li><a href="https://exemplo.com.br">Dois</a></li></ul>' +
        '<p>perigo</p>'
    );
    expect(images).toEqual([]);
  });

  it('takes images out of the text, in order, with their address and description', () => {
    const { html, images } = sanitizePastedHtml(
      '<p>Antes</p><p><img src="https://cdn.exemplo.com.br/a.png" alt="A"></p>' +
        '<div><img src="data:image/png;base64,AAAA"></div><p>Depois</p>'
    );

    expect(html).toBe('<p>Antes</p><p>Depois</p>');
    expect(images).toEqual([
      { src: 'https://cdn.exemplo.com.br/a.png', alt: 'A' },
      { src: 'data:image/png;base64,AAAA', alt: '' },
    ]);
  });

  it('reads Google Docs bold spans and ignores its non-bold <b> wrapper', () => {
    const { html } = sanitizePastedHtml(
      '<meta charset="utf-8"><b style="font-weight:normal;" id="docs-internal-guid-1">' +
        '<p dir="ltr"><span style="font-weight:700">Forte</span><span> normal</span></p></b>'
    );

    expect(html).toBe('<p><strong>Forte</strong> normal</p>');
  });

  it('never nests paragraphs and turns headings into bold paragraphs', () => {
    const { html } = sanitizePastedHtml(
      '<div><p>Um</p><p>Dois</p></div><h2>Título</h2><div>Três</div>'
    );

    expect(html).toBe(
      '<p>Um</p><p>Dois</p><p><strong>Título</strong></p><p>Três</p>'
    );
  });

  it('drops scripts, styles and Word comments', () => {
    const { html } = sanitizePastedHtml(
      '<style>p{}</style><!--[if gte mso 9]><xml></xml><![endif]--><p>Texto<script>x()</script></p>'
    );

    expect(html).toBe('<p>Texto</p>');
  });

  it('returns no text when only an image came', () => {
    expect(
      sanitizePastedHtml('<img src="https://cdn.exemplo.com.br/a.png">')
    ).toEqual({
      html: '',
      images: [{ src: 'https://cdn.exemplo.com.br/a.png', alt: '' }],
    });
  });
});

describe('plainTextToHtml', () => {
  it('makes one escaped paragraph per line', () => {
    expect(plainTextToHtml('Oi <você>\n\n  tudo bem?  ')).toBe(
      '<p>Oi &lt;você&gt;</p><p>tudo bem?</p>'
    );
  });
});
