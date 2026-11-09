// #1301 — regras das Ferramentas do agente (protótipo ferramentas.html). Endereço, nomes e corpo
// são lidos com métodos de string e com o parser URL do navegador: nada de regex.

// O mesmo valor de Autonomia::Agents::Tool.masked_header_value: a API devolve o segredo assim e,
// no PATCH, o ToolsController troca esse valor pelo guardado quando a chave é a mesma.
export const MASCARA_DO_SEGREDO = '••••••••';
export const TIPOS = ['string', 'number', 'integer', 'boolean'];
// #1430: a pessoa diz primeiro o que o agente descobre na conversa e depois cola o link, tocando na
// informação para encaixá-la (sem digitar {{ }}).
export const PASSOS = ['O_QUE_FAZ', 'PREENCHE', 'PARA_ONDE', 'COMO_ENTRA'];

// O HttpExecutor já põe Accept e Content-Type: a tela não os mostra, mas os guarda como vieram.
const AUTOMATICOS = ['content-type', 'accept'];
const LETRAS = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
const PERMITIDOS = `${LETRAS}0123456789_`;
// O exemplo vem do i18n, para o pacote da conta trocar (#1802). As chaves e o filtro ficam no código:
// "{" e "|" têm significado no vue-i18n.
const NS_EXEMPLO = 'AGENTS.JORNADA.PAGINA.FERRAMENTAS';
const VARIAVEL_DO_EXEMPLO = '?termo={{termo}}';
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
// Decisão do Rodrigo (09/11): senha no link fica legível para quem tem a chave; o lugar dela é a Chave de acesso. Mesma
// lista do backend (`SegredosDaChamada::NOMES_DE_CREDENCIAL`), lida pelo parser de URL do navegador, sem regex. Valor
// com {{ }} vem da conversa e vale.
const NOMES_DE_CREDENCIAL = [
  'token',
  'api_key',
  'apikey',
  'key',
  'secret',
  'password',
  'senha',
  'access_token',
];
const senhaNoLink = url =>
  Boolean(url.username || url.password) ||
  [...url.searchParams].some(
    ([nome, valor]) =>
      preenchido(valor) &&
      !valor.includes('{{') &&
      NOMES_DE_CREDENCIAL.includes(nome.toLowerCase())
  );

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
  if (senhaNoLink(url)) return 'SENHA';
  return '';
};

export const hostDoEndereco = endereco => {
  try {
    return new URL(String(endereco).trim()).hostname;
  } catch {
    return String(endereco ?? '');
  }
};

// Informação nova: o rótulo vazio é o que falta. Salva: o nome técnico (de antes do rótulo) vale.
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

// rotulo: o nome de gente ("CEP"), que a tela mostra. nome: o técnico, que vai no link; numa
// informação nova sai do rótulo, numa salva fica fixo (mudar quebraria o link já montado).
export const novaInformacao = () => ({
  id: novoId(),
  rotulo: '',
  nome: '',
  fixo: false,
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
      rotulo: t(`${NS_EXEMPLO}.RASCUNHO_EXEMPLO.INFORMACAO`),
      nome: 'termo',
      fixo: true,
      tipo: 'string',
      descricao: t(`${NS_EXEMPLO}.PASSOS.TRES.DESCRICAO_EXEMPLO`),
      podeFaltar: false,
    },
  ],
  cabecalhos: [{ ...novoCabecalho(), chave: 'x-api-key' }],
});

export const mudarRotulo = (informacao, rotulo) => ({
  ...informacao,
  rotulo,
  nome:
    informacao.fixo || !preenchido(rotulo)
      ? (informacao.fixo && informacao.nome) || ''
      : nomeTecnico(rotulo),
});

// O nome de gente de uma informação pelo nome técnico; sem informação com esse nome, o próprio nome.
const rotuloDe = (nome, informacoes) => {
  const achada = (informacoes || []).find(i => i.nome === nome);
  return (achada && preenchido(achada.rotulo) && achada.rotulo) || nome;
};

// O link como a pessoa lê: cada {{ informação }} vira [Rótulo].
export const enderecoLegivel = (endereco, informacoes) => {
  const partes = String(endereco ?? '').split('{{');
  return partes.slice(1).reduce((saida, pedaco) => {
    const fim = pedaco.indexOf('}}');
    if (fim < 0) return `${saida}{{${pedaco}`;
    const nome = pedaco.slice(0, fim).split('|')[0].trim();
    return `${saida}[${rotuloDe(nome, informacoes)}]${pedaco.slice(fim + 2)}`;
  }, partes[0]);
};

// O que vale entre colchetes no campo do link: o rótulo de cada informação e, para variável do link sem
// informação no passo 2, o próprio nome. O nome técnico de uma informação não vale: filter[status] é do link.
const marcasDoLink = (informacoes, endereco) => {
  const marcas = new Map(
    variaveisEm(endereco).map(nome => [
      String(rotuloDe(nome, informacoes)).trim(),
      nome,
    ])
  );
  (informacoes || [])
    .filter(i => preenchido(i.nome) && preenchido(i.rotulo))
    .forEach(i => marcas.set(i.rotulo.trim(), i.nome));
  return marcas;
};

