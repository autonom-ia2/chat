// Modelo como a Meta devolve (lista sincronizada da caixa + perfil do Chat2You,
// API do #1330) → Modelo no formato da tela (ver ./modelosWhatsapp.js).
// Lê só o que existe: o que a Meta não informa (quando foi enviado, desde quando
// está pausado, quantas alterações restam) fica null e a tela não inventa.
// Sem expressão regular (regra do Rodrigo): o texto é lido com indexOf/slice.
import { campoDoPerfil } from '../helpers/campos';

const ABRE = '{{';
const FECHA = '}}';

const SITUACOES = {
  APPROVED: 'pronto',
  PENDING: 'em_analise',
  IN_APPEAL: 'em_analise',
  REJECTED: 'recusado',
  PAUSED: 'pausado',
  DISABLED: 'pausado',
  LIMIT_EXCEEDED: 'pausado',
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
const componente = (template, tipo) =>
  (template.components || []).find(item => maiusculo(item.type) === tipo);

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
    return { tipo: 'site', texto: botao.text || '', valor: botao.url || '' };
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

const ofertaDe = (template, botoes) => {
  const oferta = componente(template, 'LIMITED_TIME_OFFER');
  const cupom = botoes.find(botao => maiusculo(botao.type) === 'COPY_CODE');
  const link = botoes.find(botao => maiusculo(botao.type) === 'URL');
  return {
    titulo: oferta?.limited_time_offer?.text || '',
    terminaEm: '',
    link: link?.url || '',
    cupom: cupom?.example || '',
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
  if (componente(template, 'CAROUSEL')) return 'carrossel';
  if (componente(template, 'LIMITED_TIME_OFFER')) return 'oferta';
  const tipos = botoesDe(componente(template, 'BUTTONS')).map(botao =>
    maiusculo(botao.type)
  );
  if (tipos.includes('FLOW')) return 'formulario';
  if (tipos.includes('CATALOG') || tipos.includes('MPM')) return 'catalogo';
  return 'padrao';
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
  };
  return { conteudo, campos };
};

// Motivo da recusa: o que a Meta disse ou, quando ela diz só "formato inválido",
// o que dá para ver no próprio texto (campo no começo, no fim, exemplo faltando).
export const recusaDe = (template, conteudo) => {
  const motivo = maiusculo(template.rejected_reason);
  if (RECUSAS[motivo]) return { codigo: RECUSAS[motivo] };
  if (motivo !== 'INVALID_FORMAT') return { codigo: 'outro' };
  const pedacos = conteudo.texto.filter(
    pedaco => pedaco.t === 'campo' || pedaco.v.trim()
  );
  if (pedacos[pedacos.length - 1]?.t === 'campo')
    return { codigo: 'campo_no_fim' };
  if (pedacos[0]?.t === 'campo') return { codigo: 'campo_no_inicio' };
  const semExemplo = Object.values(conteudo.exemplos).some(valor => !valor);
  return { codigo: semExemplo ? 'exemplo_faltando' : 'formato_invalido' };
};

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
    biblioteca: false,
    sistema: Boolean(template.system_owner),
    idioma: template.language,
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
    enviosNoMes: grupo.envios ? grupo.envios[template.name] || 0 : null,
    enviadoEm: null,
    edicoes: { restantesNoMes: null, liberadaEm: null },
    template,
  };
};
