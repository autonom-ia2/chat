// #1301 — regras das Ferramentas do agente (protótipo ferramentas.html). Endereço, nomes e corpo
// são lidos com métodos de string e com o parser URL do navegador: nada de regex.

// O mesmo valor de Autonomia::Agents::Tool.masked_header_value: a API devolve o segredo assim e,
// no PATCH, o ToolsController troca esse valor pelo guardado quando a chave é a mesma.
export const MASCARA_DO_SEGREDO = '••••••••';
export const TIPOS = ['string', 'number', 'integer', 'boolean'];
export const PASSOS = ['O_QUE_FAZ', 'PARA_ONDE', 'PREENCHE', 'COMO_ENTRA'];

// O HttpExecutor já põe Accept e Content-Type: a tela não os mostra, mas os guarda como vieram.
const AUTOMATICOS = ['content-type', 'accept'];
const LETRAS = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
const PERMITIDOS = `${LETRAS}0123456789_`;
// O exemplo vem do i18n, para o pacote da conta trocar (#1802). As chaves e o filtro ficam no código:
// "{" e "|" têm significado no vue-i18n.
const NS_EXEMPLO = 'AGENTS.JORNADA.PAGINA.FERRAMENTAS';
const VARIAVEL_DO_EXEMPLO = '?termo={{ termo | url_encode }}';
export const enderecoDeExemplo = t =>
  `${t(`${NS_EXEMPLO}.RASCUNHO_EXEMPLO.ENDERECO`)}${VARIAVEL_DO_EXEMPLO}`;

const preenchido = valor => String(valor ?? '').trim() !== '';
const ehDigito = c => c >= '0' && c <= '9';
const soPermitidos = texto => [...texto].every(c => PERMITIDOS.includes(c));
const ehLetra = c => LETRAS.includes(c);
// Autonomia::Agents::Tool::SLUG_FORMAT: começa por letra; letras, números e _; até 64.
const MAX_SLUG = 64;
const slugValido = slug =>
  slug.length <= MAX_SLUG && ehLetra(slug.charAt(0)) && soPermitidos(slug);
// validate_headers_config: só letras, números e hífen no nome do cabeçalho.
const CHAVE_PERMITIDA = `${LETRAS}0123456789-`;
const chaveValida = chave => [...chave].every(c => CHAVE_PERMITIDA.includes(c));

// Id de cada cartão (informação ou cabeçalho): o Vue reaproveita o componente certo ao remover um
// do meio. Fica só na tela; nunca vai para a API.
let ultimoId = 0;
const novoId = () => {
  ultimoId += 1;
  return `cartao-${ultimoId}`;
};

// {{ nome | filtro }} → [{ nome, filtros }] na ordem em que aparecem.
const pedacosComVariavel = texto =>
  String(texto ?? '')
    .split('{{')
    .slice(1)
    .filter(pedaco => pedaco.indexOf('}}') > 0)
    .map(pedaco => pedaco.slice(0, pedaco.indexOf('}}')))
    .map(dentro => {
      const [nome, ...filtros] = dentro.split('|').map(p => p.trim());
      return { nome, filtros };
    })
    .filter(({ nome }) => nome);

const semRepetir = nomes => nomes.filter((n, i) => nomes.indexOf(n) === i);

export const variaveisEm = texto =>
  semRepetir(pedacosComVariavel(texto).map(v => v.nome));

const ehIpV4 = host =>
  host.split('.').every(parte => parte !== '' && [...parte].every(ehDigito));

const DENTRO_DA_REDE = ['.local', '.internal', '.localhost'];

// Mesmas regras do model (HTTPS, com host, sem localhost/.local, sem IP), antes de salvar.
export const conferirEndereco = endereco => {
  const texto = String(endereco ?? '').trim();
  if (!texto) return 'VAZIO';
  if (!texto.toLowerCase().startsWith('https://')) return 'HTTPS';
  let url;
  try {
    url = new URL(texto);
  } catch {
    return 'INCOMPLETO';
  }
  const host = url.hostname.toLowerCase();
  if (host === 'localhost' || DENTRO_DA_REDE.some(fim => host.endsWith(fim))) {
    return 'REDE';
  }
  if (host.startsWith('[') || ehIpV4(host)) return 'IP';
  if (!host.includes('.')) return 'INCOMPLETO';
  return '';
};