// Troca cada [x] do texto: `trocar(x)` devolve o substituto, ou null para deixar como está.
const trocarColchetes = (texto, trocar) => {
  const partes = String(texto ?? '').split('[');
  return partes.slice(1).reduce((saida, pedaco) => {
    const fim = pedaco.indexOf(']');
    const novo = fim < 0 ? null : trocar(pedaco.slice(0, fim));
    return novo === null
      ? `${saida}[${pedaco}`
      : `${saida}${novo}${pedaco.slice(fim + 1)}`;
  }, partes[0]);
};

// O campo do link nunca mostra {{ }} (pedido da coordenadora, 09/11): cada {{ informação }} aparece como [Rótulo].
// Variável com filtro além de url_encode (o backend já codifica pela posição) fica crua, para não perder o filtro.
// Colchete do próprio link igual a um rótulo vira %5B…%5D (o mesmo para o outro sistema), para a volta não confundir.
export const enderecoNaTela = (endereco, informacoes) => {
  const marcas = marcasDoLink(informacoes, endereco);
  const literal = texto =>
    trocarColchetes(texto, x => (marcas.has(x.trim()) ? `%5B${x}%5D` : null));
  const partes = String(endereco ?? '').split('{{');
  return partes.slice(1).reduce((saida, pedaco) => {
    const fim = pedaco.indexOf('}}');
    if (fim < 0) return `${saida}{{${literal(pedaco)}`;
    const [nome, ...filtros] = pedaco
      .slice(0, fim)
      .split('|')
      .map(p => p.trim());
    const depois = literal(pedaco.slice(fim + 2));
    if (!nome || !filtros.every(f => f === 'url_encode')) {
      return `${saida}{{${pedaco.slice(0, fim + 2)}${depois}`;
    }
    return `${saida}[${rotuloDe(nome, informacoes)}]${depois}`;
  }, literal(partes[0]));
};

// O caminho de volta: [Rótulo] de uma informação, ou [nome] de uma variável que o link já tinha, vira {{nome}}.
// Colchete que não é informação ([1], filter[status]) fica como está.
export const enderecoDaTela = (texto, informacoes, anterior) => {
  const marcas = marcasDoLink(informacoes, anterior);
  return trocarColchetes(texto, x => {
    const nome = marcas.get(x.trim());
    return nome ? `{{${nome}}}` : null;
  });
};

// Encaixa o trecho onde o cursor está (no lugar do que estiver selecionado); sem posição, no fim.
// Devolve o texto e onde o cursor fica.
export const inserirNoCursor = (texto, posicao, trecho, fimDaSelecao) => {
  const atual = String(texto ?? '');
  const onde =
    Number.isInteger(posicao) && posicao >= 0 && posicao <= atual.length
      ? posicao
      : atual.length;
  const ate =
    Number.isInteger(fimDaSelecao) &&
    fimDaSelecao >= onde &&
    fimDaSelecao <= atual.length
      ? fimDaSelecao
      : onde;
  return {
    texto: `${atual.slice(0, onde)}${trecho}${atual.slice(ate)}`,
    cursor: onde + trecho.length,
  };
};

// "Mandar informação": o que vai junto já nasce com todas as informações. Número e sim/não sem
// aspas; o que pode faltar vai entre aspas, para o vazio não quebrar o formato.
const SEM_ASPAS = ['number', 'integer', 'boolean'];
export const corpoPadrao = informacoes => {
  const validas = (informacoes || []).filter(i => preenchido(i.nome));
  if (!validas.length) return '';
  const linhas = validas.map(i => {
    const variavel = `{{${i.nome}}}`;
    const valor =
      SEM_ASPAS.includes(i.tipo) && !i.podeFaltar ? variavel : `"${variavel}"`;
    return `  "${i.nome}": ${valor}`;
  });
  return `{\n${linhas.join(',\n')}\n}`;
};

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
      rotulo: p.label || p.name || '',
      nome: p.name || '',
      fixo: true,
      tipo: TIPOS.includes(p.type) ? p.type : 'string',
      descricao: p.description || '',
      podeFaltar: p.required === false,
    })),
    corpo: ferramenta.request_body_template || '',
    // Para saber se o link ou o método mudou: a chave guardada não vai para um destino novo.
    destinoOriginal: {
      endereco: ferramenta.endpoint_url || '',
      metodo: ferramenta.http_method === 'POST' ? 'POST' : 'GET',
    },
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

// Decisão do Rodrigo (09/11): mudou o link ou o método, a chave guardada é digitada de novo (o backend recusa a
// chave guardada num destino novo). Ferramenta nova não tem destino original.
export const destinoMudou = rascunho =>
  Boolean(rascunho.destinoOriginal) &&
  (String(rascunho.endereco ?? '').trim() !==
    rascunho.destinoOriginal.endereco ||
    rascunho.metodo !== rascunho.destinoOriginal.metodo);

