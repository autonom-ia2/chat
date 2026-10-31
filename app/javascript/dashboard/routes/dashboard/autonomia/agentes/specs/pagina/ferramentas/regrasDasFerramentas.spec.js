import {
  MASCARA_DO_SEGREDO,
  conferirEndereco,
  conferirNomeDaInformacao,
  jsonValido,
  nomeTecnico,
  paraApi,
  paraRascunho,
  precisaRedigitar,
  rascunhoDeExemplo,
  validarPasso,
  variaveisEm,
  avisosDasInformacoes,
  passosProvaveisDoErro,
  conteudoDoRascunho,
  novoCabecalho,
  novaInformacao,
  rascunhoVazio,
  enderecoDeExemplo,
} from '../../../utils/ferramentas';
import ptBR from 'dashboard/i18n/locale/pt_BR/agents.json';
import { composeMessages } from 'dashboard/i18n/pacotesDoPainel';
import segurosPtBR from 'dashboard/i18n/pacotes/seguros/pt_BR.json';
import corretoraPtBR from 'dashboard/i18n/pacotes/seguros/corretora/pt_BR.json';
import {
  lerResposta,
  montarChamada,
  valorParaTeste,
  traduzirErroDoTeste,
} from '../../../utils/testeDaFerramenta';

// #1301 — regras das Ferramentas (protótipo ferramentas.html). Tudo por métodos de string: nada de
// regex para ler endereço, nome ou erro.

// Tradutor mínimo, como o vue-i18n: busca a chave no catálogo.
const tradutor = mensagens => chave =>
  chave.split('.').reduce((nivel, parte) => nivel?.[parte], mensagens);
const t = tradutor(ptBR);

const FERRAMENTA = {
  id: 3,
  name: 'Busca no estoque',
  slug: 'busca_no_estoque',
  description: 'Use quando a pessoa perguntar se tem a peça.',
  enabled: true,
  http_method: 'GET',
  endpoint_url:
    'https://api.sualoja.com.br/estoque/busca?termo={{ termo | url_encode }}',
  request_body_template: '',
  headers_config: [
    { key: 'content-type', value: 'application/json', secret: false },
    { key: 'x-api-key', value: MASCARA_DO_SEGREDO, secret: true },
    { key: 'x-loja', value: '12', secret: false },
  ],
  param_schema: [
    { name: 'termo', type: 'string', description: 'A peça', required: true },
    { name: 'ano', type: 'integer', description: 'Ano', required: false },
  ],
  response_mapping: { template: '{{ response.total }}', outro: 'x' },
};

