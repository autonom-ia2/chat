import { formatarWhatsapp, lerFormatacao } from '../formatacaoWhatsapp';
import { FORMATOS, formatoDoTexto } from '../useFormatoDoWhatsapp';
import { MESSAGE_TYPES } from '../../message/constants';

const p = html => `<p>${html}</p>`;

describe('formatarWhatsapp (#1732)', () => {
  it.each([
    ['*negrito*', '<strong>negrito</strong>'],
    ['_itálico_', '<em>itálico</em>'],
    ['~riscado~', '<s>riscado</s>'],
    ['`código`', '<code>código</code>'],
    ['```mono```', '<span class="font-mono whitespace-pre-wrap">mono</span>'],
    ['a *b* c', 'a <strong>b</strong> c'],
    ['*_os dois_*', '<strong><em>os dois</em></strong>'],
    ['_*os dois*_', '<em><strong>os dois</strong></em>'],
    ['*~três~ _juntos_*', '<strong><s>três</s> <em>juntos</em></strong>'],
    ['(*entre parênteses*)', '(<strong>entre parênteses</strong>)'],
    ['*negrito*, depois', '<strong>negrito</strong>, depois'],
    ['*😀 emoji*', '<strong>😀 emoji</strong>'],
  ])('%s', (entrada, html) => {
    expect(formatarWhatsapp(entrada)).toBe(p(html));
  });

  it.each([
    ['2*3*4', 'colado em número não abre'],
    ['nome_do_arquivo_final', 'colado em letra não abre'],
    ['a* b*', 'abre com espaço depois'],
    ['*a *', 'fecha com espaço antes'],
    ['**', 'sem nada dentro'],
    ['* item solto', 'sem fechamento'],
    ['~', 'marcador sozinho'],
  ])('fica como texto: %s (%s)', entrada => {
    const nos = lerFormatacao(entrada).flatMap(bloco => bloco.linhas.flat());
    const tipos = nos.flatMap(no => (no.nos ? no.nos : [no])).map(n => n.tipo);
    expect(tipos.every(tipo => tipo === 'texto')).toBe(true);
  });

  it.each([
    ['# título', '# título'],
    ['## sub', '## sub'],
    ['#hashtag *a*', '#hashtag <strong>a</strong>'],
    [
      '[t](https://x.com)',
      '[t](<a href="https://x.com" class="link" rel="noreferrer noopener nofollow" target="_blank">https://x.com</a>)',
    ],
    ['1) não é lista', '1) não é lista'],
    ['a * b * c', 'a * b * c'],
    ['_a_b', '_a_b'],
    ['*a*b', '*a*b'],
    ['_a_.', '<em>a</em>.'],
    ['~a~!', '<s>a</s>!'],
    ['`a b` e `c`', '<code>a b</code> e <code>c</code>'],
    ['``', '``'],
    ['``x``', '``x``'],
    ['*a* *b*', '<strong>a</strong> <strong>b</strong>'],
    ['ç*ã*o', 'ç*ã*o'],
  ])('borda do app: %s', (entrada, html) => {
    expect(formatarWhatsapp(entrada)).toBe(p(html));
  });

  it('texto vazio ou nulo não quebra', () => {
    expect(formatarWhatsapp('')).toBe(p(''));
    expect(formatarWhatsapp(null)).toBe(p(''));
  });

  it('não atravessa a quebra de linha', () => {
    expect(formatarWhatsapp('*a\nb*')).toBe(p('*a<br>b*'));
  });

  it('``` atravessa linhas e não formata o que tem dentro', () => {
    expect(formatarWhatsapp('```linha *1*\nlinha 2```')).toBe(
      p('<span class="font-mono whitespace-pre-wrap">linha *1*\nlinha 2</span>')
    );
  });

  it('dentro de ` nada é formatado', () => {
    expect(formatarWhatsapp('`*x*`')).toBe(p('<code>*x*</code>'));
  });

  it('listas com -, * e número', () => {
    const html = formatarWhatsapp('- um\n* dois\n1. três\n10. *dez*');
    expect(html).toBe(
      '<div class="my-1">' +
        '<div class="flex gap-2"><span class="shrink-0">•</span><span>um</span></div>' +
        '<div class="flex gap-2"><span class="shrink-0">•</span><span>dois</span></div>' +
        '<div class="flex gap-2"><span class="shrink-0">1.</span><span>três</span></div>' +
        '<div class="flex gap-2"><span class="shrink-0">10.</span><span><strong>dez</strong></span></div>' +
        '</div>'
    );
  });

  it('citação agrupa as linhas seguidas e separa do resto', () => {
    expect(formatarWhatsapp('> a\n> _b_\nfim')).toBe(
      '<blockquote class="not-italic my-1">a<br><em>b</em></blockquote>' +
        p('fim')
    );
  });

  it('sem espaço depois do marcador de bloco, é texto', () => {
    expect(formatarWhatsapp('>a\n-b\n1.c')).toBe(p('&gt;a<br>-b<br>1.c'));
  });

  it('guarda as linhas em branco', () => {
    expect(formatarWhatsapp('a\n\nb')).toBe(p('a<br><br>b'));
  });

  it('escapa HTML do cliente', () => {
    expect(formatarWhatsapp('<img src=x onerror=alert(1)> *"a"&*')).toBe(
      p(
        '&lt;img src=x onerror=alert(1)&gt; <strong>&quot;a&quot;&amp;</strong>'
      )
    );
  });

  it('link vira link e o _ do endereço não formata', () => {
    expect(formatarWhatsapp('veja https://exemplo.com/_a_ ok')).toBe(
      p(
        'veja <a href="https://exemplo.com/_a_" class="link" rel="noreferrer noopener nofollow" target="_blank">https://exemplo.com/_a_</a> ok'
      )
    );
  });

  it('link dentro de negrito', () => {
    expect(formatarWhatsapp('*site.com.br*')).toBe(
      p(
        '<strong><a href="http://site.com.br" class="link" rel="noreferrer noopener nofollow" target="_blank">site.com.br</a></strong>'
      )
    );
  });

  it.each([
    ['_https://x.com_', '<em><a href="https://x.com">https://x.com</a></em>'],
    [
      '*https://x.com/a*',
      '<strong><a href="https://x.com/a">https://x.com/a</a></strong>',
    ],
    ['~www.x.com~', '<s><a href="http://www.x.com">www.x.com</a></s>'],
    [
      'veja (https://x.com).',
      'veja (<a href="https://x.com">https://x.com</a>).',
    ],
  ])('marcador em volta do link: %s', (entrada, esperado) => {
    const html = formatarWhatsapp(entrada).replaceAll(
      ' class="link" rel="noreferrer noopener nofollow" target="_blank"',
      ''
    );
    expect(html).toBe(p(esperado));
  });

  it('não cria link javascript:', () => {
    // eslint-disable-next-line no-script-url
    expect(formatarWhatsapp('javascript:alert(1)')).not.toContain('<a');
  });
});

