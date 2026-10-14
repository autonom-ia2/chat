import {
  conteudoDaMeta,
  lerCorpo,
  modeloDaMeta,
  recusaDe,
} from '../api/daMeta';
import {
  cardMedia,
  corpoParaAlterar,
  corpoParaCriar,
  nomeParaWhatsapp,
  usavelEmCampanha,
} from '../helpers/paraMeta';
import { ajustarEspacosDosCampos, previaCurta } from '../helpers/conteudo';
import { ligacaoDoCatalogo, rotuloDoCampo } from '../helpers/campos';

// Ida e volta entre o modelo da Meta (API de Modelos, #1330) e a tela (#1332).
const GRUPO = { id: 7, conta: { id: 7, nome: 'Hub2you' }, numeros: [7, 8] };

const template = extras => ({
  id: '1001',
  name: 'lembrete_boleto',
  language: 'pt_BR',
  status: 'APPROVED',
  category: 'UTILITY',
  components: [
    {
      type: 'BODY',
      text: 'Olá, {{1}}! O boleto de {{2}} vence em {{3}}.',
      example: { body_text: [['Ana', 'R$ 10,00', '15/10']] },
    },
    { type: 'FOOTER', text: 'Hub2you' },
    {
      type: 'BUTTONS',
      buttons: [{ type: 'URL', text: 'Pagar', url: 'https://h.com/b' }],
    },
  ],
  fields: { 1: 'cliente.primeiro_nome', 2: 'valor' },
  header_media: {},
  ...extras,
});

