// Modelo como a Meta devolve (lista sincronizada da caixa + perfil do Chat2You,
// API do #1330) → Modelo no formato da tela (ver ./modelosWhatsapp.js).
// Lê só o que existe: o que a Meta não informa (quando foi enviado, desde quando
// está pausado, quantas alterações restam) fica null e a tela não inventa.
// Sem expressão regular (regra do Rodrigo): o texto é lido com indexOf/slice.
import { campoDoPerfil } from '../helpers/campos';
import { codigoDeExemploValido } from '../helpers/regraEstrutural';
import { pedidoDeProdutos } from '../helpers/produtosNaCampanha';

const ABRE = '{{';
const FECHA = '}}';

const SITUACOES = {
  APPROVED: 'pronto',
  PENDING: 'em_analise',
  IN_APPEAL: 'em_analise',
  REJECTED: 'recusado',
  PAUSED: 'pausado',
  DISABLED: 'desativado',
  // A conta do WhatsApp chegou ao limite de modelos: este não chegou a ser criado.
  LIMIT_EXCEEDED: 'limite',
};
// Já pedido para apagar na Meta: não aparece mais na lista.
export const SITUACOES_FORA_DA_LISTA = ['PENDING_DELETION', 'DELETED'];

const TIPOS = {
  MARKETING: 'divulgacao',
  UTILITY: 'aviso',
  AUTHENTICATION: 'codigo',
};

const TOPOS = { IMAGE: 'foto', VIDEO: 'video', DOCUMENT: 'documento' };

// Motivo de recusa da Meta → texto da tela (MODELOS_WHATSAPP.RECUSAS).
const RECUSAS = {
  INCORRECT_CATEGORY: 'parece_divulgacao',
  TAG_CONTENT_MISMATCH: 'parece_divulgacao',
  PROMOTIONAL: 'parece_divulgacao',
  ABUSIVE_CONTENT: 'conteudo_proibido',
  SCAM: 'conteudo_proibido',
};

const maiusculo = valor => String(valor || '').toUpperCase();

// Qualidade que o WhatsApp dá ao modelo (quality_score.score) → sinal da tela.
// UNKNOWN ou ausente: ainda sem retorno das pessoas.
const SINAIS_DA_META = { GREEN: 'bom', YELLOW: 'atencao', RED: 'ruim' };

// A Graph manda { score, date }.
export const sinalDe = template =>
  SINAIS_DA_META[maiusculo(template.quality_score?.score)] || 'sem_nota';

const componente = (template, tipo) =>
  (template.components || []).find(item => maiusculo(item.type) === tipo);

// Saúde dos últimos 30 dias que a lista de modelos traz (`health`, #1338) → tela.
// Sem `health` (modelo recém-criado ou alterado, fora da lista): undefined, e a
// tela não mostra números em vez de dizer "não foi enviado".
export const saudeDe = health => {
  if (!health) return undefined;
  const { cost } = health;
  return {
    dias: health.days,
    enviadas: health.sent,
    entregues: health.delivered,
    lidas: health.read,
    responderam: health.replied,
    custo: cost
      ? { total: cost.total, porResposta: cost.per_reply, moeda: cost.currency }
      : null,
    mediaDeRespostas: health.average_reply_rate,
  };
};

// "Olá, {{1}}!" → [{ t: 'texto', v: 'Olá, ' }, { t: 'campo', v: <campo do 1> }, …]
export const lerCorpo = (texto, campoDe) => {
  const pedacos = [];
  let resto = texto || '';
  while (resto.length) {
    const inicio = resto.indexOf(ABRE);
    const fim = inicio === -1 ? -1 : resto.indexOf(FECHA, inicio);
    if (fim === -1) {
      pedacos.push({ t: 'texto', v: resto });
      break;
    }
    if (inicio > 0) pedacos.push({ t: 'texto', v: resto.slice(0, inicio) });
    pedacos.push({
      t: 'campo',
      v: campoDe(resto.slice(inicio + ABRE.length, fim).trim()),
    });
    resto = resto.slice(fim + FECHA.length);
  }
  return pedacos;
};

