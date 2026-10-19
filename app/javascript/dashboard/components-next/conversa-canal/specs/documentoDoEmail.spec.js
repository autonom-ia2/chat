import { mount } from '@vue/test-utils';
import {
  SANDBOX_DO_EMAIL,
  citacaoDoDocumento,
  corpoParaImprimir,
  documentoIsolado,
} from '../email/documentoDoEmail';
import { semRastreio } from '../email/dadosDoEmail';
import CorpoIsoladoDoEmail from '../email/CorpoIsoladoDoEmail.vue';

// #1884: o e-mail HTML do remetente vai inteiro, isolado, para uma moldura sem script.
const ler = html => new DOMParser().parseFromString(html, 'text/html');

// O jsdom não monta a folha de estilo de <style> em documento do DOMParser (o Chrome,
// o Safari e o Firefox montam, e é nela que o lettersanitizer limpa o CSS). Aqui a
// folha sai de uma cópia no documento do teste, só para o sanitizador poder lê-la.
const SHEET = Object.getOwnPropertyDescriptor(
  window.HTMLStyleElement.prototype,
  'sheet'
);
const folhas = new WeakMap();
beforeAll(() => {
  Object.defineProperty(window.HTMLStyleElement.prototype, 'sheet', {
    configurable: true,
    get() {
      const propria = SHEET.get.call(this);
      if (propria) return propria;
      if (!folhas.has(this)) {
        const copia = document.createElement('style');
        copia.textContent = this.textContent;
        document.head.append(copia);
        folhas.set(this, copia.sheet);
        copia.remove();
      }
      return folhas.get(this);
    },
  });
});
afterAll(() => {
  Object.defineProperty(window.HTMLStyleElement.prototype, 'sheet', SHEET);
});

const CONVITE = `<!doctype html><html><head>
<meta http-equiv="refresh" content="0;url=https://mau.test">
<base href="https://mau.test/">
<link rel="stylesheet" href="https://mau.test/a.css">
<style>.coluna{width:50%!important} @media (max-width:480px){.coluna{width:100%!important}}</style>
</head><body bgcolor="#f3f2ef" style="margin:0;font-family:Arial" text="#333333">
<table class="coluna"><tr><td>Convite</td></tr></table></body></html>`;

