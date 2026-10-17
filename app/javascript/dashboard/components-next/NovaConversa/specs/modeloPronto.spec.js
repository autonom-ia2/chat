import { shallowMount } from '@vue/test-utils';
import WhatsAppTemplateParser from 'dashboard/components-next/whatsapp/WhatsAppTemplateParser.vue';
import {
  camposDoModelo,
  comCampo,
  modeloCompleto,
  paramsVazios,
  partesDoTexto,
  payloadDoModelo,
  preenchedorProprioCobre,
  previaDoModelo,
  textoDoCorpo,
  trechoDoCampo,
  trechoFalado,
} from '../modeloPronto';

// #1459 — a mensagem pronta em funções puras, e a garantia de que o
// preenchedor próprio envia exatamente o que o antigo enviava.
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: chave => chave }) }));

const base = {
  name: 'boas_vindas',
  category: 'MARKETING',
  language: 'pt_BR',
  namespace: 'ns_1',
};
const umCampo = {
  ...base,
  components: [
    {
      type: 'BODY',
      text: 'Olá, {{1}}! Aqui é da Acme.',
      example: { body_text: [['Mariana']] },
    },
  ],
};
const doisCampos = {
  ...base,
  name: 'lembrete',
  components: [
    { type: 'HEADER', format: 'TEXT', text: 'Lembrete' },
    {
      type: 'BODY',
      text: 'Oi, {{1}}. Seu horário é {{2}}.',
      example: { body_text: [['Mariana', 'sexta, 9h']] },
    },
  ],
};
const nomeado = {
  ...base,
  components: [
    {
      type: 'BODY',
      text: 'Olá, {{nome}}! Seu pedido {{pedido}} saiu.',
      example: {
        body_text_named_params: [
          { param_name: 'nome', example: 'Mariana' },
          { param_name: 'pedido', example: '1234' },
        ],
      },
    },
  ],
};
const semCampo = {
  ...base,
  components: [{ type: 'BODY', text: 'Oi! Podemos ajudar?' }],
};
const comMidia = {
  ...base,
  components: [
    { type: 'HEADER', format: 'IMAGE' },
    { type: 'BODY', text: 'Veja a foto, {{1}}.' },
  ],
};
const comBotao = {
  ...base,
  components: [
    { type: 'BODY', text: 'Acompanhe seu pedido.' },
    {
      type: 'BUTTONS',
      buttons: [{ type: 'URL', url: 'https://acme.com/p/{{1}}' }],
    },
  ],
};

describe('partesDoTexto', () => {
  it('separa o texto dos campos numerados', () => {
    expect(partesDoTexto('Olá, {{1}}! Aqui é da Acme.')).toEqual([
      { texto: 'Olá, ' },
      { campo: '1' },
      { texto: '! Aqui é da Acme.' },
    ]);
  });

  it('aceita campo nomeado, com espaços, e campos colados', () => {
    expect(partesDoTexto('{{ nome }}{{2}} fim')).toEqual([
      { campo: 'nome' },
      { campo: '2' },
      { texto: ' fim' },
    ]);
  });

  it('devolve o texto inteiro quando não há campo', () => {
    expect(partesDoTexto('Oi! Tudo bem?')).toEqual([
      { texto: 'Oi! Tudo bem?' },
    ]);
    expect(partesDoTexto('')).toEqual([]);
    expect(partesDoTexto()).toEqual([]);
  });

  it('não trata como campo uma chave que não fecha', () => {
    expect(partesDoTexto('Oi {{1')).toEqual([
      { texto: 'Oi ' },
      { texto: '{{1' },
    ]);
    expect(partesDoTexto('a }} b')).toEqual([{ texto: 'a }} b' }]);
  });
});

describe('camposDoModelo', () => {
  it('lista os campos do corpo com o exemplo do próprio modelo', () => {
    expect(camposDoModelo(doisCampos)).toEqual([
      {
        parte: 'body',
        chave: '1',
        exemplo: 'Mariana',
        trecho: [
          { texto: 'Oi, ' },
          { campo: '1', alvo: true },
          { texto: '. Seu horário é' },
        ],
      },
      {
        parte: 'body',
        chave: '2',
        exemplo: 'sexta, 9h',
        // As 4 palavras de antes acabam no ponto, que é aparado do começo.
        trecho: [
          { texto: 'Seu horário é ' },
          { campo: '2', alvo: true },
          { texto: '.' },
        ],
      },
    ]);
  });

  it('usa o exemplo dos parâmetros nomeados', () => {
    expect(camposDoModelo(nomeado)).toMatchObject([
      { parte: 'body', chave: 'nome', exemplo: 'Mariana' },
      { parte: 'body', chave: 'pedido', exemplo: '1234' },
    ]);
  });

  it('põe os campos do cabeçalho de texto antes dos do corpo', () => {
    const modelo = {
      ...base,
      components: [
        {
          type: 'HEADER',
          format: 'TEXT',
          text: 'Pedido {{1}}',
          example: { header_text: ['1234'] },
        },
        { type: 'BODY', text: 'Oi, {{1}}.' },
      ],
    };
    expect(camposDoModelo(modelo)).toEqual([
      {
        parte: 'header',
        chave: '1',
        exemplo: '1234',
        trecho: [{ texto: 'Pedido ' }, { campo: '1', alvo: true }],
      },
      {
        parte: 'body',
        chave: '1',
        exemplo: '',
        trecho: [{ texto: 'Oi, ' }, { campo: '1', alvo: true }, { texto: '.' }],
      },
    ]);
  });

  it('fica vazio quando o modelo não tem campo', () => {
    expect(camposDoModelo(semCampo)).toEqual([]);
  });
});