export const hostDoEndereco = endereco => {
  try {
    return new URL(String(endereco).trim()).hostname;
  } catch {
    return String(endereco ?? '');
  }
};

export const conferirNomeDaInformacao = (nome, lista, indice) => {
  const texto = String(nome ?? '').trim();
  if (!texto) return 'VAZIO';
  if (!soPermitidos(texto) || ehDigito(texto.charAt(0))) return 'FORMATO';
  const repetido = lista.some(
    (item, j) => j !== indice && String(item.nome ?? '').trim() === texto
  );
  return repetido ? 'REPETIDO' : '';
};

// Troca cada {{ … }} por 1 e tenta ler: vale para "{{x}}" entre aspas e para número solto.
export const jsonValido = corpo => {
  const texto = String(corpo ?? '');
  if (!texto.trim()) return true;
  const partes = texto.split('{{');
  const preenchidoComUm = partes.slice(1).reduce((saida, pedaco) => {
    const fim = pedaco.indexOf('}}');
    return fim < 0
      ? `${saida}{{${pedaco}`
      : `${saida}1${pedaco.slice(fim + 2)}`;
  }, partes[0]);
  try {
    JSON.parse(preenchidoComUm);
    return true;
  } catch {
    return false;
  }
};

// Prévia do nome técnico; o backend faz o mesmo (parameterize) quando o campo vai vazio.
export const nomeTecnico = nome => {
  const base = String(nome ?? '')
    .normalize('NFD')
    .toLowerCase();
  const letras = [...base].map(c => {
    const codigo = c.charCodeAt(0);
    if (codigo >= 0x300 && codigo <= 0x36f) return '';
    return (c >= 'a' && c <= 'z') || ehDigito(c) ? c : '_';
  });
  const nomeLimpo = letras.join('').split('_').filter(Boolean).join('_');
  if (!nomeLimpo) return 'ferramenta';
  const comLetra = ehLetra(nomeLimpo.charAt(0)) ? nomeLimpo : `f_${nomeLimpo}`;
  return comLetra.slice(0, MAX_SLUG);
};

export const novaInformacao = () => ({
  id: novoId(),
  nome: '',
  tipo: 'string',
  descricao: '',
  podeFaltar: false,
});

// Cabeçalho novo nasce como segredo: chave e token quase sempre são.
export const novoCabecalho = () => ({
  id: novoId(),
  chave: '',
  valor: '',
  segredo: true,
  guardado: false,
  chaveOriginal: '',
});

export const rascunhoVazio = () => ({
  nome: '',
  slug: '',
  quando: '',
  metodo: 'GET',
  endereco: '',
  informacoes: [],
  corpo: '',
  mapeamento: '',
  cabecalhos: [],
  automaticos: [],
  mapeamentoOriginal: {},
});

// Exemplo genérico (decisão do Rodrigo, 11/10): nenhuma URL de cliente real.
export const rascunhoDeExemplo = t => ({
  ...rascunhoVazio(),
  nome: t(`${NS_EXEMPLO}.RASCUNHO_EXEMPLO.NOME`),
  quando: t(`${NS_EXEMPLO}.PASSOS.UM.QUANDO_EXEMPLO`),
  endereco: enderecoDeExemplo(t),
  informacoes: [
    {
      id: novoId(),
      nome: 'termo',
      tipo: 'string',
      descricao: t(`${NS_EXEMPLO}.PASSOS.TRES.DESCRICAO_EXEMPLO`),
      podeFaltar: false,
    },
  ],
  cabecalhos: [{ ...novoCabecalho(), chave: 'x-api-key' }],
});

const ehAutomatico = cabecalho =>
  AUTOMATICOS.includes(
    String(cabecalho.key ?? '')
      .trim()
      .toLowerCase()
  );

