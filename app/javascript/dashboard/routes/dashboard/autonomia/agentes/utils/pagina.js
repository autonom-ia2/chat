// #1181 PR3 — regras da página do agente (protótipo T07–T17) que não dependem de tela.

import { ESTADO } from './estadoDoAgente';

export const GAVETA = {
  TESTAR: 'testar',
  SABE: 'sabe',
  ONDE: 'onde',
  VOLTAR: 'voltar',
  CONVERSAS: 'conversas',
  FOTO: 'foto',
  VERSOES: 'versoes',
  INSTRUCOES: 'instrucoes',
};

// O `:tab` da página antiga (links do Guia, da Central e de favoritos) abre a gaveta equivalente.
// Ajustar e Publicar viram a própria página: o que elas faziam está nos blocos e no interruptor.
const GAVETA_DA_ABA = {
  test: GAVETA.TESTAR,
  knowledge: GAVETA.SABE,
  channels: GAVETA.ONDE,
  performance: GAVETA.CONVERSAS,
};

export const gavetaDaAba = aba => GAVETA_DA_ABA[aba] || null;

const TIPO_COTACAO = 'insurance_quote';

export const ehCotacao = agente => agente?.agent_type === TIPO_COTACAO;
export const ehManual = agente => agente?.mode === 'manual';
export const ehInterno = agente => agente?.actuation === 'internal';

// Estado de operação na página: o agente de cotação também atende ou está parado (o cartão da lista
// mostra "Cotação", mas a página precisa do interruptor certo). Mesma regra de Agent#operating?.
export const estadoDeOperacao = agente => {
  if (!agente?.status || agente.status === 'draft')
    return ESTADO.FALTA_TERMINAR;
  if (agente.status === 'active' && agente.enabled === true) {
    return ESTADO.ATENDENDO;
  }
  return ESTADO.PARADO;
};

// Mudar conversando usa o Construtor: não serve a quem escreve à mão (o Construtor sobrescreveria a
// instrução) nem à cotação (instrução mantida pelo módulo, o backend responde 422).
export const podeMudarConversando = agente =>
  !ehManual(agente) && !ehCotacao(agente);

// Gavetas que cada tipo de agente e cada papel podem abrir. Quem só vê testa e lê; a cotação mostra
// só nome, foto, horário, estado e números; o interno não tem canal.
export const gavetasPermitidas = (agente, podeGerenciar) => {
  if (ehCotacao(agente)) {
    return podeGerenciar ? [GAVETA.ONDE, GAVETA.VOLTAR, GAVETA.FOTO] : [];
  }
  const leitura = [GAVETA.TESTAR, GAVETA.SABE, GAVETA.VERSOES];
  if (!podeGerenciar) return leitura;
  const escrita = [
    GAVETA.CONVERSAS,
    GAVETA.FOTO,
    GAVETA.INSTRUCOES,
    ...(ehInterno(agente) ? [] : [GAVETA.ONDE, GAVETA.VOLTAR]),
  ];
  return [...leitura, ...escrita];
};

export const QUANDO = ['always', 'business_hours', 'outside_business_hours'];

export const quandoDoAgente = agente => {
  const janela = agente?.config?.response_window;
  return QUANDO.includes(janela) ? janela : 'always';
};

export const chaveDoQuando = janela =>
  (QUANDO.includes(janela) ? janela : 'always').toUpperCase();

// Arquivos e sites (protótipo T09): o limite de 25 MB bate com Source::MAX_FILE_BYTES.
export const MAX_ARQUIVO = 25 * 1024 * 1024;
export const MAX_FONTES = 30;
export const MAX_FOTO = 5 * 1024 * 1024;
export const TIPOS_FOTO = ['image/png', 'image/jpeg'];
export const MAX_INSTRUCAO = 50000;

// Endereço de site digitado pela pessoa: aceita sem "https://", exige um domínio com ponto e nada
// de espaço. Lido pelo URL do navegador, sem expressão regular.
export const enderecoDoSite = valor => {
  const texto = (valor || '').trim();
  if (!texto || texto.includes(' ')) return null;
  try {
    const url = new URL(texto.includes('://') ? texto : `https://${texto}`);
    const { hostname } = url;
    if (!['http:', 'https:'].includes(url.protocol)) return null;
    if (!hostname.includes('.') || hostname.endsWith('.')) return null;
    return url.href;
  } catch {
    return null;
  }
};

const ESTADO_LENDO = ['pending', 'processing'];

// Estado de um arquivo ou site para quem lê (sem nota, confiança nem percentual): lendo, pronto ou
// "não consegui ler" (falha na leitura ou o Revisor pediu outro arquivo).
export const estadoDaFonte = fonte => {
  if (fonte?.status === 'failed' || fonte?.review?.status === 'needs_resend') {
    return 'falha';
  }
  if (ESTADO_LENDO.includes(fonte?.status)) return 'lendo';
  return 'pronto';
};

export const ehSite = fonte => fonte?.source_type === 'link';

export const nomeDaFonte = fonte =>
  fonte?.reference || fonte?.external_link || '';

// Frase de cada versão da instrução (DECISOES.md item 6): só o que a API tem.
const MOTIVOS = {
  kb_refresh: 'KB_REFRESH',
  manual_edit: 'MANUAL_EDIT',
  rollback: 'ROLLBACK',
};
export const chaveDoMotivo = motivo => MOTIVOS[motivo] || null;

// Texto que vai para a conversa de mudar quando o teste respondeu errado (protótipo wrongDraft).
const FIM_DE_FRASE = ['.', '?', '!'];
export const fecharFrase = texto => {
  const limpo = (texto || '').trim();
  if (!limpo) return '';
  return FIM_DE_FRASE.includes(limpo.slice(-1)) ? limpo : `${limpo}.`;
};

// O locale do i18n vem como "pt_BR"; o Intl do navegador quer "pt-BR".
export const idiomaDoNavegador = locale =>
  (locale || 'en').split('_').join('-');