describe('formatarWhatsapp tolerante, para robô e IA (#1732)', () => {
  const tolerante = texto => formatarWhatsapp(texto, { tolerante: true });

  it.each([
    ['**negrito**', '<strong>negrito</strong>'],
    ['*negrito*', '<strong>negrito</strong>'],
    ['~~riscado~~', '<s>riscado</s>'],
    ['~riscado~', '<s>riscado</s>'],
    ['_itálico_', '<em>itálico</em>'],
    ['**_os dois_**', '<strong><em>os dois</em></strong>'],
    [
      'Seu **pedido**: *ok*',
      'Seu <strong>pedido</strong>: <strong>ok</strong>',
    ],
    ['2*3*4', '2*3*4'],
    ['***tudo***', '<strong>tudo</strong>'],
    ['**Pedido *urgente***', '<strong>Pedido urgente</strong>'],
    ['*a _b_ c*', '<strong>a <em>b</em> c</strong>'],
    // Grudado em letra: o envio manda como foi escrito, e a tela também.
    ['a**b**c', 'a**b**c'],
    // ** com espaço depois: o envio manda cru; o leitor abre no 2º asterisco (borda,
    // a conferir no aparelho).
    ['** solto**', '<strong>* solto*</strong>'],
  ])('%s', (entrada, html) => {
    expect(tolerante(entrada)).toBe(p(html));
  });

  it.each(['**x**', '~~x~~', '__x__', '***x***', '*a**', 'a **b** c'])(
    'sem a opção, %s fica como texto (o app não lê markdown)',
    entrada => {
      expect(formatarWhatsapp(entrada)).toBe(p(entrada));
    }
  );
});

describe('formatoDoTexto (#1732)', () => {
  const { INCOMING, OUTGOING, ACTIVITY, TEMPLATE } = MESSAGE_TYPES;
  const { APP, ROBO } = FORMATOS;

  it.each([
    ['recebida do cliente', { messageType: INCOMING }, APP],
    [
      'eco do celular',
      { messageType: OUTGOING, contentAttributes: { externalEcho: true } },
      APP,
    ],
    [
      'modelo da Meta',
      {
        messageType: OUTGOING,
        additionalAttributes: { templateParams: { name: 'boas_vindas' } },
      },
      APP,
    ],
    [
      'robô (sender.type)',
      { messageType: OUTGOING, tipoDoRemetente: 'agent_bot' },
      ROBO,
    ],
    [
      'robô (sender_type cru)',
      { messageType: OUTGOING, tipoDoRemetente: 'AgentBot' },
      ROBO,
    ],
    [
      'assistente',
      { messageType: OUTGOING, tipoDoRemetente: 'captain_assistant' },
      ROBO,
    ],
    [
      'follow-up em nome de pessoa',
      {
        messageType: OUTGOING,
        tipoDoRemetente: 'user',
        contentAttributes: { crmFollowUpId: 7 },
      },
      ROBO,
    ],
    [
      'regra de automação',
      { messageType: OUTGOING, contentAttributes: { automationRuleId: 1 } },
      ROBO,
    ],
    [
      'convite do Agendamento',
      { messageType: OUTGOING, contentAttributes: { crmBookingInviteId: 2 } },
      ROBO,
    ],
    [
      'aviso do Agendamento',
      { messageType: OUTGOING, contentAttributes: { crmBookingNotice: 'x' } },
      ROBO,
    ],
    [
      'campanha',
      { messageType: OUTGOING, additionalAttributes: { campaignId: 3 } },
      ROBO,
    ],
    [
      'campanha da API do WhatsApp',
      {
        messageType: OUTGOING,
        additionalAttributes: { whatsappApiCampaignId: 4 },
      },
      ROBO,
    ],
    [
      'pessoa no painel (markdown)',
      { messageType: OUTGOING, tipoDoRemetente: 'user' },
      null,
    ],
    [
      'nota privada do robô',
      { messageType: OUTGOING, privada: true, tipoDoRemetente: 'agent_bot' },
      null,
    ],
    ['nota privada recebida', { messageType: INCOMING, privada: true }, null],
    ['atividade', { messageType: ACTIVITY }, null],
    ['template do Chatwoot', { messageType: TEMPLATE }, null],
  ])('%s', (_, mensagem, esperado) => {
    expect(formatoDoTexto(mensagem)).toBe(esperado);
  });
});
