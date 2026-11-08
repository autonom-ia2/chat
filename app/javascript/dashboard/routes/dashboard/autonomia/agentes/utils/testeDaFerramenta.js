// #1301 (protótipo F07) — teste de uma ferramenta salva: a prévia do que vai ser chamado, a leitura
// do que o agente recebe e a tradução do erro do POST /tools/:id/test. Só métodos de string.

// #1425: o /test devolve o MESMO texto que o agente lê (cortado em 8.000 caracteres, com o aviso de
// corte) e diz se cortou (`cortada`).

const HTTP = 'tool_http_error:';
const EXECUCAO = 'tool_execution_error:';

// "corrigir" é a parte da ferramenta a abrir (passo 2, 3 ou 4); null = só testar de novo.
const PASSO_DA_CORRECAO = { ENDERECO: 2, PREENCHE: 3, CHAVE: 4 };
export const passoDaCorrecao = corrigir => PASSO_DA_CORRECAO[corrigir];

const erroHttp = codigo => {
  if (codigo === 401 || codigo === 403) return ['CHAVE', 'CHAVE'];
  if (codigo === 404) return ['NAO_ENCONTRADO', 'ENDERECO'];
  if (codigo === 400 || codigo === 422) return ['NAO_ENTENDEU', 'PREENCHE'];
  if (codigo >= 500) return ['SERVIDOR', null];
  if (codigo >= 300 && codigo < 400) return ['REDIRECIONA', 'ENDERECO'];
  return null;
};

const ERROS_DE_EXECUCAO = {
  invalid_url_error: ['URL_INVALIDA', 'ENDERECO'],
  unsafe_url_error: ['REDE', 'ENDERECO'],
  fetch_error: ['SEM_RESPOSTA', null],
  total_timeout_error: ['SEM_RESPOSTA', null],
  // #1425: o HttpExecutor recusa redirecionamento para outro domínio, corpo que deixou de ser JSON
  // depois de preenchido e quebra de linha num cabeçalho.
  cross_origin_redirect_error: ['REDIRECIONA', 'ENDERECO'],
  corpo_json_invalido: ['CORPO', 'PREENCHE'],
  cabecalho_invalido: ['CABECALHO', 'CHAVE'],
  // Revisão do #1425: valor fora do tipo da informação, corpo de tipo sem escape seguro com {{ }}, e
  // resposta que não é JSON numa ferramenta com mapeamento.
  parametro_invalido: ['VALOR', 'PREENCHE'],
  corpo_sem_escape: ['TIPO_DO_CORPO', null],
  parser_error: ['NAO_JSON', 'PREENCHE'],
  endereco_invalido: ['URL_INVALIDA', 'ENDERECO'],
  undefined_variable: ['NAO_EXISTE', 'PREENCHE'],
  undefined_filter: ['NAO_EXISTE', 'PREENCHE'],
  syntax_error: ['NAO_EXISTE', 'PREENCHE'],
  // #1444: com o erro de render recusado, um filtro que falha no valor digitado também chega aqui.
  argument_error: ['VALOR', 'PREENCHE'],
  zero_division_error: ['VALOR', 'PREENCHE'],
};

const lerPrefixo = erro => {
  if (erro.startsWith(HTTP)) {
    const codigo = Number(erro.slice(HTTP.length).trim().split(' ')[0]);
    return erroHttp(codigo);
  }
  if (erro.startsWith(EXECUCAO)) {
    return ERROS_DE_EXECUCAO[erro.slice(EXECUCAO.length).trim()] || null;
  }
  return null;
};

// A tradução lê a mensagem do HttpExecutor. O "detalhe" é o que o agente recebe (#1425), quando a API
// manda; senão, a própria mensagem.
export const traduzirErroDoTeste = (erro, agenteRecebe = '') => {
  const mensagem = String(erro ?? '');
  const [chave, corrigir] = lerPrefixo(mensagem) || ['GENERICO', null];
  const detalhe = String(agenteRecebe ?? '') || mensagem;
  return { chave, corrigir, ambar: chave === 'SEM_RESPOSTA', detalhe };
};