describe('documento isolado do e-mail (#1884)', () => {
  it('mantém os <style> do <head>, o @media, o !important e o estilo do <body>', () => {
    const doc = ler(documentoIsolado(CONVITE));
    const css = [...doc.querySelectorAll('style')]
      .map(estilo => estilo.textContent)
      .join('\n');
    expect(css).toContain('.coluna');
    expect(css).toContain('@media');
    expect(css).toContain('!important');
    const corpo = doc.body;
    // bgcolor e text continuam atributo: o CSS do remetente ganha deles, como no original.
    expect(corpo.getAttribute('bgcolor')).toBe('#f3f2ef');
    expect(corpo.getAttribute('text')).toBe('#333333');
    expect(corpo.style.margin).toBe('0px');
    expect(corpo.style.fontFamily).toBe('Arial');
    expect(corpo.querySelector('table.coluna')?.textContent).toContain(
      'Convite'
    );
  });

  it('nada do <head> do remetente sobra: refresh, base, folha de fora', () => {
    const doc = ler(documentoIsolado(CONVITE));
    expect(doc.querySelector('meta[http-equiv="refresh"]')).toBeNull();
    expect(doc.querySelector('link')).toBeNull();
    expect(doc.querySelectorAll('base')).toHaveLength(1);
    expect(doc.querySelector('base').getAttribute('href')).toBeNull();
    expect(doc.querySelector('base').getAttribute('target')).toBe('_blank');
  });

  it('a CSP bloqueia script, formulário, moldura, objeto e conexão; tema claro', () => {
    const doc = ler(documentoIsolado('<p>oi</p>'));
    const csp = doc
      .querySelector('meta[http-equiv="Content-Security-Policy"]')
      .getAttribute('content');
    [
      "script-src 'none'",
      "form-action 'none'",
      "frame-src 'none'",
      "object-src 'none'",
      "connect-src 'none'",
      "default-src 'none'",
    ].forEach(regra => expect(csp).toContain(regra));
    expect(csp).toContain('img-src http: https: data:');
    expect(
      doc.querySelector('meta[name="color-scheme"]').getAttribute('content')
    ).toBe('light');
  });

  it('script, onerror, formulário, moldura e svg não sobrevivem', () => {
    const srcdoc = documentoIsolado(`<html><body>
      <script>window.x=1</script>
      <img src="https://ok.test/a.png" onerror="window.x=2" onload="window.x=3">
      <form action="https://mau.test"><input name="senha"><button>Enviar</button></form>
      <iframe src="https://mau.test"></iframe>
      <object data="https://mau.test/x.swf"></object><embed src="https://mau.test/y">
      <svg><script>window.x=4</script></svg>
      <div onclick="window.x=5" style="position:fixed;top:0">texto</div>
    </body></html>`);
    const doc = ler(srcdoc);
    expect(
      doc.querySelector('script, form, input, iframe, object, embed, svg')
    ).toBeNull();
    expect(srcdoc).not.toContain('onerror');
    expect(srcdoc).not.toContain('onload');
    expect(srcdoc).not.toContain('onclick');
    expect(srcdoc).not.toContain('window.x');
    expect(srcdoc).not.toContain('position');
    expect(doc.querySelector('img').getAttribute('src')).toBe(
      'https://ok.test/a.png'
    );
  });

  it('link só web, e-mail e telefone, sempre em aba nova sem referência', () => {
    const doc = ler(
      documentoIsolado(`<body>
        <a id="a" href="javascript:alert(1)">a</a>
        <a id="b" href="JaVaScRiPt:alert(1)">b</a>
        <a id="c" href="data:text/html,<script>1</script>">c</a>
        <a id="d" href="vbscript:x">d</a>
        <a id="e" href="https://site.test/x">e</a>
        <a id="f" href="mailto:a@b.test">f</a>
        <a id="g" href="tel:+5511999999999">g</a>
        <a id="h" href="#ancora">h</a>
        <img id="i" src="javascript:alert(1)">
        <img id="j" src="data:image/png;base64,AAAA">
      </body>`)
    );
    const href = seletor => doc.querySelector(seletor).getAttribute('href');
    ['#a', '#b', '#c', '#d', '#h'].forEach(seletor =>
      expect(href(seletor)).toBeNull()
    );
    expect(href('#e')).toBe('https://site.test/x');
    expect(href('#f')).toBe('mailto:a@b.test');
    expect(href('#g')).toBe('tel:+5511999999999');
    doc.querySelectorAll('a').forEach(link => {
      expect(link.getAttribute('target')).toBe('_blank');
      expect(link.getAttribute('rel')).toBe('noopener noreferrer');
    });
    expect(doc.querySelector('#i').getAttribute('src')).toBeNull();
    expect(doc.querySelector('#j').getAttribute('src')).toBe(
      'data:image/png;base64,AAAA'
    );
  });

  it('sem rastreio: o pixel e o clique das Campanhas saem, o resto fica', () => {
    const doc = ler(
      documentoIsolado(
        `<body><img id="p" src="https://chat.exemplo.com/email_campaigns/t/o/abc">
         <img id="l" src="https://site.com/logo.png">
         <a id="c" href="https://chat.exemplo.com/email_campaigns/t/c/abc">x</a></body>`,
        { semRastreio }
      )
    );
    expect(doc.querySelector('#p').getAttribute('src')).toBeNull();
    expect(doc.querySelector('#l').getAttribute('src')).toBe(
      'https://site.com/logo.png'
    );
    expect(doc.querySelector('#c').getAttribute('href')).toBeNull();
  });

  it('CSS com "<" escapado não fecha o <style> nem injeta marcação', () => {
    const srcdoc = documentoIsolado(`<html><head><style>
      p{font-family:"\\3c /style\\3e \\3c meta http-equiv=refresh content=0;url=https://mau.test/\\3e \\3c img src=x onerror=alert(1)\\3e "}
      .ok{color:#123456}
    </style></head><body><p class="ok">x</p></body></html>`);
    const doc = ler(srcdoc);
    expect(doc.querySelector('meta[http-equiv="refresh"]')).toBeNull();
    expect(doc.querySelector('[onerror]')).toBeNull();
    expect(srcdoc).not.toContain('onerror');
    expect(srcdoc).not.toContain('mau.test');
    expect(doc.querySelector('p.ok')).not.toBeNull();
  });

  it('url() com "%" quebrado não derruba o e-mail; o resto do CSS fica', () => {
    const html = `<html><head><style>.a{background:url(https://x.test/%zz.png)} .b{color:#654321}</style></head>
      <body><div class="b" style="background:url(%E0%A4%A)">texto</div></body></html>`;
    let srcdoc = '';
    expect(() => {
      srcdoc = documentoIsolado(html, { semRastreio });
    }).not.toThrow();
    const doc = ler(srcdoc);
    expect(doc.body.textContent).toContain('texto');
    expect(srcdoc).toContain('.b');
    expect(doc.querySelector('.b').getAttribute('style')).toBeNull();
  });

  it('imagem só com endereço completo web ou embutida: relativa não pede nada ao painel', () => {
    const doc = ler(
      documentoIsolado(`<body bgcolor="#fff" background="/rails/fundo.png">
        <img id="r" src="/rails/active_storage/x.png"><img id="w" src="https://ok.test/a.png"></body>`)
    );
    expect(doc.querySelector('#r').getAttribute('src')).toBeNull();
    expect(doc.querySelector('#w').getAttribute('src')).toBe(
      'https://ok.test/a.png'
    );
    expect(doc.body.getAttribute('background')).toBeNull();
  });

  it('a CSP também proíbe <base> com endereço', () => {
    const csp = ler(documentoIsolado('<p>x</p>'))
      .querySelector('meta[http-equiv="Content-Security-Policy"]')
      .getAttribute('content');
    expect(csp).toContain("base-uri 'none'");
  });

  it('a moldura nunca tem allow-scripts', () => {
    expect(SANDBOX_DO_EMAIL.split(' ')).not.toContain('allow-scripts');
    expect(SANDBOX_DO_EMAIL.split(' ')).toEqual([
      'allow-same-origin',
      'allow-popups',
      'allow-popups-to-escape-sandbox',
    ]);
  });

  it('Imprimir leva o corpo limpo, com o estilo do <body>, sem o CSS da moldura', () => {
    const impresso = corpoParaImprimir(documentoIsolado(CONVITE));
    const div = ler(impresso).body.firstElementChild;
    expect(div.style.backgroundColor).toBe('rgb(243, 242, 239)');
    expect(div.querySelector('table.coluna')).not.toBeNull();
    expect(impresso).not.toContain('overflow-y');
  });
});