describe('trechoDoCampo', () => {
  const falar = chave => `campo ${chave}`;

  it('mostra o campo do meio com o que vem antes e depois', () => {
    const trecho = trechoDoCampo('Olá, {{1}}! Aqui é da Acme Seguros.', '1');

    expect(trecho).toEqual([
      { texto: 'Olá, ' },
      { campo: '1', alvo: true },
      { texto: '! Aqui é da' },
    ]);
    expect(trechoFalado(trecho, falar)).toBe('Olá, campo 1! Aqui é da');
  });

  it('corta em 4 palavras antes e 3 depois', () => {
    const texto =
      'Um dois três quatro cinco seis {{nome}} sete oito nove dez onze';

    expect(trechoDoCampo(texto, 'nome')).toEqual([
      { texto: 'três quatro cinco seis ' },
      { campo: 'nome', alvo: true },
      { texto: ' sete oito nove' },
    ]);
  });

  it('funciona com o campo no início e no fim da mensagem', () => {
    expect(trechoDoCampo('{{1}}, seu pedido saiu hoje cedo.', '1')).toEqual([
      { campo: '1', alvo: true },
      { texto: ', seu pedido saiu' },
    ]);
    expect(trechoDoCampo('Seu código de acesso é {{1}}', '1')).toEqual([
      { texto: 'código de acesso é ' },
      { campo: '1', alvo: true },
    ]);
  });

  it('mostra o campo vizinho como campo, contando como uma palavra', () => {
    const texto = 'Oi {{1}}{{2}} tudo bem com você hoje?';

    expect(trechoDoCampo(texto, '1')).toEqual([
      { texto: 'Oi ' },
      { campo: '1', alvo: true },
      { campo: '2' },
      { texto: ' tudo bem' },
    ]);
    const segundo = trechoDoCampo(texto, '2');
    expect(segundo).toEqual([
      { texto: 'Oi ' },
      { campo: '1' },
      { campo: '2', alvo: true },
      { texto: ' tudo bem com' },
    ]);
    expect(trechoFalado(segundo, falar)).toBe(
      'Oi campo 1 campo 2 tudo bem com'
    );
  });

  it('junta as linhas e ignora espaços repetidos', () => {
    expect(trechoDoCampo('Olá!\nSeu  horário é {{1}}\nAté logo', '1')).toEqual([
      { texto: 'Olá! Seu horário é ' },
      { campo: '1', alvo: true },
      { texto: ' Até logo' },
    ]);
  });

  it('apara a pontuação solta do começo do trecho, e só do começo', () => {
    const texto = 'Oi, {{1}}. Seu horário é {{2}}. Até lá!';

    expect(trechoDoCampo(texto, '2')).toEqual([
      { texto: 'Seu horário é ' },
      { campo: '2', alvo: true },
      { texto: '. Até lá!' },
    ]);
    expect(trechoDoCampo('Tudo certo?! — Então {{1}}', '1')).toEqual([
      { texto: 'Tudo certo?! — Então ' },
      { campo: '1', alvo: true },
    ]);
    expect(trechoDoCampo('um dois três quatro. — {{1}} fim', '1')).toEqual([
      { texto: 'dois três quatro. — ' },
      { campo: '1', alvo: true },
      { texto: ' fim' },
    ]);
    expect(trechoDoCampo('a b c d ... {{1}}', '1')).toEqual([
      { texto: 'b c d ... ' },
      { campo: '1', alvo: true },
    ]);
    // Um trecho que era só pontuação some, e o campo vira o começo.
    expect(trechoDoCampo('... {{1}} fim', '1')).toEqual([
      { campo: '1', alvo: true },
      { texto: ' fim' },
    ]);
  });

  it('devolve só o campo quando a mensagem é só ele, e nada se não existe', () => {
    expect(trechoDoCampo('{{1}}', '1')).toEqual([{ campo: '1', alvo: true }]);
    expect(trechoDoCampo('Oi, {{1}}', '2')).toEqual([]);
    expect(trechoDoCampo()).toEqual([]);
  });
});

