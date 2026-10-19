import { mount } from '@vue/test-utils';
import {
  SANDBOX_DO_EMAIL,
  citacaoDoDocumento,
  corpoParaImprimir,
  documentoIsolado,
} from '../email/documentoDoEmail';
import { semRastreio } from '../email/dadosDoEmail';
import { htmlComCssSeguro } from '../email/estiloSeguroDoEmail';
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
    expect(csp).toContain('font-src data:;');
    expect(
      doc.querySelector('meta[name="referrer"]').getAttribute('content')
    ).toBe('no-referrer');
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
    // Sai só a declaração com o endereço quebrado; o resto do estilo fica.
    expect(doc.querySelector('.b').getAttribute('style') || '').not.toContain(
      'url('
    );
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

  it('a CSP também proíbe <base> com endereço (base-uri)', () => {
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

  it('a altura da moldura vai no style do <html> (inline !important, acima do CSS do remetente)', () => {
    const doc = ler(
      documentoIsolado(
        '<style>:root:root{height:20000px!important}</style><p>oi</p>'
      )
    );
    expect(doc.documentElement.getAttribute('style')).toContain(
      'height:auto!important'
    );
  });

  it('vh e @media de altura valem para a janela do painel; tema escuro sai', () => {
    const tela = {
      altura: 900,
      largura: 1200,
      combina: condicao => condicao.includes('min-height'),
    };
    const doc = ler(
      documentoIsolado(
        `<html lang="pt-BR" dir="rtl"><head><style>
        body{min-height:100vh}
        @media (min-height: 500px){.a{color:red}}
        @media (max-height: 300px){.b{color:blue}}
        @media (prefers-color-scheme: dark){.c{color:white}}
        @media (prefers-color-scheme: light){.d{color:black}}
        @media (max-width: 480px){.e{width:100%}}
        </style></head><body><p style="height:50vh">x</p></body></html>`,
        { tela }
      )
    );
    const css = [...doc.querySelectorAll('style')]
      .map(estilo => estilo.textContent)
      .join('\n');
    expect(css).toContain('min-height: 900px');
    expect(css).not.toContain('vh');
    expect(css).toContain('.a');
    expect(css).not.toContain('.b');
    expect(css).not.toContain('.c');
    expect(css).toContain('.d');
    expect(css).toContain('max-width: 480px');
    expect(doc.querySelector('p').getAttribute('style')).toContain('450px');
    expect(doc.documentElement.getAttribute('lang')).toBe('pt-BR');
    expect(doc.documentElement.getAttribute('dir')).toBe('rtl');
  });

  it('@media mista: tema e altura decididos aqui, a largura fica com a moldura', () => {
    const tela = {
      altura: 900,
      largura: 1200,
      combina: condicao => condicao.includes('portrait'),
    };
    const doc = ler(
      documentoIsolado(
        `<style>
        @media (max-width: 600px) and (prefers-color-scheme: light){.a{color:red}}
        @media not (prefers-color-scheme: dark){.b{color:blue}}
        @media (max-width: 480px) and (orientation: portrait){.c{color:green}}
        @media (max-width: 480px) and (orientation: landscape){.d{color:gray}}
        </style><p>oi</p>`,
        { tela }
      )
    );
    const todo = [...doc.querySelectorAll('style')]
      .map(estilo => estilo.textContent)
      .join('\n');
    expect(todo).toContain('.a');
    expect(todo).not.toContain('prefers-color-scheme');
    expect(todo).toContain('.b');
    expect(todo).toContain('.c');
    expect(todo).not.toContain('.d');
    expect(todo).not.toContain('orientation');
    expect(todo).toContain('@media (max-width: 600px)');
    expect(todo).toContain('@media (max-width: 480px)');
  });

  it('fórmula (math) vira texto nos dois caminhos; o crash do sanitizador não volta', () => {
    const html = '<p>Área: <math><mi>x</mi><mo>+</mo><mn>1</mn></math> m²</p>';
    expect(ler(documentoIsolado(html)).body.textContent).toContain('x+1');
    const antigo = htmlComCssSeguro(html);
    expect(antigo).not.toContain('<math');
    expect(antigo).toContain('x+1');
  });

  it('Imprimir mantém a imagem embutida (data:image) e tira a relativa', () => {
    const impresso = corpoParaImprimir(
      documentoIsolado(
        '<img id="d" src="data:image/png;base64,iVBORw0KGgo="><p style="background:url(/x)">a</p>'
      )
    );
    expect(ler(impresso).querySelector('img').getAttribute('src')).toContain(
      'data:image/png'
    );
    expect(impresso).not.toContain('url(/x)');
  });

  it('botão, lista e caixa de texto: sai a tag, o texto fica (os dois caminhos)', () => {
    const html = '<p><button>Botão</button><textarea>Nota</textarea></p>';
    const doc = ler(documentoIsolado(html));
    expect(doc.querySelector('button, textarea')).toBeNull();
    expect(doc.body.textContent).toContain('Botão');
    expect(doc.body.textContent).toContain('Nota');
    expect(htmlComCssSeguro(html)).toContain('<button>Botão</button>');
  });

  it('imagem com largura e altura nos atributos guarda a proporção (espaçador 1×20)', () => {
    const doc = ler(
      documentoIsolado(
        '<img id="e" src="https://x.test/e.gif" width="1" height="20">' +
          '<img id="a" src="https://x.test/a.gif" height="20">' +
          '<img id="p" src="https://x.test/p.gif" width="100%" height="20">'
      )
    );
    expect(doc.getElementById('e').getAttribute('style')).toContain(
      'aspect-ratio:1 / 20'
    );
    expect(doc.getElementById('a').getAttribute('style') || '').not.toContain(
      'aspect-ratio'
    );
    expect(doc.getElementById('p').getAttribute('style') || '').not.toContain(
      'aspect-ratio'
    );
    // Só a imagem com proporção ganha height:auto; `width="100%" height="20"` fica 20.
    expect(doc.getElementById('e').hasAttribute('data-proporcao')).toBe(true);
    expect(doc.getElementById('p').hasAttribute('data-proporcao')).toBe(false);
    expect(doc.querySelector('style').textContent).toContain(
      ':where(img[data-proporcao]){height:auto}'
    );
  });

  it('atributos antigos de tabela viram estilo: fundo, altura e nowrap', () => {
    const doc = ler(
      documentoIsolado(
        '<table id="t" height="120" background="https://ok.test/f.png"><tr id="r" height="40">' +
          '<td id="c" nowrap background="/relativo.png">a</td></tr></table>'
      )
    );
    const tabela = doc.getElementById('t').getAttribute('style');
    expect(tabela).toContain('height: 120px');
    expect(tabela).toContain('https://ok.test/f.png');
    expect(doc.getElementById('r').getAttribute('style')).toContain(
      'height: 40px'
    );
    const celula = doc.getElementById('c').getAttribute('style');
    expect(celula).toContain('white-space: nowrap');
    expect(celula).not.toContain('relativo');
  });

  it('Imprimir guarda a proporção da imagem, como na tela', () => {
    const impresso = corpoParaImprimir(
      documentoIsolado(
        '<img src="https://x.test/e.gif" width="1" height="20"><p>a</p>'
      )
    );
    const imagem = ler(impresso).querySelector('img');
    expect(imagem.getAttribute('style')).toContain('aspect-ratio:1 / 20');
    expect(imagem.hasAttribute('data-proporcao')).toBe(true);
  });

  it('endereço relativo no CSS e na tabela não chega ao painel; o de outro host fica', () => {
    const srcdoc = documentoIsolado(
      `<style>.a{background:url(/api/v1/profile)} .b{background:url(https://ok.test/f.png)}</style>
      <table background="/rails/active_storage/x"><tr>
      <td style="background-image:url('/x/y')">a</td>
      <td style="background-image:url(//mau.test/f.png)">b</td></tr></table>`
    );
    expect(srcdoc).not.toContain('/api/v1/profile');
    expect(srcdoc).not.toContain('/rails/active_storage');
    expect(srcdoc).not.toContain('/x/y');
    // `//host` é de outro host (vale como https, como no Gmail), não do painel.
    expect(srcdoc).toContain('https://mau.test/f.png');
    expect(srcdoc).toContain('https://ok.test/f.png');
  });

  it('")" dentro das aspas não devolve o endereço relativo (os dois caminhos)', () => {
    const html = `<style>.a{background:url("/X)y")} @media (max-width:600px){.b{background-image:url("/M)y")}}</style>
      <p class="a" style='background-image:url("/I)z")'>a</p>
      <table background='") ; color:red; x:url("/T'><tr><td>b</td></tr></table>`;
    const srcdoc = documentoIsolado(html);
    ['/X)y', '/M)y', '/I)z', '/T'].forEach(rel =>
      expect(srcdoc).not.toContain(rel)
    );
    const antigo = htmlComCssSeguro(html, { conferirUrls: true });
    ['/X)y', '/M)y', '/I)z'].forEach(rel => expect(antigo).not.toContain(rel));
  });

  it('HTML que derruba a limpeza vira texto: o e-mail não some', () => {
    const erro = vi.spyOn(console, 'error').mockImplementation(() => {});
    const original = window.DOMParser.prototype.parseFromString;
    let chamadas = 0;
    const quebrar = vi
      .spyOn(window.DOMParser.prototype, 'parseFromString')
      .mockImplementation(function ler2(...args) {
        chamadas += 1;
        if (chamadas === 2) throw new Error('quebrou');
        return original.apply(this, args);
      });
    const doc = ler(
      documentoIsolado('<style>p{color:red}</style><p>Olá, cliente</p>')
    );
    quebrar.mockRestore();
    expect(doc.body.textContent).toContain('Olá, cliente');
    expect(doc.body.textContent).not.toContain('color');
    expect(
      doc.querySelector('meta[http-equiv="Content-Security-Policy"]')
    ).not.toBeNull();
    expect(erro).toHaveBeenCalled();
    erro.mockRestore();
  });

  it('svg e math relidos não derrubam o sanitizador: o e-mail abre', () => {
    [
      '<math><mtext><table><mglyph><style><img src=x onerror=alert(1)>',
      '<form><math><mtext></form><form><mglyph><style></math><p>oi</p>',
    ].forEach(ataque => {
      const doc = ler(documentoIsolado(ataque));
      expect(doc.querySelector('math, img[onerror]')).toBeNull();
      expect(() => htmlComCssSeguro(ataque)).not.toThrow();
    });
  });

  it('Imprimir leva o corpo limpo, com o estilo do <body>, sem o CSS da moldura', () => {
    const impresso = corpoParaImprimir(documentoIsolado(CONVITE));
    const div = ler(impresso).body.querySelector('[style]');
    expect(div.style.backgroundColor).toBe('rgb(243, 242, 239)');
    expect(ler(impresso).querySelector('table')).not.toBeNull();
    expect(impresso).not.toContain('overflow-y');
  });

  it('Imprimir: o CSS do remetente fica com escopo e não esconde o cabeçalho', () => {
    const impresso = corpoParaImprimir(
      documentoIsolado(
        '<style>dl, h1 {display:none} body{background:red}</style><p>oi</p>'
      )
    );
    const regras = ler(impresso).querySelector('style').textContent;
    expect(regras).toContain('#email_impresso dl');
    expect(regras).not.toContain('body');
    expect(regras.startsWith('dl')).toBe(false);
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