describe('regras das Ferramentas', () => {
  describe('variáveis do endereço e do corpo', () => {
    it('lists the names between double braces, without filters or repeats', () => {
      expect(
        variaveisEm(
          'https://x.com/{{numero}}?t={{ termo | url_encode }}&n={{numero}}'
        )
      ).toEqual(['numero', 'termo']);
      expect(variaveisEm('')).toEqual([]);
      expect(variaveisEm('sem {{ fim')).toEqual([]);
    });
  });

  describe('conferirEndereco', () => {
    it.each([
      ['', 'VAZIO'],
      ['http://api.sualoja.com.br', 'HTTPS'],
      ['https://', 'INCOMPLETO'],
      ['https://localhost/x', 'REDE'],
      ['https://estoque.local/x', 'REDE'],
      ['https://192.168.0.10/estoque', 'IP'],
      ['https://servidor/x', 'INCOMPLETO'],
      [
        'https://api.sualoja.com.br/estoque/busca?termo={{ termo | url_encode }}',
        '',
      ],
    ])('%s → %s', (endereco, esperado) => {
      expect(conferirEndereco(endereco)).toBe(esperado);
    });
  });

  describe('conferirNomeDaInformacao', () => {
    const lista = [{ nome: 'termo' }, { nome: 'termo' }, { nome: 'cor' }];
    it('asks for a name, plain letters and no repeats', () => {
      expect(conferirNomeDaInformacao('', lista, 2)).toBe('VAZIO');
      expect(conferirNomeDaInformacao('ano carro', lista, 2)).toBe('FORMATO');
      expect(conferirNomeDaInformacao('preço', lista, 2)).toBe('FORMATO');
      expect(conferirNomeDaInformacao('1ano', lista, 2)).toBe('FORMATO');
      expect(conferirNomeDaInformacao('termo', lista, 0)).toBe('REPETIDO');
      expect(conferirNomeDaInformacao('cor', lista, 2)).toBe('');
    });
  });

  it('checks the JSON body after filling the variables', () => {
    expect(jsonValido('')).toBe(true);
    expect(jsonValido('{ "termo": "{{termo}}", "limite": {{limite}} }')).toBe(
      true
    );
    expect(jsonValido('{ "a": 1 "b": 2 }')).toBe(false);
  });

  // Revisão 2 do #1425: numa vaga sem aspas o backend aceita texto que seja número, true, false ou
  // null (o tipo padrão da tela é texto). A tela não sabe o valor; checa só a forma do JSON.
  it('accepts a variable without quotes, as the backend takes a number there', () => {
    expect(jsonValido('{ "t": {{termo}} }')).toBe(true);
    expect(jsonValido('{ "t": "{{termo}}" }')).toBe(true);
  });

  it('builds the technical name from the name, without accents', () => {
    expect(nomeTecnico('Cálculo de frete!')).toBe('calculo_de_frete');
    expect(nomeTecnico('')).toBe('ferramenta');
  });

  it('starts from a generic example, never a real customer address', () => {
    const exemplo = rascunhoDeExemplo(t);
    expect(exemplo.endereco).toBe(
      'https://api.sualoja.com.br/estoque/busca?termo={{ termo | url_encode }}'
    );
    expect(exemplo.informacoes.map(i => i.nome)).toEqual(['termo']);
    expect(JSON.stringify(exemplo)).not.toContain('gira');
  });

  // #1802: o exemplo vem do i18n. O geral fica como era; a corretora ganha um exemplo de seguro.
  it('keeps the general example exactly as it was', () => {
    const exemplo = rascunhoDeExemplo(t);
    expect(exemplo).toMatchObject({
      nome: 'Busca no estoque',
      quando:
        'Use quando a pessoa perguntar se uma peça tem em estoque ou quanto custa. Traz nome, preço e quantidade.',
    });
    expect(exemplo.informacoes[0].descricao).toBe(
      'A peça que a pessoa procura, do jeito que ela falou.'
    );
    expect(enderecoDeExemplo(t)).toBe(exemplo.endereco);
  });

  it('uses the brokerage example from the pack, with a generic address', () => {
    const exemplo = rascunhoDeExemplo(
      tradutor(composeMessages(ptBR, [segurosPtBR, corretoraPtBR]))
    );
    expect(exemplo.nome).toBe('Consulta de apólice');
    expect(exemplo.endereco).toBe(
      'https://api.suacorretora.com.br/apolices/busca?termo={{ termo | url_encode }}'
    );
    expect(exemplo.informacoes.map(i => i.nome)).toEqual(['termo']);
    expect(conferirEndereco(exemplo.endereco)).toBe('');
  });

  describe('rascunho ↔ API', () => {
    it('reads a saved tool, keeping the secret as "Guardado" and hiding automatic headers', () => {
      const r = paraRascunho(FERRAMENTA);
      expect(r).toMatchObject({
        nome: 'Busca no estoque',
        slug: 'busca_no_estoque',
        quando: 'Use quando a pessoa perguntar se tem a peça.',
        metodo: 'GET',
        mapeamento: '{{ response.total }}',
      });
      expect(r.informacoes).toMatchObject([
        {
          nome: 'termo',
          tipo: 'string',
          descricao: 'A peça',
          podeFaltar: false,
        },
        { nome: 'ano', tipo: 'integer', descricao: 'Ano', podeFaltar: true },
      ]);
      expect(r.cabecalhos.map(c => c.chave)).toEqual(['x-api-key', 'x-loja']);
      expect(r.cabecalhos[0]).toMatchObject({
        valor: '',
        segredo: true,
        guardado: true,
        chaveOriginal: 'x-api-key',
      });
      expect(r.cabecalhos[1]).toMatchObject({ valor: '12', segredo: false });
    });

    it('sends the mask back only for an untouched secret, with the same key', () => {
      const r = paraRascunho(FERRAMENTA);
      const api = paraApi(r);
      expect(api.headers_config).toEqual([
        { key: 'content-type', value: 'application/json', secret: false },
        { key: 'x-api-key', value: MASCARA_DO_SEGREDO, secret: true },
        { key: 'x-loja', value: '12', secret: false },
      ]);
      expect(api.param_schema).toEqual([
        {
          name: 'termo',
          type: 'string',
          description: 'A peça',
          required: true,
        },
        { name: 'ano', type: 'integer', description: 'Ano', required: false },
      ]);
      expect(api.response_mapping).toEqual({
        template: '{{ response.total }}',
        outro: 'x',
      });
      expect(api).not.toHaveProperty('enabled');
    });

    it('never sends the mask under a renamed key or a secret turned off', () => {
      const r = paraRascunho(FERRAMENTA);
      const renomeado = {
        ...r,
        cabecalhos: [
          { ...r.cabecalhos[0], chave: 'x-api-token', valor: 'novo' },
        ],
      };
      expect(paraApi(renomeado).headers_config).toContainEqual({
        key: 'x-api-token',
        value: 'novo',
        secret: true,
      });
      expect(JSON.stringify(paraApi(renomeado))).not.toContain(
        MASCARA_DO_SEGREDO
      );
      expect(precisaRedigitar(renomeado.cabecalhos[0])).toBe(true);
      expect(precisaRedigitar({ ...r.cabecalhos[0], segredo: false })).toBe(
        true
      );
      expect(precisaRedigitar(r.cabecalhos[0])).toBe(false);
    });

    it('drops empty header rows and the mapping key when it is cleared', () => {
      const r = {
        ...paraRascunho({ ...FERRAMENTA, response_mapping: {} }),
        cabecalhos: [{ chave: ' ', valor: 'x', segredo: false }],
      };
      const api = paraApi(r);
      expect(api.headers_config).toEqual([
        { key: 'content-type', value: 'application/json', secret: false },
      ]);
      expect(api.response_mapping).toEqual({});
    });
  });

  describe('validarPasso', () => {
    const base = () => ({ ...rascunhoDeExemplo(t), nome: 'Estoque' });

    it('step 1: name is required; empty "Quando usar" only warns once', () => {
      expect(validarPasso(1, { ...base(), nome: ' ' }, false).erros).toEqual({
        nome: 'NOME',
      });
      expect(validarPasso(1, { ...base(), quando: '' }, false)).toEqual({
        erros: {},
        avisarQuando: true,
      });
      expect(validarPasso(1, { ...base(), quando: '' }, true)).toEqual({
        erros: {},
        avisarQuando: false,
      });
    });

    it('step 2: address and technical name', () => {
      expect(
        validarPasso(2, { ...base(), endereco: 'http://x.com' }).erros
      ).toEqual({ endereco: 'HTTPS' });
      expect(validarPasso(2, { ...base(), slug: 'com espaço' }).erros).toEqual({
        slug: 'SLUG',
      });
    });

    it('step 3: each information name', () => {
      const r = {
        ...base(),
        informacoes: [{ nome: 'ano carro', tipo: 'string', descricao: '' }],
      };
      expect(validarPasso(3, r).erros).toEqual({ i0: 'FORMATO' });
    });

    it('step 4: a secret needs a value; a renamed saved one needs it again', () => {
      const novo = {
        ...base(),
        cabecalhos: [{ chave: 'x-api-key', valor: '', segredo: true }],
      };
      expect(validarPasso(4, novo).erros).toEqual({ c0: 'VALOR' });
      const renomeado = {
        ...base(),
        cabecalhos: [
          {
            chave: 'x-token',
            valor: '',
            segredo: true,
            guardado: true,
            chaveOriginal: 'x-api-key',
          },
        ],
      };
      expect(validarPasso(4, renomeado).erros).toEqual({ c0: 'REDIGITAR' });
      const guardado = {
        ...base(),
        cabecalhos: [{ ...renomeado.cabecalhos[0], chave: 'x-api-key' }],
      };
      expect(validarPasso(4, guardado).erros).toEqual({});
    });
  });

  it('warns about variables without information and information never used', () => {
    expect(
      avisosDasInformacoes({
        metodo: 'POST',
        endereco: 'https://x.com/busca',
        corpo: '{ "t": "{{termo}}", "m": "{{marca}}" }',
        informacoes: [
          { nome: 'termo' },
          { nome: 'cor' },
          { nome: 'ano carro' },
        ],
      })
    ).toEqual({
      semInformacao: { onde: 'CORPO', nome: 'marca' },
      naoUsadas: ['cor'],
    });
  });

  it('guesses the step from the API message, by its start', () => {
    expect(passosProvaveisDoErro('Endpoint url deve usar HTTPS')).toEqual([2]);
    expect(
      passosProvaveisDoErro('Param schema possui nomes inválidos')
    ).toEqual([3]);
    expect(
      passosProvaveisDoErro('Headers config possui cabeçalhos inválidos')
    ).toEqual([4]);
    expect(passosProvaveisDoErro('Nome não pode ficar em branco')).toEqual([
      2, 3,
    ]);
  });

  describe('teste da ferramenta', () => {
    it.each([
      ['tool_http_error: 401 Unauthorized', 'CHAVE', 'CHAVE', false],
      ['tool_http_error: 403 Forbidden', 'CHAVE', 'CHAVE', false],
      ['tool_http_error: 404 Not Found', 'NAO_ENCONTRADO', 'ENDERECO', false],
      ['tool_http_error: 422 Unprocessable', 'NAO_ENTENDEU', 'PREENCHE', false],
      ['tool_http_error: 503 Service Unavailable', 'SERVIDOR', null, false],
      ['tool_http_error: 302 Found', 'REDIRECIONA', 'ENDERECO', false],
      [
        'tool_execution_error: invalid_url_error',
        'URL_INVALIDA',
        'ENDERECO',
        false,
      ],
      ['tool_execution_error: unsafe_url_error', 'REDE', 'ENDERECO', false],
      ['tool_execution_error: fetch_error', 'SEM_RESPOSTA', null, true],
      ['tool_execution_error: total_timeout_error', 'SEM_RESPOSTA', null, true],
      [
        'tool_execution_error: undefined_variable',
        'NAO_EXISTE',
        'PREENCHE',
        false,
      ],
      [
        'tool_execution_error: cross_origin_redirect_error',
        'REDIRECIONA',
        'ENDERECO',
        false,
      ],
      ['tool_execution_error: corpo_json_invalido', 'CORPO', 'PREENCHE', false],
      ['tool_execution_error: cabecalho_invalido', 'CABECALHO', 'CHAVE', false],
      ['tool_execution_error: parametro_invalido', 'VALOR', 'PREENCHE', false],
      ['tool_execution_error: corpo_sem_escape', 'TIPO_DO_CORPO', null, false],
      ['tool_execution_error: parser_error', 'NAO_JSON', 'PREENCHE', false],
      [
        'tool_execution_error: endereco_invalido',
        'URL_INVALIDA',
        'ENDERECO',
        false,
      ],
      ['tool_execution_error: argument_error', 'VALOR', 'PREENCHE', false],
      ['tool_execution_error: zero_division_error', 'VALOR', 'PREENCHE', false],
      ['tool_execution_error: internal_error', 'GENERICO', null, false],
      ['outra coisa', 'GENERICO', null, false],
    ])('%s → %s', (erro, chave, corrigir, ambar) => {
      expect(traduzirErroDoTeste(erro)).toEqual({
        chave,
        corrigir,
        ambar,
        detalhe: erro,
      });
    });

    // #1425: o detalhe é o que o agente recebe, quando a API manda.
    it('shows in the detail what the agent receives, when the API sends it', () => {
      const agente =
        '{"error":"tool_http_error: 400","resposta":"falta o cep"}';
      expect(
        traduzirErroDoTeste('tool_http_error: 400 Bad Request', agente)
      ).toMatchObject({ chave: 'NAO_ENTENDEU', detalhe: agente });
    });

    // Revisão 3 do #1425: o backend codifica cada valor do endereço pela posição; nada fica cru.
    it('shows the call as the backend builds it, with the address values encoded', () => {
      const chamada = montarChamada(
        {
          metodo: 'POST',
          endereco: 'https://x.com/b?t={{ termo | url_encode }}&c={{cor}}',
          corpo: '{ "t": "{{termo}}" }',
          cabecalhos: [
            { chave: 'x-api-key', segredo: true },
            { chave: 'x-loja', valor: '{{loja}}', segredo: false },
          ],
        },
        { termo: 'pastilha de freio', cor: 'azul claro', loja: '7' }
      );
      expect(chamada.endereco).toEqual([
        { texto: 'https://x.com/b?t=pastilha+de+freio&c=azul+claro' },
      ]);
      expect(chamada.cabecalhos).toEqual([
        'x-api-key: ••••••',
        'x-loja: 7',
        'Content-Type: application/json',
        'Accept: application/json',
      ]);
      expect(chamada.corpo).toBe('{"t":"pastilha de freio"}');
    });

    it('encodes a path value as one segment and a query value as a field', () => {
      const chamada = montarChamada(
        {
          metodo: 'GET',
          endereco:
            'https://x.com/estoque/{{p}}?t={{ q | url_encode }}&u={{q}}#ancora',
          corpo: '',
          cabecalhos: [],
        },
        { p: '../a b?x#y (ção)!', q: 'a&admin=1#z' }
      );
      expect(chamada.endereco).toEqual([
        {
          texto:
            'https://x.com/estoque/..%2Fa%20b%3Fx%23y%20%28%C3%A7%C3%A3o%29%21?t=a%26admin%3D1%23z&u=a%26admin%3D1%23z#ancora',
        },
      ]);
    });

    it('keeps a fixed address identical', () => {
      const fixo = 'https://x.com/v1?x=1&y=a%20b#frag';
      const chamada = montarChamada(
        { metodo: 'GET', endereco: fixo, corpo: '', cabecalhos: [] },
        {}
      );
      expect(chamada.endereco).toEqual([{ texto: fixo }]);
    });

    // #1425: a prévia do corpo mostra o texto escapado, como o backend envia.
    it('shows the body with the text escaped for JSON, as the backend sends it', () => {
      const chamada = montarChamada(
        {
          metodo: 'POST',
          endereco: 'https://x.com/b',
          corpo: '{ "t": "{{termo}}" }',
          cabecalhos: [],
        },
        { termo: 'x","admin":true' }
      );
      expect(chamada.corpo).toBe('{"t":"x\\",\\"admin\\":true"}');
      expect(JSON.parse(chamada.corpo)).toEqual({ t: 'x","admin":true' });
    });

    // Revisão do #1425: a prévia espelha o backend — JSON só quando o Content-Type é JSON ou falta;
    // formulário codifica cada valor; outro tipo mostra como foi escrito.
    it('previews a form body with each value encoded, like the backend', () => {
      const chamada = montarChamada(
        {
          metodo: 'POST',
          endereco: 'https://x.com/b',
          corpo: 'q={{termo}}&limit=5',
          cabecalhos: [],
          automaticos: [
            { key: 'Content-Type', value: 'application/x-www-form-urlencoded' },
          ],
        },
        { termo: 'a&admin=true (x)' }
      );
      expect(chamada.corpo).toBe('q=a%26admin%3Dtrue+%28x%29&limit=5');
      // Revisão 2: o cabeçalho mostrado é o declarado, não um JSON fixo.
      expect(chamada.cabecalhos).toEqual([
        'Content-Type: application/x-www-form-urlencoded',
        'Accept: application/json',
      ]);
    });

    it('previews url_encode already written in a form body only once', () => {
      const chamada = montarChamada(
        {
          metodo: 'POST',
          endereco: 'https://x.com/b',
          corpo: 'q={{ termo | url_encode }}',
          cabecalhos: [],
          automaticos: [
            { key: 'Content-Type', value: 'application/x-www-form-urlencoded' },
          ],
        },
        { termo: 'a b' }
      );
      expect(chamada.corpo).toBe('q=a+b');
    });

    it('treats an empty Content-Type as JSON', () => {
      const chamada = montarChamada(
        {
          metodo: 'POST',
          endereco: 'https://x.com/b',
          corpo: '{"q":"{{termo}}"}',
          cabecalhos: [],
          automaticos: [{ key: 'Content-Type', value: ' ' }],
        },
        { termo: 'a"b' }
      );
      expect(chamada.corpo).toBe('{"q":"a\\"b"}');
      expect(chamada.cabecalhos).toContain('Content-Type: application/json');
    });

    it('previews another body type as written', () => {
      const chamada = montarChamada(
        {
          metodo: 'POST',
          endereco: 'https://x.com/b',
          corpo: '<q>{{termo}}</q>',
          cabecalhos: [],
          automaticos: [{ key: 'content-type', value: 'application/xml' }],
        },
        { termo: 'a"b' }
      );
      expect(chamada.corpo).toBe('<q>a"b</q>');
    });

    it('keeps the variable visible while the value is empty, and GET has no body', () => {
      const chamada = montarChamada(
        {
          metodo: 'GET',
          endereco: 'https://x.com?t={{termo}}',
          corpo: '{}',
          cabecalhos: [],
        },
        {}
      );
      expect(chamada.endereco).toEqual([
        { texto: 'https://x.com?t={{termo}}' },
      ]);
      expect(chamada.corpo).toBe('');
      expect(chamada.cabecalhos).toEqual(['Accept: application/json']);
    });

    it('reads the answer: indented JSON, raw text when cut, empty', () => {
      expect(lerResposta('{"a":1}')).toEqual({
        vazia: false,
        cortada: false,
        json: '{\n  "a": 1\n}',
        texto: '{"a":1}',
      });
      // #1425: quem diz que cortou é a API (o mesmo corte de 8.000 do agente, com o aviso).
      const longa = `${'x'.repeat(7900)} […cortado por tamanho]`;
      expect(lerResposta(longa, true)).toMatchObject({
        cortada: true,
        json: null,
        texto: longa,
      });
      expect(lerResposta(`${'x'.repeat(1997)}...`)).toMatchObject({
        cortada: false,
      });
      expect(lerResposta('  ')).toMatchObject({ vazia: true });
    });
  });

  describe('revisão independente (#1301)', () => {
    it('counts variables in non-secret header values and warns when one has no information', () => {
      const avisos = avisosDasInformacoes({
        metodo: 'GET',
        endereco: 'https://x.com/busca',
        corpo: '',
        informacoes: [{ nome: 'loja' }],
        cabecalhos: [
          { chave: 'x-loja', valor: '{{loja}}', segredo: false },
          { chave: 'x-filial', valor: '{{filial}}', segredo: false },
          { chave: 'x-key', valor: '{{oculto}}', segredo: true },
        ],
      });
      expect(avisos).toEqual({
        semInformacao: { onde: 'CABECALHO', nome: 'filial' },
        naoUsadas: [],
      });
    });

    it('gives each card a stable id that never goes to the API', () => {
      const a = novoCabecalho();
      const b = novoCabecalho();
      expect(a.id).toBeTruthy();
      expect(a.id).not.toBe(b.id);
      expect(novaInformacao().id).toBeTruthy();
      const r = {
        ...rascunhoVazio(),
        nome: 'X',
        endereco: 'https://x.com',
        cabecalhos: [{ ...a, chave: 'x-a', valor: '1' }],
        informacoes: [{ ...novaInformacao(), nome: 'termo' }],
      };
      expect(JSON.stringify(paraApi(r))).not.toContain(a.id);
      expect(
        paraRascunho({ headers_config: [{ key: 'k', value: 'v' }] })
          .cabecalhos[0].id
      ).toBeTruthy();
    });

    it('compares drafts by content, ignoring card ids', () => {
      const vazio = rascunhoVazio();
      expect(conteudoDoRascunho(vazio)).toBe(
        conteudoDoRascunho(rascunhoVazio())
      );
      const comCabecalho = { ...vazio, cabecalhos: [novoCabecalho()] };
      expect(conteudoDoRascunho(comCabecalho)).not.toBe(
        conteudoDoRascunho(vazio)
      );
    });

    it('builds a technical name that starts with a letter (SLUG_FORMAT)', () => {
      expect(nomeTecnico('123 estoque')).toBe('f_123_estoque');
      expect(nomeTecnico('Estoque')).toBe('estoque');
      expect(
        validarPasso(2, { ...rascunhoDeExemplo(t), slug: '1abc' }).erros
      ).toEqual({ slug: 'SLUG' });
      expect(
        validarPasso(2, { ...rascunhoDeExemplo(t), slug: '_abc' }).erros
      ).toEqual({ slug: 'SLUG' });
      expect(
        validarPasso(2, { ...rascunhoDeExemplo(t), slug: 'a'.repeat(65) }).erros
      ).toEqual({ slug: 'SLUG' });
      expect(
        paraApi({ ...rascunhoDeExemplo(t), nome: '123 estoque', slug: '' }).slug
      ).toBe('f_123_estoque');
    });

    it('checks the header name: letters, numbers and hyphen', () => {
      const r = {
        ...rascunhoDeExemplo(t),
        cabecalhos: [{ ...novoCabecalho(), chave: 'x api_key', valor: 'v' }],
      };
      expect(validarPasso(4, r).erros).toEqual({ c0: 'CHAVE' });
    });

    it('accepts a comma in decimal numbers and sends a point', () => {
      expect(valorParaTeste('number', ' 12,5 ')).toBe('12.5');
      expect(valorParaTeste('string', '12,5')).toBe('12,5');
      expect(valorParaTeste('integer', '', true)).toBeNull();
    });
  });
});