describe('Meta → tela', () => {
  it('reads the body into pieces, with the profile fields and the Meta examples', () => {
    const { conteudo, campos } = conteudoDaMeta(template());

    expect(conteudo.texto).toEqual([
      { t: 'texto', v: 'Olá, ' },
      { t: 'campo', v: 'nome_cliente' },
      { t: 'texto', v: '! O boleto de ' },
      { t: 'campo', v: 'valor' },
      { t: 'texto', v: ' vence em ' },
      { t: 'campo', v: 'variavel_3' },
      { t: 'texto', v: '.' },
    ]);
    expect(campos).toEqual({ 1: 'nome_cliente', 2: 'valor', 3: 'variavel_3' });
    expect(conteudo.exemplos).toEqual({
      nome_cliente: 'Ana',
      valor: 'R$ 10,00',
      variavel_3: '15/10',
    });
    expect(conteudo.rodape).toBe('Hub2you');
    expect(conteudo.botoes).toEqual([
      { tipo: 'site', texto: 'Pagar', valor: 'https://h.com/b' },
    ]);
  });

  it('keeps text without braces and a lone {{ as text', () => {
    expect(lerCorpo('Oi {{ sem fim', () => 'x')).toEqual([
      { t: 'texto', v: 'Oi {{ sem fim' },
    ]);
  });

  // #1334: o arquivo aprovado de cada cartão vem do perfil, na posição do cartão.
  it('keeps the saved file of each carousel card in its position', () => {
    const modelo = modeloDaMeta(
      template({ card_media: [{ card_index: 1, file_name: 'b.jpg' }] }),
      GRUPO
    );
    expect(modelo.cartoesGuardados).toEqual([undefined, { nome: 'b.jpg' }]);
  });

  // #1465: o arquivo do topo guardado de fato no perfil (não o nome solto do header_media).
  it('keeps the saved header file, or null when there is none', () => {
    expect(
      modeloDaMeta(
        template({
          header_file_name: 'topo.png',
          header_file_preview_url: 'https://s/topo.png',
        }),
        GRUPO
      ).topoGuardado
    ).toEqual({ nome: 'topo.png', url: 'https://s/topo.png' });
    expect(
      modeloDaMeta(template({ header_file_name: 'a.pdf' }), GRUPO).topoGuardado
    ).toEqual({ nome: 'a.pdf', url: '' });
    expect(modeloDaMeta(template({}), GRUPO).topoGuardado).toBeNull();
  });

  it('builds the screen model with what Meta says and null for what it does not', () => {
    const modelo = modeloDaMeta(
      template({
        status: 'PAUSED',
        category: 'MARKETING',
        previous_category: 'UTILITY',
        friendly_name: 'Lembrete do boleto',
        system_owner: 'agendamento',
      }),
      { ...GRUPO, envios: { lembrete_boleto: 12 } }
    );

    expect(modelo).toMatchObject({
      id: '1001',
      nome: 'Lembrete do boleto',
      nomeNoWhatsapp: 'lembrete_boleto',
      situacao: 'pausado',
      tipo: 'divulgacao',
      tipoMudouPeloWhatsapp: true,
      sistema: true,
      conta: 7,
      caixa: 7,
      numeros: [7, 8],
      pausa: { desde: null },
      enviosNoMes: 12,
      enviadoEm: null,
      edicoes: { restantesNoMes: null, liberadaEm: null },
    });
    expect(modelo.template.id).toBe('1001');
  });

  it('reads carousel, limited-time offer and verification code', () => {
    const carrossel = conteudoDaMeta({
      category: 'MARKETING',
      components: [
        { type: 'BODY', text: 'Novidades' },
        {
          type: 'CAROUSEL',
          cards: [
            {
              components: [
                { type: 'HEADER', format: 'VIDEO' },
                { type: 'BODY', text: 'Cartão' },
                {
                  type: 'BUTTONS',
                  buttons: [{ type: 'QUICK_REPLY', text: 'Quero' }],
                },
              ],
            },
          ],
        },
      ],
    }).conteudo;
    expect(carrossel.formato).toBe('carrossel');
    expect(carrossel.cartoes[0]).toMatchObject({
      midia: 'video',
      texto: 'Cartão',
    });

    const oferta = conteudoDaMeta({
      category: 'MARKETING',
      components: [
        { type: 'LIMITED_TIME_OFFER', limited_time_offer: { text: 'Só hoje' } },
        { type: 'BODY', text: 'Corre' },
        {
          type: 'BUTTONS',
          buttons: [
            { type: 'COPY_CODE', example: 'HUB30' },
            { type: 'URL', text: 'Ver', url: 'https://h.com/o' },
          ],
        },
      ],
    }).conteudo;
    expect(oferta.oferta).toEqual({
      titulo: 'Só hoje',
      link: 'https://h.com/o',
      botao: 'Ver',
      cupom: 'HUB30',
    });

    const codigo = conteudoDaMeta({
      category: 'AUTHENTICATION',
      components: [
        { type: 'BODY', add_security_recommendation: true },
        { type: 'FOOTER', code_expiration_minutes: 5 },
        { type: 'BUTTONS', buttons: [{ type: 'OTP', otp_type: 'COPY_CODE' }] },
      ],
    }).conteudo;
    expect(codigo.codigo).toEqual({
      botao: 'copiar',
      validade: 5,
      avisoDeSeguranca: true,
    });
    expect(codigo.texto).toEqual([]);
  });

  it('explains the refusal from the Meta reason or from the text itself', () => {
    const conteudo = conteudoDaMeta(
      template({
        components: [
          {
            type: 'BODY',
            text: 'Pague em {{1}}',
            example: { body_text: [['x']] },
          },
        ],
      })
    ).conteudo;
    expect(recusaDe({ rejected_reason: 'INVALID_FORMAT' }, conteudo)).toEqual({
      codigo: 'campo_no_fim',
    });
    expect(
      recusaDe({ rejected_reason: 'INCORRECT_CATEGORY' }, conteudo)
    ).toEqual({
      codigo: 'parece_divulgacao',
    });
    expect(recusaDe({ rejected_reason: 'NONE' }, conteudo)).toEqual({
      codigo: 'outro',
    });
  });
});