// O que a tela sabe editar sem perder nada: topo de texto, foto, vídeo ou
// documento; botões de resposta, site, ligar e copiar código; código de
// verificação de copiar. Modelo feito fora com outra coisa (topo de localização,
// botão de ligação por voz, preenchimento automático) não é alterado nem
// duplicado aqui: a conversão perderia essa parte sem aviso.
const TOPOS_EDITAVEIS = ['TEXT', 'IMAGE', 'VIDEO', 'DOCUMENT'];
const BOTOES_EDITAVEIS = ['QUICK_REPLY', 'URL', 'PHONE_NUMBER', 'COPY_CODE'];
const PREENCHIMENTO_AUTOMATICO = ['ONE_TAP', 'ZERO_TAP'];

// Variável → valor de exemplo que a Meta guardou (posicional ou com nome).
const exemplosDoCorpo = corpo => {
  const exemplo = corpo?.example || {};
  const nomeados = exemplo.body_text_named_params;
  if (Array.isArray(nomeados)) {
    return Object.fromEntries(
      nomeados.map(item => [item.param_name, item.example || ''])
    );
  }
  const posicionais = (exemplo.body_text || [])[0] || [];
  return Object.fromEntries(
    posicionais.map((valor, indice) => [String(indice + 1), valor || ''])
  );
};

const botaoDaMeta = botao => {
  const tipo = maiusculo(botao.type);
  if (tipo === 'URL') {
    // O exemplo do final variável ({{1}}) volta junto ao alterar ou duplicar.
    const exemplo = Array.isArray(botao.example)
      ? botao.example[0]
      : botao.example;
    return {
      tipo: 'site',
      texto: botao.text || '',
      valor: botao.url || '',
      ...(exemplo ? { exemplo } : {}),
    };
  }
  if (tipo === 'PHONE_NUMBER') {
    return {
      tipo: 'ligar',
      texto: botao.text || '',
      valor: botao.phone_number || '',
    };
  }
  if (tipo === 'COPY_CODE') {
    return {
      tipo: 'copiar_codigo',
      texto: botao.text || '',
      valor: botao.example || '',
    };
  }
  return { tipo: 'resposta', texto: botao.text || '', valor: '' };
};

const botoesDe = componenteDeBotoes => componenteDeBotoes?.buttons || [];

const topoDe = (template, perfil) => {
  const topo = componente(template, 'HEADER');
  const formato = maiusculo(topo?.format);
  if (formato === 'TEXT') {
    return {
      tipo: 'texto',
      arquivo: '',
      texto: topo.text || '',
      componente: topo,
    };
  }
  if (!TOPOS[formato]) return { tipo: 'nenhum', arquivo: '' };
  const midia = perfil.header_media || {};
  return {
    tipo: TOPOS[formato],
    arquivo: midia.file_name || '',
    handle: midia.handle || '',
  };
};

const cartoesDe = carrossel =>
  (carrossel?.cards || []).map(cartao => {
    const partes = cartao.components || [];
    const topo = partes.find(item => maiusculo(item.type) === 'HEADER');
    const corpo = partes.find(item => maiusculo(item.type) === 'BODY');
    const botoes = partes.find(item => maiusculo(item.type) === 'BUTTONS');
    return {
      midia: maiusculo(topo?.format) === 'VIDEO' ? 'video' : 'foto',
      arquivo: '',
      texto: corpo?.text || '',
      botoes: botoesDe(botoes).map(botaoDaMeta),
    };
  });

// #1418: o que o celular mostra dos produtos — o tipo, o título do topo (vários),
// o rodapé e o botão (o do modelo ou o do cartão, no carrossel).
const produtosDe = (template, botoes) => {
  const pedido = pedidoDeProdutos(template);
  const cartao = componente(template, 'CAROUSEL')?.cards?.[0];
  const botaoDoCartao = botoesDe(
    (cartao?.components || []).find(item => maiusculo(item.type) === 'BUTTONS')
  )[0];
  const botao = pedido.tipo === 'carrossel' ? botaoDoCartao : botoes[0];
  const topo = componente(template, 'HEADER');
  return {
    tipo: pedido.tipo,
    titulo: maiusculo(topo?.format) === 'TEXT' ? topo.text || '' : '',
    rodape: componente(template, 'FOOTER')?.text || '',
    botao: {
      tipo: maiusculo(botao?.type) === 'URL' ? 'site' : 'ver',
      texto: botao?.text || '',
    },
  };
};