export const paraRascunho = ferramenta => {
  const cabecalhos = ferramenta.headers_config || [];
  const mapeamento = ferramenta.response_mapping || {};
  return {
    nome: ferramenta.name || '',
    slug: ferramenta.slug || '',
    quando: ferramenta.description || '',
    metodo: ferramenta.http_method === 'POST' ? 'POST' : 'GET',
    endereco: ferramenta.endpoint_url || '',
    informacoes: (ferramenta.param_schema || []).map(p => ({
      id: novoId(),
      nome: p.name || '',
      tipo: TIPOS.includes(p.type) ? p.type : 'string',
      descricao: p.description || '',
      podeFaltar: p.required === false,
    })),
    corpo: ferramenta.request_body_template || '',
    mapeamento: mapeamento.template || '',
    mapeamentoOriginal: { ...mapeamento },
    automaticos: cabecalhos.filter(ehAutomatico).map(c => ({ ...c })),
    cabecalhos: cabecalhos
      .filter(c => !ehAutomatico(c))
      .map(c => {
        const guardado = Boolean(c.secret) && c.value === MASCARA_DO_SEGREDO;
        return {
          id: novoId(),
          chave: c.key || '',
          valor: guardado ? '' : c.value || '',
          segredo: Boolean(c.secret),
          guardado,
          chaveOriginal: guardado ? c.key : '',
        };
      }),
  };
};

const renomeado = cabecalho =>
  Boolean(cabecalho.guardado) &&
  String(cabecalho.chave ?? '').trim() !== cabecalho.chaveOriginal;

// O backend casa o segredo guardado pela chave e só o preserva com secret=true. Renomear a chave ou
// desligar "É segredo" exige digitar o valor de novo (senão o mascarado vira o valor de verdade).
export const precisaRedigitar = cabecalho =>
  renomeado(cabecalho) || (Boolean(cabecalho.guardado) && !cabecalho.segredo);

// Segredo guardado, intocado: volta a máscara com a mesma chave e o backend mantém o valor.
const mantemGuardado = cabecalho =>
  cabecalho.segredo &&
  cabecalho.guardado &&
  !cabecalho.trocando &&
  !precisaRedigitar(cabecalho);

const cabecalhoParaApi = cabecalho => {
  const key = String(cabecalho.chave).trim();
  if (mantemGuardado(cabecalho)) {
    return { key, value: MASCARA_DO_SEGREDO, secret: true };
  }
  return {
    key,
    value: cabecalho.valor ?? '',
    secret: Boolean(cabecalho.segredo),
  };
};

const mapeamentoParaApi = rascunho => {
  const { template, ...resto } = rascunho.mapeamentoOriginal || {};
  return preenchido(rascunho.mapeamento)
    ? { ...resto, template: rascunho.mapeamento }
    : resto;
};

export const paraApi = rascunho => ({
  name: rascunho.nome.trim(),
  // Vazio: o backend usaria o parameterize do nome, que pode começar por número e ser recusado.
  slug: rascunho.slug.trim() || nomeTecnico(rascunho.nome),
  description: rascunho.quando.trim(),
  http_method: rascunho.metodo,
  endpoint_url: rascunho.endereco.trim(),
  request_body_template: rascunho.corpo,
  param_schema: rascunho.informacoes.map(i => ({
    name: i.nome.trim(),
    type: i.tipo,
    description: i.descricao,
    required: !i.podeFaltar,
  })),
  headers_config: [
    ...(rascunho.automaticos || []),
    ...rascunho.cabecalhos
      .filter(c => preenchido(c.chave))
      .map(cabecalhoParaApi),
  ],
  response_mapping: mapeamentoParaApi(rascunho),
});

const validarCabecalho = cabecalho => {
  if (!preenchido(cabecalho.chave)) return '';
  if (!chaveValida(cabecalho.chave.trim())) return 'CHAVE';
  if (preenchido(cabecalho.valor)) return '';
  if (precisaRedigitar(cabecalho)) return 'REDIGITAR';
  const pedeValor =
    cabecalho.segredo && (cabecalho.trocando || !cabecalho.guardado);
  return pedeValor ? 'VALOR' : '';
};