describe('situação e o que a tela sabe editar (#1380)', () => {
  it('PAUSED, DISABLED e LIMIT_EXCEEDED têm cada um a sua situação', () => {
    const situacao = status =>
      modeloDaMeta(template({ status }), GRUPO).situacao;
    expect(situacao('PAUSED')).toBe('pausado');
    expect(situacao('DISABLED')).toBe('desativado');
    expect(situacao('LIMIT_EXCEEDED')).toBe('limite');
  });

  it('modelo feito fora com parte que a tela não edita não vira outra coisa', () => {
    const corpo = { type: 'BODY', text: 'Oi.' };
    const editavel = components =>
      modeloDaMeta(template({ components }), GRUPO).editavel;
    expect(editavel([corpo])).toBe(true);
    expect(editavel([{ type: 'HEADER', format: 'LOCATION' }, corpo])).toBe(
      false
    );
    expect(
      editavel([
        corpo,
        { type: 'BUTTONS', buttons: [{ type: 'VOICE_CALL', text: 'Ligar' }] },
      ])
    ).toBe(false);
    const autenticacao = modeloDaMeta(
      template({
        category: 'AUTHENTICATION',
        components: [
          { type: 'BODY' },
          {
            type: 'BUTTONS',
            buttons: [{ type: 'OTP', otp_type: 'ONE_TAP', supported_apps: [] }],
          },
        ],
      }),
      GRUPO
    );
    expect(autenticacao.editavel).toBe(false);
    const catalogo = modeloDaMeta(
      template({
        components: [
          corpo,
          { type: 'BUTTONS', buttons: [{ type: 'CATALOG', text: 'Ver' }] },
        ],
      }),
      GRUPO
    );
    expect(catalogo.editavel).toBe(false);
  });
});

describe('QA na tela (#1380)', () => {
  it('A4: o espaço que o editor põe depois do campo não chega ao cliente', () => {
    const pedacos = [
      { t: 'texto', v: 'Olá, ' },
      { t: 'campo', v: 'nome_cliente' },
      { t: 'texto', v: ' ! Amanhã, dia ' },
      { t: 'campo', v: 'data' },
      { t: 'texto', v: '  e às ' },
      { t: 'campo', v: 'horario' },
      // O navegador digita às vezes o espaço que não quebra (U+00A0).
      { t: 'texto', v: '\u00a0.' },
    ];
    expect(ajustarEspacosDosCampos(pedacos).map(p => p.v)).toEqual([
      'Olá, ',
      'nome_cliente',
      '! Amanhã, dia ',
      'data',
      ' e às ',
      'horario',
      '.',
    ]);
    const corpo = corpoParaCriar({
      nome: 'Aviso',
      tipo: 'aviso',
      conteudo: {
        formato: 'padrao',
        topo: { tipo: 'nenhum' },
        texto: pedacos,
        exemplos: { nome_cliente: 'Ana', data: '15/10', horario: '14h' },
        rodape: '',
        botoes: [],
      },
    });
    expect(corpo.components[0].text).toBe(
      'Olá, {{1}}! Amanhã, dia {{2}} e às {{3}}.'
    );
  });

  it('L2: a prévia da lista corta entre palavras, nunca no meio de um campo', () => {
    const rotulo = campo =>
      ({ data: 'Data e hora do horário' })[campo] || campo;
    const pedacos = [
      { t: 'texto', v: 'Olá! Seu horário está marcado para ' },
      { t: 'campo', v: 'data' },
      { t: 'texto', v: '. Até lá!' },
    ];
    const { pedacos: curtos, cortado } = previaCurta(pedacos, rotulo, 50);
    expect(cortado).toBe(true);
    expect(curtos).toEqual([
      { t: 'texto', v: 'Olá! Seu horário está marcado para ' },
    ]);
    expect(previaCurta(pedacos, rotulo, 200).cortado).toBe(false);
    expect(
      previaCurta([{ t: 'texto', v: 'uma frase bem comprida' }], rotulo, 12)
        .pedacos
    ).toEqual([{ t: 'texto', v: 'uma frase' }]);
  });

  it('A6: modelo com campo que a campanha não preenche não é oferecido para campanha', () => {
    const base = {
      conteudo: { formato: 'padrao', botoes: [] },
      campos: { 1: 'nome_cliente' },
    };
    expect(usavelEmCampanha(base)).toBe(true);
    expect(
      usavelEmCampanha({
        ...base,
        campos: { 1: 'nome_cliente', 2: 'horario.data_hora' },
      })
    ).toBe(false);
  });
});