describe('citação no documento inteiro (#1884)', () => {
  it('tira a citação do Gmail sem perder o <head> e o <body>', () => {
    const { html, achou } =
      citacaoDoDocumento(`<html><head><style>.a{color:red}</style></head>
      <body bgcolor="#eeeeee"><div class="a">Resposta</div>
      <div class="gmail_quote">Em seg, Fulano escreveu: antigo</div></body></html>`);
    expect(achou).toBe(true);
    const doc = ler(html);
    expect(doc.head.querySelector('style').textContent).toContain('.a');
    expect(doc.body.getAttribute('bgcolor')).toBe('#eeeeee');
    expect(doc.body.textContent).toContain('Resposta');
    expect(doc.body.textContent).not.toContain('antigo');
  });

  it('a do iPhone (blockquote type=cite) só no cartão novo; o balão antigo segue o Chatwoot', () => {
    const iphone = `<html><body><div>Oi</div><blockquote type="cite">antigo</blockquote><div>Assinatura</div></body></html>`;
    const novo = citacaoDoDocumento(iphone);
    expect(novo.achou).toBe(true);
    expect(ler(novo.html).body.textContent).not.toContain('antigo');
    expect(ler(novo.html).body.textContent).toContain('Assinatura');
    const antigo = citacaoDoDocumento(iphone, { leitores: false });
    expect(antigo.achou).toBe(false);
    expect(ler(antigo.html).body.textContent).toContain('antigo');
  });

  it('e-mail sem citação: nada muda e não acha nada', () => {
    const { html, achou } = citacaoDoDocumento(
      '<html><body><p>Só isto</p><p>Assinatura com <img src="https://x.test/l.png"></p></body></html>'
    );
    expect(achou).toBe(false);
    const doc = ler(html);
    expect(doc.body.querySelectorAll('p')).toHaveLength(2);
    expect(doc.body.querySelector('img')).not.toBeNull();
  });
});

describe('CorpoIsoladoDoEmail (#1884)', () => {
  it('moldura sandbox sem allow-scripts, com título e o documento isolado', () => {
    const wrapper = mount(CorpoIsoladoDoEmail, {
      props: { html: CONVITE, titulo: 'Mensagem de Fulano' },
    });
    const moldura = wrapper.find('iframe');
    expect(moldura.attributes('sandbox')).toBe(SANDBOX_DO_EMAIL);
    expect(moldura.attributes('sandbox')).not.toContain('allow-scripts');
    expect(moldura.attributes('title')).toBe('Mensagem de Fulano');
    expect(moldura.attributes('referrerpolicy')).toBe('no-referrer');
    expect(moldura.attributes('srcdoc')).toContain('Content-Security-Policy');
    expect(moldura.attributes('srcdoc')).toContain('Convite');
    expect(moldura.attributes('srcdoc')).not.toContain('mau.test');
    expect(wrapper.vm.htmlParaImprimir()).toContain('Convite');
  });
});