describe('preenchedorProprioCobre', () => {
  it('cobre texto e deixa mídia e botão com variável para o antigo', () => {
    expect(preenchedorProprioCobre(umCampo)).toBe(true);
    expect(preenchedorProprioCobre(doisCampos)).toBe(true);
    expect(preenchedorProprioCobre(semCampo)).toBe(true);
    expect(preenchedorProprioCobre(comMidia)).toBe(false);
    expect(preenchedorProprioCobre(comBotao)).toBe(false);
  });

  it('#1705: oferta com contagem vai para o preenchedor que pede a validade', () => {
    const oferta = {
      ...base,
      components: [
        {
          type: 'LIMITED_TIME_OFFER',
          limited_time_offer: { text: 'Só hoje!', has_expiration: true },
        },
        { type: 'BODY', text: 'Oi, {{1}}.' },
      ],
    };

    expect(preenchedorProprioCobre(oferta)).toBe(false);
  });
});

describe('modeloCompleto com cupom (#1705)', () => {
  const cupom = {
    ...base,
    components: [
      { type: 'BODY', text: 'Use o cupom.' },
      { type: 'BUTTONS', buttons: [{ type: 'COPY_CODE', example: ['X1'] }] },
    ],
  };

  it('não dá o modelo por pronto sem o código, mesmo sem campo no texto', () => {
    expect(modeloCompleto(cupom, paramsVazios(cupom))).toBe(false);
    expect(
      modeloCompleto(cupom, {
        buttons: [{ type: 'copy_code', parameter: 'X1' }],
      })
    ).toBe(true);
  });
});

const com = (params, chave, valor) =>
  comCampo(params, { parte: 'body', chave }, valor);

describe('paramsVazios e comCampo', () => {
  it('começa com todo campo vazio, sem adivinhar o nome de ninguém', () => {
    expect(paramsVazios(doisCampos)).toEqual({ body: { 1: '', 2: '' } });
    expect(paramsVazios(nomeado)).toEqual({ body: { nome: '', pedido: '' } });
    expect(paramsVazios(semCampo)).toEqual({});
  });

  it('troca um campo sem mexer no objeto anterior', () => {
    const antes = paramsVazios(doisCampos);
    const depois = com(antes, '2', 'sexta');

    expect(depois.body).toEqual({ 1: '', 2: 'sexta' });
    expect(antes.body).toEqual({ 1: '', 2: '' });
  });

  it('só está completo com todos os campos preenchidos', () => {
    const meio = com(paramsVazios(doisCampos), '1', 'Mariana');
    const cheio = com(meio, '2', 'sexta');

    expect(modeloCompleto(doisCampos, paramsVazios(doisCampos))).toBe(false);
    expect(modeloCompleto(doisCampos, meio)).toBe(false);
    expect(modeloCompleto(doisCampos, cheio)).toBe(true);
    expect(modeloCompleto(semCampo, {})).toBe(true);
    expect(previaDoModelo(doisCampos, cheio)).toEqual({
      cabecalho: 'Lembrete',
      corpo: 'Oi, Mariana. Seu horário é sexta.',
    });
  });
});

// O que o preenchedor antigo emite em `sendMessage`, com os mesmos valores.
const doPreenchedorAntigo = async (modelo, valores) => {
  const wrapper = shallowMount(WhatsAppTemplateParser, {
    props: { template: modelo },
    global: { mocks: { $t: chave => chave } },
  });
  Object.entries(valores).forEach(([chave, valor]) => {
    wrapper.vm.processedParams.body[chave] = valor;
  });
  await wrapper.vm.$nextTick();
  wrapper.vm.sendMessage();
  return wrapper.emitted('sendMessage')[0][0];
};

describe('payloadDoModelo', () => {
  it('é idêntico ao do preenchedor antigo com 1 campo de corpo', async () => {
    const valores = { 1: 'Mariana' };
    const proprio = payloadDoModelo(
      umCampo,
      com(paramsVazios(umCampo), '1', 'Mariana')
    );

    expect(proprio).toEqual(await doPreenchedorAntigo(umCampo, valores));
    expect(proprio).toEqual({
      message: 'Olá, {{1}}! Aqui é da Acme.',
      pendingMessageContent: 'Olá, Mariana! Aqui é da Acme.',
      templateParams: {
        name: 'boas_vindas',
        category: 'MARKETING',
        language: 'pt_BR',
        namespace: 'ns_1',
        content_mode: 'raw_template',
        processed_params: { body: { 1: 'Mariana' } },
      },
    });
  });

  it('é idêntico ao do preenchedor antigo com 2 campos de corpo', async () => {
    const valores = { 1: 'Mariana', 2: 'sexta, 9h' };
    const params = com(
      com(paramsVazios(doisCampos), '1', 'Mariana'),
      '2',
      'sexta, 9h'
    );
    const proprio = payloadDoModelo(doisCampos, params);

    expect(proprio).toEqual(await doPreenchedorAntigo(doisCampos, valores));
    expect(proprio.message).toBe(textoDoCorpo(doisCampos));
    expect(proprio.templateParams.processed_params).toEqual({
      body: { 1: 'Mariana', 2: 'sexta, 9h' },
    });
  });

  it('é idêntico ao do preenchedor antigo sem campo nenhum', async () => {
    expect(payloadDoModelo(semCampo, paramsVazios(semCampo))).toEqual(
      await doPreenchedorAntigo(semCampo, {})
    );
  });
});