describe('tela → Meta', () => {
  const rascunho = {
    nome: 'Pesquisa de satisfação',
    tipo: 'aviso',
    numeros: [7],
    conteudo: {
      formato: 'padrao',
      topo: { tipo: 'foto', arquivo: 'capa.jpg', local: 'arquivo_1' },
      texto: [
        { t: 'texto', v: 'Olá, ' },
        { t: 'campo', v: 'nome_cliente' },
        { t: 'texto', v: '! Obrigado pela compra na ' },
        { t: 'campo', v: 'nome_empresa' },
        { t: 'texto', v: '. Nota para ' },
        { t: 'campo', v: 'nome_cliente' },
        { t: 'texto', v: '?' },
      ],
      exemplos: { nome_cliente: 'Ana', nome_empresa: 'Hub2you' },
      rodape: '',
      botoes: [{ tipo: 'resposta', texto: 'Ótimo', valor: '' }],
    },
  };
  const midias = {
    topo: { handle: '4::abc', blob_signed_id: 'sig', file_name: 'capa.jpg' },
  };

  it('numbers each field once, keeps the catalog keys and sends the uploaded file', () => {
    expect(corpoParaCriar(rascunho, { midias })).toEqual({
      name: 'pesquisa_de_satisfacao',
      language: 'pt_BR',
      category: 'UTILITY',
      parameter_format: 'positional',
      components: [
        {
          type: 'HEADER',
          format: 'IMAGE',
          example: { header_handle: ['4::abc'] },
        },
        {
          type: 'BODY',
          text: 'Olá, {{1}}! Obrigado pela compra na {{2}}. Nota para {{1}}?',
          example: { body_text: [['Ana', 'Hub2you']] },
        },
        { type: 'BUTTONS', buttons: [{ type: 'QUICK_REPLY', text: 'Ótimo' }] },
      ],
      friendly_name: 'Pesquisa de satisfação',
      fields: { 1: 'cliente.primeiro_nome', 2: 'minha_empresa.nome' },
      header_media: midias.topo,
    });
  });

  // #1334: a campanha do carrossel usa a mesma mídia aprovada de cada cartão,
  // então o arquivo que subiu agora vai junto, com a posição do cartão.
  it('sends the file of each carousel card that was uploaded now, with its position', () => {
    const cartoes = [
      { handle: '4::c1', blob_signed_id: 'sig1' },
      null,
      { handle: '4::c3', blob_signed_id: 'sig3' },
    ];
    expect(cardMedia(cartoes)).toEqual([
      { card_index: 0, blob_signed_id: 'sig1' },
      { card_index: 2, blob_signed_id: 'sig3' },
    ]);
    expect(cardMedia([])).toEqual([]);
    expect(cardMedia(undefined)).toEqual([]);
  });

  it('on change sends no name, language or type (#1394)', () => {
    const corpo = corpoParaAlterar(
      {
        ...rascunho,
        conteudo: {
          ...rascunho.conteudo,
          topo: { tipo: 'foto', handle: '4::old' },
        },
      },
      { tipo: 'aviso' }
    );
    expect(corpo.name).toBeUndefined();
    expect(corpo.category).toBeUndefined();
    expect(corpo.header_media).toBeUndefined();
    // Sem arquivo novo, o topo vai sem o handle antigo (ele expira): o servidor
    // sobe de novo o arquivo guardado no perfil.
    expect(corpo.components[0]).toEqual({ type: 'HEADER', format: 'IMAGE' });
    // #1394: a Meta não aceita trocar o tipo de um modelo que já existe. A
    // edição nunca manda categoria, nem quando o rascunho chega com outro tipo.
    const outroTipo = corpoParaAlterar(rascunho, {
      tipo: 'divulgacao',
      situacao: 'recusado',
      conteudo: rascunho.conteudo,
    });
    expect(outroTipo.category).toBeUndefined();
    expect(outroTipo.components).toBeDefined();
  });

  it('só o nome amigável mudou: nada de conteúdo vai para a Meta', () => {
    const modelo = { tipo: 'aviso', conteudo: rascunho.conteudo };
    const corpo = corpoParaAlterar({ ...rascunho, nome: 'Outro nome' }, modelo);
    expect(corpo.components).toBeUndefined();
    expect(corpo.category).toBeUndefined();
    expect(corpo.friendly_name).toBe('Outro nome');
  });

  it('manda o idioma do texto (o da tela nos prontos, o do original na cópia)', () => {
    expect(corpoParaCriar(rascunho, { midias }).language).toBe('pt_BR');
    expect(
      corpoParaCriar({ ...rascunho, idioma: 'en' }, { midias }).language
    ).toBe('en');
  });

  it('respostas rápidas vão juntas, antes dos outros botões', () => {
    const botoes = [
      { tipo: 'resposta', texto: 'Sim', valor: '' },
      { tipo: 'site', texto: 'Site', valor: 'https://x.com' },
      { tipo: 'resposta', texto: 'Não', valor: '' },
    ];
    const corpo = corpoParaCriar(
      { ...rascunho, conteudo: { ...rascunho.conteudo, botoes } },
      { midias }
    );
    expect(corpo.components[2].buttons.map(botao => botao.type)).toEqual([
      'QUICK_REPLY',
      'QUICK_REPLY',
      'URL',
    ]);
  });

  it('site com final variável volta com o exemplo (duplicar o modelo de satisfação)', () => {
    const satisfacao = template({
      components: [
        { type: 'BODY', text: 'Como foi o atendimento?' },
        {
          type: 'BUTTONS',
          buttons: [
            {
              type: 'URL',
              text: 'Avaliar',
              url: 'https://app.com/survey/responses/{{1}}',
              example: ['12345'],
            },
          ],
        },
      ],
    });
    const { conteudo } = conteudoDaMeta(satisfacao);
    const corpo = corpoParaCriar({ ...rascunho, conteudo }, {});
    expect(corpo.components[1].buttons[0]).toEqual({
      type: 'URL',
      text: 'Avaliar',
      url: 'https://app.com/survey/responses/{{1}}',
      example: ['12345'],
    });
  });

  it('modelo com variáveis nomeadas continua nomeado ao alterar, nunca vira {{1}}', () => {
    const nomeado = template({
      parameter_format: 'NAMED',
      components: [
        {
          type: 'BODY',
          text: 'Olá {{first_name}}, seu pedido saiu.',
          example: {
            body_text_named_params: [
              { param_name: 'first_name', example: 'Ana' },
            ],
          },
        },
      ],
      fields: {},
    });
    const modelo = modeloDaMeta(nomeado, GRUPO);
    expect(modelo.formatoDosCampos).toBe('named');
    const corpo = corpoParaAlterar(
      {
        ...modelo,
        nome: modelo.nome,
        conteudo: { ...modelo.conteudo, rodape: 'x' },
      },
      modelo
    );
    expect(corpo.components[0]).toEqual({
      type: 'BODY',
      text: 'Olá {{first_name}}, seu pedido saiu.',
      example: {
        body_text_named_params: [{ param_name: 'first_name', example: 'Ana' }],
      },
    });
  });

  it('revisão: campo novo num modelo nomeado ganha nome válido (sem ponto)', () => {
    const modelo = {
      tipo: 'aviso',
      formatoDosCampos: 'named',
      campos: { first_name: 'nome_cliente' },
    };
    const conteudo = {
      ...rascunho.conteudo,
      topo: { tipo: 'nenhum' },
      texto: [
        { t: 'texto', v: 'Oi ' },
        { t: 'campo', v: 'nome_cliente' },
        { t: 'texto', v: ', da ' },
        { t: 'campo', v: 'cliente.primeiro_nome' },
        { t: 'texto', v: '.' },
      ],
    };
    const corpo = corpoParaAlterar({ ...rascunho, conteudo }, modelo);
    expect(corpo.components[0].text).toBe(
      'Oi {{first_name}}, da {{cliente_primeiro_nome}}.'
    );
  });

  it('revisão: texto do botão vai sem espaço nas pontas', () => {
    const botoes = [{ tipo: 'resposta', texto: '  Sim  ', valor: '' }];
    const corpo = corpoParaCriar(
      { ...rascunho, conteudo: { ...rascunho.conteudo, botoes } },
      { midias }
    );
    expect(corpo.components[2].buttons[0].text).toBe('Sim');
  });

  it('revisão: sem mudança no que vai à Meta, nada vai; recusado sempre manda', () => {
    const oferta = {
      formato: 'oferta',
      topo: { tipo: 'nenhum' },
      texto: [{ t: 'texto', v: 'Corre!' }],
      exemplos: {},
      rodape: '',
      botoes: [],
      oferta: {
        titulo: 'Hoje',
        link: 'https://x.com',
        cupom: 'A1',
        botao: 'Ver',
      },
    };
    const modelo = { tipo: 'divulgacao', conteudo: oferta };
    const soData = {
      ...rascunho,
      tipo: 'divulgacao',
      conteudo: { ...oferta, topo: { tipo: 'nenhum', arquivo: '' } },
    };
    expect(corpoParaAlterar(soData, modelo).components).toBeUndefined();
    expect(
      corpoParaAlterar(soData, { ...modelo, situacao: 'recusado' }).components
    ).toBeDefined();
  });

  it('round-trips a created template back to the same screen content', () => {
    const corpo = corpoParaCriar(rascunho, { midias });
    const { conteudo } = conteudoDaMeta({ ...corpo, fields: corpo.fields });
    expect(conteudo.texto).toEqual(rascunho.conteudo.texto);
    expect(conteudo.exemplos).toEqual(rascunho.conteudo.exemplos);
  });

  it('builds the WhatsApp name without regex, accents or symbols', () => {
    expect(nomeParaWhatsapp('Promoção — 30% OFF!')).toBe('promocao_30_off');
    expect(nomeParaWhatsapp('   ')).toBe('');
  });
});

