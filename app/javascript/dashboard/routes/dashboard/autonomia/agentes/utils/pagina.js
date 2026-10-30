// #1181 PR3 — regras da página do agente (protótipo T07–T17) que não dependem de tela.

import { estadoDeAtendimento } from './estadoDoAgente';

export const GAVETA = {
  TESTAR: 'testar',
  SABE: 'sabe',
  ONDE: 'onde',
  VOLTAR: 'voltar',
  CONVERSAS: 'conversas',
  FOTO: 'foto',
  VERSOES: 'versoes',
  INSTRUCOES: 'instrucoes',
  AGENDA: 'agenda',
  FERRAMENTAS: 'ferramentas',
};

// O `:tab` da página antiga (links do Guia, da Central e de favoritos) abre a gaveta equivalente.
// Ajustar e Publicar viram a própria página: o que elas faziam está nos blocos e no interruptor.
const GAVETA_DA_ABA = {
  test: GAVETA.TESTAR,
  knowledge: GAVETA.SABE,
  channels: GAVETA.ONDE,
  performance: GAVETA.CONVERSAS,
  tools: GAVETA.FERRAMENTAS,
};

export const gavetaDaAba = aba => GAVETA_DA_ABA[aba] || null;

// #1370 — `?gaveta=<nome>` também abre uma gaveta: o :tab antigo não tem a agenda. É por onde a volta
// do assistente de páginas de CRM › Agendamento reabre "Marcar reuniões". A página tira a consulta
// da URL ao abrir (F5 não reabre). O :tab antigo vence quando os dois vêm.
export const gavetaDaUrl = (aba, consulta) =>
  gavetaDaAba(aba) ||
  (Object.values(GAVETA).includes(consulta) ? consulta : null);

const TIPO_COTACAO = 'insurance_quote';

export const ehCotacao = agente => agente?.agent_type === TIPO_COTACAO;
export const ehManual = agente => agente?.mode === 'manual';
export const ehInterno = agente => agente?.actuation === 'internal';

// Estado de operação na página: o agente de cotação também atende ou está parado (o cartão da lista
// mostra "Cotação", mas a página precisa do interruptor certo). A mesma regra da lista
// (estadoDeAtendimento): ativo, ligado e com onde trabalhar (#1366).
export const estadoDeOperacao = agente => estadoDeAtendimento(agente);

// Mudar conversando usa o Construtor: não serve a quem escreve à mão (o Construtor sobrescreveria a
// instrução) nem à cotação (instrução mantida pelo módulo, o backend responde 422).
export const podeMudarConversando = agente =>
  !ehManual(agente) && !ehCotacao(agente);

// O agente recebe a agenda da IA (#1196): o servidor manda `booking_available: false` quando não.
export const recebeAgenda = agente => agente?.booking_available !== false;

// Quem vê "Ferramentas": o mesmo critério da aba do painel antigo (AgentPanelPage) — usuário
// SuperAdmin que gerencia, em qualquer tipo de agente (cotação e interno inclusive). O backend
// (Agents::ToolsController) recusa quem não é SuperAdmin.
export const ehSuperAdmin = usuario => usuario?.type === 'SuperAdmin';

// Gavetas que cada tipo de agente e cada papel podem abrir. Quem só vê testa e lê; a cotação mostra
// só nome, foto, horário, estado e números; o interno não tem canal. A agenda (#1253) só abre para
// quem gerencia, com a agenda nova na conta e para o agente que recebe a agenda. Ferramentas, só
// para o SuperAdmin que gerencia.
export const gavetasPermitidas = (
  agente,
  podeGerenciar,
  { agendaNova = false, superAdmin = false } = {}
) => {
  const ferramentas = podeGerenciar && superAdmin ? [GAVETA.FERRAMENTAS] : [];
  if (ehCotacao(agente)) {
    return podeGerenciar
      ? [GAVETA.ONDE, GAVETA.VOLTAR, GAVETA.FOTO, ...ferramentas]
      : [];
  }
  const leitura = [GAVETA.TESTAR, GAVETA.SABE, GAVETA.VERSOES];
  if (!podeGerenciar) return leitura;
  const escrita = [
    GAVETA.CONVERSAS,
    GAVETA.FOTO,
    GAVETA.INSTRUCOES,
    ...(ehInterno(agente) ? [] : [GAVETA.ONDE, GAVETA.VOLTAR]),
    ...(agendaNova && recebeAgenda(agente) ? [GAVETA.AGENDA] : []),
    ...ferramentas,
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
// #1428 — criar e ajustar conversando dizem o mesmo. As versões 'base' (o estado de antes da primeira
// mudança conversando) e 'antes_de_voltar' (o estado de antes de uma volta) não têm frase: só data e hora.
const MOTIVOS = {
  builder_create: 'BUILDER',
  builder_adjust: 'BUILDER',
  kb_refresh: 'KB_REFRESH',
  manual_edit: 'MANUAL_EDIT',
  rollback: 'ROLLBACK',
  // #1429 F3 — "Atualizar com a nova base".
  base_de_seguros: 'BASE_DE_SEGUROS',
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

// #1369 — quando foi a última atividade de uma conversa. Nos últimos 7 dias (hoje e os 6 anteriores)
// o dia da semana não se repete, então basta ele e a hora ("seg., 20:59"); antes disso, a data
// ("28 de set., 20:59").
const DIAS_COM_NOME = 6;
const HORA = { hour: '2-digit', minute: '2-digit' };

export const quandoFoi = (segundos, idioma, agora = new Date()) => {
  const data = new Date(segundos * 1000);
  const inicio = new Date(agora);
  inicio.setHours(0, 0, 0, 0);
  inicio.setDate(inicio.getDate() - DIAS_COM_NOME);
  const formato =
    data >= inicio
      ? { weekday: 'short', ...HORA }
      : { day: 'numeric', month: 'short', ...HORA };
  return data.toLocaleString(idioma, formato);
};

// #1369 — de onde veio um jeito criado pelo "Voltar": o jeito anterior com o mesmo texto (mesmo
// instruction_hash), só quando há exatamente um. Com dois ou mais não dá para saber qual deles foi
// escolhido, e sem nenhum o jeito já saiu da lista (a API guarda os 50 mais novos): null, e a tela
// usa a frase genérica. `versoes` vem do mais novo para o mais antigo, como a API devolve.
export const origemDaVolta = (versao, versoes) => {
  if (versao?.reason !== 'rollback') return null;
  // A volta gravada depois do #1428 diz para qual versão foi; a de antes, só pelo texto.
  if (versao.voltou_para) {
    return versoes.find(item => item.id === versao.voltou_para) || null;
  }
  if (!versao.instruction_hash) return null;
  const posicao = versoes.indexOf(versao);
  const iguais = versoes
    .slice(posicao + 1)
    .filter(item => item.instruction_hash === versao.instruction_hash);
  return iguais.length === 1 ? iguais[0] : null;
};