// O backend casa o segredo guardado pela chave e só o preserva com secret=true. Renomear a chave ou
// desligar "É segredo" exige digitar o valor de novo (senão o mascarado vira o valor de verdade).
export const precisaRedigitar = (cabecalho, mudouDestino = false) =>
  renomeado(cabecalho) ||
  (Boolean(cabecalho.guardado) && (!cabecalho.segredo || mudouDestino));

// Segredo guardado, intocado: volta a máscara com a mesma chave e o backend mantém o valor.
const mantemGuardado = (cabecalho, mudouDestino) =>
  cabecalho.segredo &&
  cabecalho.guardado &&
  !cabecalho.trocando &&
  !precisaRedigitar(cabecalho, mudouDestino);

const cabecalhoParaApi = (cabecalho, mudouDestino) => {
  const key = String(cabecalho.chave).trim();
  if (mantemGuardado(cabecalho, mudouDestino)) {
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
    label: String(i.rotulo ?? '').trim(),
    type: i.tipo,
    description: i.descricao,
    required: !i.podeFaltar,
  })),
  headers_config: [
    ...(rascunho.automaticos || []),
    ...rascunho.cabecalhos
      .filter(c => preenchido(c.chave))
      .map(c => cabecalhoParaApi(c, destinoMudou(rascunho))),
  ],
  response_mapping: mapeamentoParaApi(rascunho),
});

const validarCabecalho = (cabecalho, mudouDestino) => {
  if (!preenchido(cabecalho.chave)) return '';
  if (!chaveValida(cabecalho.chave.trim())) return 'CHAVE';
  if (preenchido(cabecalho.valor)) return '';
  if (precisaRedigitar(cabecalho, mudouDestino)) return 'REDIGITAR';
  const pedeValor =
    cabecalho.segredo && (cabecalho.trocando || !cabecalho.guardado);
  return pedeValor ? 'VALOR' : '';
};

// Informação com rótulo apagado conta como sem nome (a de antes do #1430 não tem rótulo).
const semRotulo = info => 'rotulo' in info && !preenchido(info.rotulo);

// O rótulo vira [Rótulo] no campo do link: com colchete ele não volta, e repetido (sem olhar maiúscula)
// faria um [CEP] valer por duas informações.
const comparavel = rotulo =>
  String(rotulo ?? '')
    .trim()
    .toLocaleLowerCase();
const conferirRotulo = (info, lista, indice) => {
  if (!preenchido(info.rotulo)) return '';
  if (info.rotulo.includes('[') || info.rotulo.includes(']')) return 'COLCHETE';
  const repetido = lista.some(
    (item, j) =>
      j !== indice &&
      preenchido(item.rotulo) &&
      comparavel(item.rotulo) === comparavel(info.rotulo)
  );
  return repetido ? 'REPETIDO' : '';
};

const VALIDACOES = {
  1: (rascunho, tentou) => {
    if (!preenchido(rascunho.nome)) return { erros: { nome: 'NOME' } };
    return { erros: {}, avisarQuando: !preenchido(rascunho.quando) && !tentou };
  },
  3: rascunho => {
    const erros = {};
    const endereco = conferirEndereco(rascunho.endereco);
    if (endereco) erros.endereco = endereco;
    if (preenchido(rascunho.slug) && !slugValido(rascunho.slug.trim())) {
      erros.slug = 'SLUG';
    }
    return { erros };
  },
  2: rascunho => ({
    erros: Object.fromEntries(
      rascunho.informacoes
        .map((info, i) => [
          `i${i}`,
          conferirNomeDaInformacao(
            semRotulo(info) ? '' : info.nome,
            rascunho.informacoes,
            i
          ) || conferirRotulo(info, rascunho.informacoes, i),
        ])
        .filter(([, erro]) => erro)
    ),
  }),
  4: rascunho => ({
    erros: Object.fromEntries(
      rascunho.cabecalhos
        .map((cabecalho, i) => [
          `c${i}`,
          validarCabecalho(cabecalho, destinoMudou(rascunho)),
        ])
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

// O 422 do salvar traz os campos recusados (`campos`, nomes do model): cada um aponta o passo dele. Sem campos
// conhecidos, os dois passos prováveis.
const PASSO_DO_CAMPO = {
  param_schema: 2,
  endpoint_url: 3,
  slug: 3,
  http_method: 3,
  request_body_template: 3,
  response_mapping: 3,
  headers_config: 4,
};
export const passosProvaveisDoErro = (campos = []) => {
  const passos = (campos || [])
    .map(campo => PASSO_DO_CAMPO[campo])
    .filter(Boolean);
  const unicos = passos.filter((n, i) => passos.indexOf(n) === i).sort();
  return unicos.length ? unicos : [2, 3];
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