describe('campos', () => {
  it('binds by the catalog only what an audience fills', () => {
    expect(ligacaoDoCatalogo('nome_cliente')).toEqual({
      source: 'field',
      value: 'cliente.primeiro_nome',
      suggested: true,
    });
    expect(ligacaoDoCatalogo('nome_empresa')).toMatchObject({
      value: 'minha_empresa.nome',
    });
    expect(ligacaoDoCatalogo('data')).toBeNull();
    expect(ligacaoDoCatalogo('horario.data_hora')).toBeNull();
  });

  it('names screen fields, catalog keys, audience columns and unnamed variables', () => {
    const t = (chave, params) => (params ? `${chave}:${params.n}` : chave);
    expect(rotuloDoCampo(t, 'data')).toBe(
      'MODELOS_WHATSAPP.CAMPOS.data.ROTULO'
    );
    expect(rotuloDoCampo(t, 'horario.hora')).toBe(
      'MODELOS_WHATSAPP.CATALOGO_DE_CAMPOS.horario.hora'
    );
    expect(rotuloDoCampo(t, 'publico.Vencimento')).toBe('Vencimento');
    expect(rotuloDoCampo(t, 'variavel_3')).toBe(
      'MODELOS_WHATSAPP.CAMPO_SEM_NOME:3'
    );
  });
});