const ofertaDe = (template, botoes) => {
  const oferta = componente(template, 'LIMITED_TIME_OFFER');
  const cupom = botoes.find(botao => maiusculo(botao.type) === 'COPY_CODE');
  const link = botoes.find(botao => maiusculo(botao.type) === 'URL');
  return {
    titulo: oferta?.limited_time_offer?.text || '',
    link: link?.url || '',
    botao: link?.text || '',
    cupom:
      (Array.isArray(cupom?.example) ? cupom.example[0] : cupom?.example) || '',
  };
};

const codigoDe = template => {
  const corpo = componente(template, 'BODY');
  const rodape = componente(template, 'FOOTER');
  const otp = botoesDe(componente(template, 'BUTTONS')).find(
    botao => maiusculo(botao.type) === 'OTP'
  );
  return {
    botao: maiusculo(otp?.otp_type) === 'ONE_TAP' ? 'preencher' : 'copiar',
    validade: Number(rodape?.code_expiration_minutes) || 10,
    avisoDeSeguranca: Boolean(corpo?.add_security_recommendation),
  };
};

const formatoDe = template => {
  if (maiusculo(template.category) === 'AUTHENTICATION') return 'codigo';
  // #1418: um produto, vários ou carrossel de produtos do catálogo.
  if (pedidoDeProdutos(template)) return 'produtos';
  if (componente(template, 'CAROUSEL')) return 'carrossel';
  if (componente(template, 'LIMITED_TIME_OFFER')) return 'oferta';
  const tipos = botoesDe(componente(template, 'BUTTONS')).map(botao =>
    maiusculo(botao.type)
  );
  if (tipos.includes('FLOW')) return 'formulario';
  if (tipos.includes('CATALOG') || tipos.includes('MPM')) return 'catalogo';
  return 'padrao';
};

export const editavelNaTela = template => {
  const topo = componente(template, 'HEADER');
  if (topo && !TOPOS_EDITAVEIS.includes(maiusculo(topo.format))) return false;
  const botoes = botoesDe(componente(template, 'BUTTONS'));
  const formato = formatoDe(template);
  if (formato === 'codigo') {
    return !botoes.some(
      botao =>
        PREENCHIMENTO_AUTOMATICO.includes(maiusculo(botao.otp_type)) ||
        Array.isArray(botao.supported_apps)
    );
  }
  // Catálogo, formulário e produtos: a tela ainda não remonta esses botões.
  if (['catalogo', 'formulario', 'produtos'].includes(formato)) return false;
  if (formato !== 'padrao') return true;
  return botoes.every(botao =>
    BOTOES_EDITAVEIS.includes(maiusculo(botao.type))
  );
};

// O conteúdo na tela e o mapa variável → campo (para a campanha ligar sozinha).
// O perfil do Chat2You (fields, header_media) vem junto do modelo na API.
export const conteudoDaMeta = (template, perfil = template) => {
  const campos = {};
  const campoDe = chave => {
    const campo = campoDoPerfil((perfil.fields || {})[chave], chave);
    campos[chave] = campo;
    return campo;
  };
  const formato = formatoDe(template);
  const corpo = componente(template, 'BODY');
  const texto = formato === 'codigo' ? [] : lerCorpo(corpo?.text, campoDe);
  const exemplosDaMeta = exemplosDoCorpo(corpo);
  const exemplos = Object.fromEntries(
    Object.entries(campos).map(([chave, campo]) => [
      campo,
      exemplosDaMeta[chave] || '',
    ])
  );
  const botoes = botoesDe(componente(template, 'BUTTONS'));
  const conteudo = {
    formato,
    topo: topoDe(template, perfil),
    texto,
    exemplos,
    rodape:
      formato === 'padrao' ? componente(template, 'FOOTER')?.text || '' : '',
    botoes: formato === 'padrao' ? botoes.map(botaoDaMeta) : [],
    ...(formato === 'carrossel'
      ? { cartoes: cartoesDe(componente(template, 'CAROUSEL')) }
      : {}),
    ...(formato === 'oferta' ? { oferta: ofertaDe(template, botoes) } : {}),
    ...(formato === 'codigo' ? { codigo: codigoDe(template) } : {}),
    ...(formato === 'catalogo'
      ? { catalogo: { botao: botoes[0]?.text || '' } }
      : {}),
    ...(formato === 'formulario'
      ? { formulario: { id: '', botao: botoes[0]?.text || '' } }
      : {}),
    ...(formato === 'produtos'
      ? { produtos: produtosDe(template, botoes) }
      : {}),
  };
  return { conteudo, campos };
};