// O mesmo que o filtro url_encode do Liquid (CGI.escape): espaço vira +.
const codificar = valor => encodeURIComponent(valor).split('%20').join('+');

const valorDe = (valores, nome) => String(valores[nome] ?? '').trim();

// Junta os pedaços num só, para a prévia não virar uma sopa de <span>.
const juntar = pedacos => {
  const texto = pedacos.map(p => p.texto).join('');
  return texto ? [{ texto }] : [];
};

// Troca as {{variáveis}} como o HttpExecutor. Sem valor, a variável continua escrita. Cada valor vai com
// o escape da posição (#1425): no endereço, pedaço do caminho ou valor da query (EnderecoDaFerramenta);
// no corpo, o do tipo do corpo (CorpoDaFerramenta).
const comoVeio = valor => valor;
const paraDentroDeAspas = valor => JSON.stringify(valor).slice(1, -1);
// URI.encode_www_form_component: só letras, dígitos e * - . _ ficam; espaço vira +.
const FORA_DO_ENCODE_URI = ['!', "'", '(', ')', '~'];
const comoCampoDeFormulario = valor =>
  FORA_DO_ENCODE_URI.reduce(
    (texto, c) =>
      texto.split(c).join(`%${c.charCodeAt(0).toString(16).toUpperCase()}`),
    codificar(valor)
  );
// ERB::Util.url_encode: só letras, dígitos e - . _ ~ ficam; espaço vira %20 e "/" também é codificada.
const FORA_DO_ENCODE_URI_NO_CAMINHO = ['!', "'", '(', ')', '*'];
const noCaminho = valor =>
  FORA_DO_ENCODE_URI_NO_CAMINHO.reduce(
    (texto, c) =>
      texto.split(c).join(`%${c.charCodeAt(0).toString(16).toUpperCase()}`),
    encodeURIComponent(valor)
  );
// Os escapes que já codificam: com eles, o backend tira o url_encode final e codifica uma vez só.
const CODIFICAM = [comoCampoDeFormulario, noCaminho];

const preencher = (texto, valores, escapar = comoVeio) => {
  const partes = String(texto ?? '').split('{{');
  const pedacos = [{ texto: partes[0] }];
  partes.slice(1).forEach(parte => {
    const fim = parte.indexOf('}}');
    if (fim < 0) {
      pedacos.push({ texto: `{{${parte}` });
      return;
    }
    const [nome, ...filtros] = parte
      .slice(0, fim)
      .split('|')
      .map(p => p.trim());
    const valor = valorDe(valores, nome);
    if (!valor) {
      pedacos.push({ texto: `{{${parte.slice(0, fim)}}}` });
    } else if (
      CODIFICAM.includes(escapar) &&
      filtros[filtros.length - 1] === 'url_encode'
    ) {
      pedacos.push({ texto: escapar(valor) });
    } else if (filtros.includes('url_encode')) {
      pedacos.push({ texto: escapar(codificar(valor)) });
    } else {
      pedacos.push({ texto: escapar(valor) });
    }
    pedacos.push({ texto: parte.slice(fim + 2) });
  });
  return { pedacos: juntar(pedacos) };
};

// -> [antes, depois do separador] ou [texto, null], como EnderecoDaFerramenta#dividir.
const dividir = (texto, separador) => {
  const posicao = texto.indexOf(separador);
  return posicao < 0
    ? [texto, null]
    : [texto.slice(0, posicao), texto.slice(posicao + 1)];
};

// O endereço como o backend monta: fragmento a partir do primeiro #, query a partir do primeiro ? antes
// dele. Sem {{ }}, como foi cadastrado.
const montarEndereco = (endereco, valores) => {
  const texto = String(endereco ?? '');
  const [base, fragmento] = dividir(texto, '#');
  const [caminho, query] = dividir(base, '?');
  const pedacos = [
    ...preencher(caminho, valores, noCaminho).pedacos,
    ...(query === null
      ? []
      : [
          { texto: '?' },
          ...preencher(query, valores, comoCampoDeFormulario).pedacos,
        ]),
    ...(fragmento === null ? [] : [{ texto: `#${fragmento}` }]),
  ];
  return juntar(pedacos);
};

const comCorpo = rascunho =>
  rascunho.metodo === 'POST' && String(rascunho.corpo ?? '').trim() !== '';

