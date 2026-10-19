import { sanitizeTextForRender } from '@chatwoot/utils';
import { EmailQuoteExtractor } from 'dashboard/helper/emailQuoteExtractor.js';
import { semCitacaoDosLeitores } from '../email/citacaoDosLeitores';

// O que o cartão do e-mail mostra: o nosso corte e, depois, o extrator do Chatwoot.
const corpoVisivel = html => {
  const { html: semCitacao, achou } = semCitacaoDosLeitores(html);
  const div = document.createElement('div');
  div.innerHTML = EmailQuoteExtractor.extractQuotes(semCitacao);
  return { texto: div.textContent, achou };
};

// Caso real da conversa 320 (#1869): resposta pelo Mail do iPhone, sem <blockquote>.
const IPHONE_TEXTO = [
  'RV',
  '',
  '',
  'Enviado do meu iPhone 14 Pro',
  '',
  'Em 19 de out. de 2026, à(s) 07:51, Fulano <fulano@ex.com> escreveu:',
  '',
  '> Segue a proposta revisada.',
  '>',
  '>> Em 18 de out. de 2026, Ana escreveu:',
  '>> Pode mandar de novo?',
].join('\n');

const IPHONE_HTML =
  '<html><head><meta http-equiv="content-type" content="text/html; charset=utf-8"></head>' +
  '<body dir="auto">RV<br><br><br><div dir="ltr">Enviado do meu iPhone 14 Pro</div>' +
  '<div dir="ltr"><br><div dir="ltr">Em 19 de out. de 2026, à(s) 07:51, Fulano &lt;fulano@ex.com&gt; escreveu:</div>' +
  '<div dir="ltr"><br></div><div dir="ltr">&gt; Segue a proposta revisada.<br>&gt;<br>' +
  '&gt;&gt; Em 18 de out. de 2026, Ana escreveu:<br>&gt;&gt; Pode mandar de novo?</div></div></body></html>';

describe('citação com ">" no fim do e-mail (#1869)', () => {
  it('iPhone pt-BR em texto puro: recolhe o cabeçalho e as linhas > e >>', () => {
    const { texto, achou } = corpoVisivel(sanitizeTextForRender(IPHONE_TEXTO));
    expect(achou).toBe(true);
    expect(texto).toContain('RV');
    expect(texto).toContain('Enviado do meu iPhone 14 Pro');
    expect(texto).not.toContain('escreveu');
    expect(texto).not.toContain('Segue a proposta');
    expect(texto).not.toContain('Pode mandar');
  });

  it('iPhone pt-BR em HTML com &gt; e sem blockquote', () => {
    const { texto, achou } = corpoVisivel(IPHONE_HTML);
    expect(achou).toBe(true);
    expect(texto).toContain('Enviado do meu iPhone 14 Pro');
    expect(texto).not.toContain('escreveu');
    expect(texto).not.toContain('Segue a proposta');
  });

  it('a citação aberta continua com o histórico inteiro (o corte não mexe no original)', () => {
    const { html } = semCitacaoDosLeitores(IPHONE_HTML);
    expect(html).not.toContain('Pode mandar');
    expect(IPHONE_HTML).toContain('Pode mandar');
  });

  it('Gmail em inglês, texto puro: "On ... wrote:" e as linhas >', () => {
    const texto = [
      'Thanks, works for me.',
      '',
      'Best,',
      'John',
      '',
      'On Mon, Oct 19, 2026 at 7:51 AM Fulano <fulano@ex.com> wrote:',
      '',
      '> Can we meet on Friday?',
      '> ',
      '> Fulano',
    ].join('\n');
    const visto = corpoVisivel(sanitizeTextForRender(texto));
    expect(visto.achou).toBe(true);
    expect(visto.texto).toContain('Thanks, works for me.');
    expect(visto.texto).toContain('John');
    expect(visto.texto).not.toContain('wrote');
    expect(visto.texto).not.toContain('Friday');
  });

  it('sem cabeçalho: só as linhas > do fim saem', () => {
    const visto = corpoVisivel(
      sanitizeTextForRender('Combinado.\n\n> Pode ser amanhã?\n> Abraço')
    );
    expect(visto.achou).toBe(true);
    expect(visto.texto).toContain('Combinado.');
    expect(visto.texto).not.toContain('amanhã');
  });

  it('a linha acima sem ":" não é cabeçalho e fica', () => {
    const { html } = semCitacaoDosLeitores(
      sanitizeTextForRender('Veja abaixo\n> trecho antigo')
    );
    expect(html).toContain('Veja abaixo');
    expect(html).not.toContain('trecho antigo');
  });

  it('citação no meio, com resposta embaixo, não some', () => {
    const texto = [
      'Respondendo por partes:',
      '',
      '> Qual o prazo?',
      '',
      'Sexta-feira.',
      '',
      '> E o valor?',
      '',
      'R$ 1.200.',
    ].join('\n');
    const visto = corpoVisivel(sanitizeTextForRender(texto));
    expect(visto.achou).toBe(false);
    expect(visto.texto).toContain('Qual o prazo?');
    expect(visto.texto).toContain('E o valor?');
    expect(visto.texto).toContain('R$ 1.200.');
  });

  it('e-mail só com citação: não esconde tudo', () => {
    const texto = 'Em 19 de out., Ana escreveu:\n\n> oi\n> tudo bem?';
    const visto = corpoVisivel(sanitizeTextForRender(texto));
    expect(visto.achou).toBe(false);
    expect(visto.texto).toContain('tudo bem?');
  });

  it('só a assinatura acima da citação: mostra a assinatura', () => {
    const visto = corpoVisivel(
      sanitizeTextForRender(
        'Enviado do meu iPhone\n\nEm 19 de out., Ana escreveu:\n\n> oi'
      )
    );
    expect(visto.achou).toBe(true);
    expect(visto.texto).toContain('Enviado do meu iPhone');
    expect(visto.texto).not.toContain('Ana escreveu');
  });

  it('não corta foto que vem depois do texto e antes de nada citado', () => {
    const { html, achou } = semCitacaoDosLeitores(
      '<p>Segue a foto</p><p><img src="https://ex.com/a.png"></p>'
    );
    expect(achou).toBe(false);
    expect(html).toContain('<img');
  });
});
