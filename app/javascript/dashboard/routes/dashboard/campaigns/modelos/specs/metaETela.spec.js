import {
  conteudoDaMeta,
  lerCorpo,
  modeloDaMeta,
  recusaDe,
} from '../api/daMeta';
import {
  corpoParaAlterar,
  corpoParaCriar,
  nomeParaWhatsapp,
} from '../helpers/paraMeta';
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
      terminaEm: '',
      link: 'https://h.com/o',
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

  it('on change sends no name or language, and the type only when it changed', () => {
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
    expect(corpo.components[0].example.header_handle).toEqual(['4::old']);
    expect(corpoParaAlterar(rascunho, { tipo: 'divulgacao' }).category).toBe(
      'UTILITY'
    );
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