const VALIDACOES = {
  1: (rascunho, tentou) => {
    if (!preenchido(rascunho.nome)) return { erros: { nome: 'NOME' } };
    return { erros: {}, avisarQuando: !preenchido(rascunho.quando) && !tentou };
  },
  2: rascunho => {
    const erros = {};
    const endereco = conferirEndereco(rascunho.endereco);
    if (endereco) erros.endereco = endereco;
    if (preenchido(rascunho.slug) && !slugValido(rascunho.slug.trim())) {
      erros.slug = 'SLUG';
    }
    return { erros };
  },
  3: rascunho => ({
    erros: Object.fromEntries(
      rascunho.informacoes
        .map((info, i) => [
          `i${i}`,
          conferirNomeDaInformacao(info.nome, rascunho.informacoes, i),
        ])
        .filter(([, erro]) => erro)
    ),
  }),
  4: rascunho => ({
    erros: Object.fromEntries(
      rascunho.cabecalhos
        .map((cabecalho, i) => [`c${i}`, validarCabecalho(cabecalho)])
        .filter(([, erro]) => erro)
    ),
  }),
};

// Devolve os erros por campo (chaves de i18n) e, no passo 1, se o aviso de "Quando usar" aparece.
export const validarPasso = (passo, rascunho, tentou = false) =>
  VALIDACOES[passo](rascunho, tentou);

const ondeEsta = (nome, doEndereco, doCorpo) => {
  if (doEndereco.includes(nome)) return 'ENDERECO';
  return doCorpo.includes(nome) ? 'CORPO' : 'CABECALHO';
};

// Dois lados: {{variável}} sem informação (a chamada falha) e informação que não vai a lugar nenhum.
export const avisosDasInformacoes = rascunho => {
  const doEndereco = variaveisEm(rascunho.endereco);
  const doCorpo = rascunho.metodo === 'POST' ? variaveisEm(rascunho.corpo) : [];
  // Segredo não entra: o valor guardado não volta para a tela.
  const dosCabecalhos = (rascunho.cabecalhos || [])
    .filter(c => !c.segredo)
    .flatMap(c => variaveisEm(c.valor));
  const usadas = [...doEndereco, ...doCorpo, ...dosCabecalhos];
  const lista = rascunho.informacoes || [];
  const nomes = lista.map(i => String(i.nome ?? '').trim());
  const faltando = usadas.find(v => !nomes.includes(v));
  const naoUsadas = nomes.filter(
    (nome, i) =>
      nome &&
      !conferirNomeDaInformacao(nome, lista, i) &&
      !usadas.includes(nome)
  );
  return {
    semInformacao: faltando
      ? {
          onde: ondeEsta(faltando, doEndereco, doCorpo),
          nome: faltando,
        }
      : null,
    naoUsadas,
  };
};

// O 422 traz full_messages: o começo da frase diz o atributo e, com ele, o passo provável.
export const passosProvaveisDoErro = mensagem => {
  const texto = String(mensagem ?? '');
  const comeca = prefixos => prefixos.some(p => texto.startsWith(p));
  if (comeca(['Endpoint url', 'Slug', 'Http method'])) return [2];
  if (comeca(['Param schema', 'Request body'])) return [3];
  if (comeca(['Headers config'])) return [4];
  return [2, 3];
};

// Rascunho sem os ids dos cartões: serve para saber se algo mudou.
const semId = ({ id, ...resto }) => resto;
export const conteudoDoRascunho = rascunho =>
  JSON.stringify({
    ...rascunho,
    informacoes: (rascunho.informacoes || []).map(semId),
    cabecalhos: (rascunho.cabecalhos || []).map(semId),
  });

// Segredo guardado cujo nome foi apagado: sair do envio apaga a chave, então a tela pergunta antes.
export const segredosSemNome = rascunho =>
  (rascunho.cabecalhos || []).filter(c => c.guardado && !preenchido(c.chave));