const textoDe = pedacos => pedacos.map(p => p.texto).join('');

// O cabeçalho automático declarado (Content-Type, Accept), com valor; vazio conta como ausente, como no
// HttpExecutor#request_headers.
const automaticoDeclarado = (rascunho, nome) =>
  [...(rascunho.automaticos || []), ...(rascunho.cabecalhos || [])].find(
    c =>
      String(c.key ?? c.chave ?? '')
        .trim()
        .toLowerCase() === nome &&
      String(c.value ?? c.valor ?? '').trim() !== ''
  );
const valorDoCabecalho = cabecalho =>
  String(cabecalho?.value ?? cabecalho?.valor ?? '').trim();

// O tipo do corpo, pela mesma regra do backend (CorpoDaFerramenta#tipo): sem Content-Type (ou vazio)
// ou com "json" é JSON; formulário; o resto vai como foi escrito.
const FORMULARIO = 'application/x-www-form-urlencoded';
const tipoDoCorpo = rascunho => {
  const declarado = automaticoDeclarado(rascunho, 'content-type');
  const valor = valorDoCabecalho(declarado).toLowerCase();
  if (!declarado || valor.includes('json')) return 'JSON';
  return valor.includes(FORMULARIO) ? 'FORMULARIO' : 'OUTRO';
};

// O backend manda o JSON regerado (sem espaços nem comentários); com {{variável}} ainda sem valor,
// a prévia mostra como está.
const regerado = texto => {
  try {
    return JSON.stringify(JSON.parse(texto));
  } catch {
    return texto;
  }
};

const montarCorpo = (rascunho, valores) => {
  const tipo = tipoDoCorpo(rascunho);
  if (tipo === 'JSON') {
    return regerado(
      textoDe(preencher(rascunho.corpo, valores, paraDentroDeAspas).pedacos)
    );
  }
  const escapar = tipo === 'FORMULARIO' ? comoCampoDeFormulario : comoVeio;
  return textoDe(preencher(rascunho.corpo, valores, escapar).pedacos);
};

export const montarChamada = (rascunho, valores) => {
  const cabecalhos = (rascunho.cabecalhos || [])
    .filter(c => String(c.chave ?? '').trim() !== '')
    .map(c => {
      const valor = c.segredo
        ? '••••••'
        : textoDe(preencher(c.valor, valores).pedacos);
      return `${c.chave.trim()}: ${valor}`;
    });
  // Os automáticos como o backend manda: o declarado, ou application/json (Content-Type só com corpo).
  const tipoDeclarado = automaticoDeclarado(rascunho, 'content-type');
  const acceptDeclarado = automaticoDeclarado(rascunho, 'accept');
  const contentType =
    tipoDeclarado || comCorpo(rascunho)
      ? [
          `Content-Type: ${valorDoCabecalho(tipoDeclarado) || 'application/json'}`,
        ]
      : [];
  const automaticos = [
    ...contentType,
    `Accept: ${valorDoCabecalho(acceptDeclarado) || 'application/json'}`,
  ];
  return {
    metodo: rascunho.metodo,
    endereco: montarEndereco(rascunho.endereco, valores),
    cabecalhos: [...cabecalhos, ...automaticos],
    corpo: comCorpo(rascunho) ? montarCorpo(rascunho, valores) : '',
  };
};

// O que o agente recebe: JSON indentado quando dá para ler; cortado ou texto, como veio.
export const lerResposta = (corpo, cortadaNaApi = false) => {
  const texto = String(corpo ?? '');
  const cortada = Boolean(cortadaNaApi);
  let json = null;
  if (!cortada) {
    try {
      json = JSON.stringify(JSON.parse(texto), null, 2);
    } catch {
      json = null;
    }
  }
  return { vazia: texto.trim() === '', cortada, json, texto };
};

// Valor digitado no teste: vazio vai como null (como o agente manda no atendimento) e número com
// vírgula vira ponto.
export const valorParaTeste = (tipo, valor) => {
  const texto = String(valor ?? '').trim();
  if (!texto) return null;
  return tipo === 'number' ? texto.split(',').join('.') : texto;
};