// Motivo da recusa: o que a Meta disse ou, quando ela diz só "formato inválido",
// o que dá para ver no próprio modelo (botão "Copiar código" sem código, campo
// no começo, no fim, exemplo faltando).
export const recusaDe = (template, conteudo) => {
  const motivo = maiusculo(template.rejected_reason);
  if (RECUSAS[motivo]) return { codigo: RECUSAS[motivo] };
  if (motivo !== 'INVALID_FORMAT') return { codigo: 'outro' };
  const copiarSemCodigo = (conteudo.botoes || []).some(
    botao =>
      botao.tipo === 'copiar_codigo' && !codigoDeExemploValido(botao.valor)
  );
  if (copiarSemCodigo) return { codigo: 'botao_copiar_codigo' };
  const pedacos = conteudo.texto.filter(
    pedaco => pedaco.t === 'campo' || pedaco.v.trim()
  );
  if (pedacos[pedacos.length - 1]?.t === 'campo')
    return { codigo: 'campo_no_fim' };
  if (pedacos[0]?.t === 'campo') return { codigo: 'campo_no_inicio' };
  const semExemplo = Object.values(conteudo.exemplos).some(valor => !valor);
  return { codigo: semExemplo ? 'exemplo_faltando' : 'formato_invalido' };
};

// Arquivo guardado de cada cartão, na posição do cartão (null onde não há).
const cartoesGuardadosDe = (lista = []) =>
  (lista || []).reduce((guardados, midia) => {
    const copia = [...guardados];
    copia[midia.card_index] = { nome: midia.file_name };
    return copia;
  }, []);

// grupo: { id (caixa que fala com a Meta), conta: { id, nome }, numeros: [inbox_id], envios: { nome: n } }
export const modeloDaMeta = (template, grupo) => {
  const { conteudo, campos } = conteudoDaMeta(template);
  // Situação que a tela não conhece: tratada como pausada, que não deixa usar em
  // campanha (melhor travar do que agendar um envio que a Meta pode recusar).
  const situacao = SITUACOES[maiusculo(template.status)] || 'pausado';
  const tipo = TIPOS[maiusculo(template.category)] || 'aviso';
  const anterior = maiusculo(template.previous_category);
  return {
    id: String(template.id),
    nome: template.friendly_name || template.name,
    nomeNoWhatsapp: template.name,
    objetivo: conteudo.formato === 'padrao' ? 'em_branco' : conteudo.formato,
    sistema: Boolean(template.system_owner),
    donoDoSistema: template.system_owner || '',
    editavel: editavelNaTela(template),
    idioma: template.language,
    // Variáveis com nome ({{primeiro_nome}}) continuam com nome ao alterar.
    formatoDosCampos:
      maiusculo(template.parameter_format) === 'NAMED' ? 'named' : 'positional',
    situacao,
    tipo,
    tipoMudouPeloWhatsapp:
      Boolean(anterior) && anterior !== maiusculo(template.category),
    conta: grupo.conta.id,
    caixa: grupo.id,
    numeros: grupo.numeros,
    conteudo,
    campos,
    recusa: situacao === 'recusado' ? recusaDe(template, conteudo) : null,
    pausa: situacao === 'pausado' ? { desde: null } : null,
    sinal: sinalDe(template),
    saude: saudeDe(template.health),
    enviosNoMes: grupo.envios ? grupo.envios[template.name] || 0 : null,
    enviadoEm: null,
    edicoes: { restantesNoMes: null, liberadaEm: null },
    cartoesGuardados: cartoesGuardadosDe(template.card_media),
    // #1465: o arquivo do topo guardado de fato (a campanha diz "vai a foto aprovada")
    // e, se for foto, o link de leitura assinado para a miniatura.
    topoGuardado: template.header_file_name
      ? {
          nome: template.header_file_name,
          url: template.header_file_preview_url || '',
        }
      : null,
    template,
  };
};
