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
  undefined_variable: ['NAO_EXISTE', 'PREENCHE'],
  undefined_filter: ['NAO_EXISTE', 'PREENCHE'],
  syntax_error: ['NAO_EXISTE', 'PREENCHE'],
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

// Junta pedaços vizinhos sem marca, para a prévia não virar uma sopa de <span>.
const juntar = pedacos =>
  pedacos
    .filter(p => p.texto !== '')
    .reduce((lista, pedaco) => {
      const ultimo = lista[lista.length - 1];
      if (ultimo && !ultimo.ruim && !pedaco.ruim) {
        return [...lista.slice(0, -1), { texto: ultimo.texto + pedaco.texto }];
      }
      return [...lista, pedaco];
    }, []);

// Troca as {{variáveis}} como o HttpExecutor (Liquid sem codificar, a não ser com url_encode).
// Sem valor, a variável continua escrita; no endereço, valor com espaço sem url_encode é "ruim".
// No corpo JSON o texto vai escapado para dentro de aspas, como o backend envia (#1425).
const paraDentroDeAspas = valor => JSON.stringify(valor).slice(1, -1);

const preencher = (texto, valores, noEndereco, noCorpo = false) => {
  const partes = String(texto ?? '').split('{{');
  const pedacos = [{ texto: partes[0] }];
  let ruim = '';
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
    } else if (filtros.includes('url_encode')) {
      pedacos.push({ texto: codificar(valor) });
    } else if (noEndereco && valor.includes(' ')) {
      ruim = ruim || nome;
      pedacos.push({ texto: valor, ruim: true });
    } else {
      pedacos.push({ texto: noCorpo ? paraDentroDeAspas(valor) : valor });
    }
    pedacos.push({ texto: parte.slice(fim + 2) });
  });
  return { pedacos: juntar(pedacos), ruim };
};

const comCorpo = rascunho =>
  rascunho.metodo === 'POST' && String(rascunho.corpo ?? '').trim() !== '';

const textoDe = pedacos => pedacos.map(p => p.texto).join('');

export const montarChamada = (rascunho, valores) => {
  const endereco = preencher(rascunho.endereco, valores, true);
  const cabecalhos = (rascunho.cabecalhos || [])
    .filter(c => String(c.chave ?? '').trim() !== '')
    .map(c => {
      const valor = c.segredo
        ? '••••••'
        : textoDe(preencher(c.valor, valores, false).pedacos);
      return `${c.chave.trim()}: ${valor}`;
    });
  const automaticos = comCorpo(rascunho)
    ? ['Content-Type: application/json', 'Accept: application/json']
    : ['Accept: application/json'];
  return {
    metodo: rascunho.metodo,
    endereco: endereco.pedacos,
    ruim: endereco.ruim,
    cabecalhos: [...cabecalhos, ...automaticos],
    corpo: comCorpo(rascunho)
      ? textoDe(preencher(rascunho.corpo, valores, false, true).pedacos)
      : '',
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
