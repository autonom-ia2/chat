// #2283 — os grupos da Lista nova "o que fazer agora". O grupo de cada card em
// andamento vem do servidor (`action_group`, sort=acao); os números de cada
// grupo vêm de /crm/cards/summaries?group_by=acao, nunca do que já carregou.
import { FAILURE_STATUSES, SUCCESS_STATUSES } from '../../helpers/cardOutcome';

export const GRUPOS_DE_ACAO = ['esperando', 'retorno', 'ninguem', 'parado'];
export const GRUPOS_EM_ANDAMENTO = [...GRUPOS_DE_ACAO, 'demais'];
export const ORDEM_DOS_GRUPOS = [
  ...GRUPOS_EM_ANDAMENTO,
  'ganho',
  'perdido',
  'arquivado',
];
export const ABAS = ['aberto', 'ganho', 'perdido', 'arquivado', 'tudo'];

// Tom da etiqueta: texto n-slate-12, a cor só no fundo e no ícone.
export const TONS = {
  azul: { fundo: 'bg-n-blue-3', icone: 'text-n-blue-11' },
  ambar: { fundo: 'bg-n-amber-3', icone: 'text-n-amber-11' },
  vermelho: { fundo: 'bg-n-ruby-3', icone: 'text-n-ruby-11' },
  iris: { fundo: 'bg-n-iris-3', icone: 'text-n-iris-11' },
  cinza: { fundo: 'bg-n-slate-3 dark:bg-n-solid-3', icone: 'text-n-slate-11' },
  verde: { fundo: 'bg-n-teal-3', icone: 'text-n-teal-11' },
};

export const GRUPOS = {
  esperando: { tom: 'azul', icone: 'i-lucide-hourglass' },
  retorno: { tom: 'ambar', icone: 'i-lucide-clock' },
  ninguem: { tom: 'iris', icone: 'i-lucide-user-round' },
  parado: { tom: 'cinza', icone: 'i-lucide-pause' },
  demais: { tom: 'cinza', icone: 'i-lucide-align-left' },
  ganho: { tom: 'verde', icone: 'i-lucide-check' },
  perdido: { tom: 'cinza', icone: 'i-lucide-x' },
  arquivado: { tom: 'cinza', icone: 'i-lucide-archive' },
};

// Tabela pela largura da LISTA (não da janela). Cheia a partir de 1040 px;
// compacta entre 960 e 1040 px (janela de 1280 com a barra lateral aberta).
// A compacta tira largura dos botões e da situação para o nome do cliente
// nunca ficar espremido.
export const LARGURA_DA_TABELA = 960;
export const LARGURA_DA_TABELA_CHEIA = 1040;
export const COLUNAS = {
  cheia: {
    linha: 'grid-cols-[44px_minmax(0,1fr)_276px_452px]',
    botoes: 'grid-cols-[204px_144px_88px]',
  },
  // A 1ª vaga fica com a largura da cheia: "Passar para alguém" cabe inteiro.
  compacta: {
    linha: 'grid-cols-[44px_minmax(0,1fr)_216px_432px]',
    botoes: 'grid-cols-[204px_140px_72px]',
  },
};

// Aba "Mostrar" → parâmetro `result` da API. Ganhos e Perdidos seguem o tipo
// do funil (won/lost na venda, resolved/cancelled no Atender).
export const resultadoDaAba = (aba, statuses) =>
  ({
    aberto: 'open',
    ganho: statuses.success,
    perdido: statuses.failure,
    arquivado: 'archived',
    tudo: undefined,
  })[aba];

// Onde o card aparece: em andamento, o grupo do servidor; fechado, o desfecho.
export const grupoDoCard = card => {
  if (SUCCESS_STATUSES.includes(card.status)) return 'ganho';
  if (FAILURE_STATUSES.includes(card.status)) return 'perdido';
  if (card.status === 'archived') return 'arquivado';
  return GRUPOS_EM_ANDAMENTO.includes(card.action_group)
    ? card.action_group
    : 'demais';
};

// O card é "meu": sou o dono, ou ele não tem dono e a conversa é minha. A
// conversa minha esperando resposta também é minha, mesmo com outro dono
// (o mesmo critério do `mine=true` do servidor).
export const ehMeu = (card, meuId) => {
  if (!meuId) return false;
  const conversaMinha =
    String(card.conversation?.assignee_id ?? '') === String(meuId);
  if (String(card.owner_id ?? '') === String(meuId)) return true;
  if (!card.owner_id && conversaMinha) return true;
  return grupoDoCard(card) === 'esperando' && conversaMinha;
};

// A ação principal da linha. Cliente de colega: sem ação principal.
// "Feito" só com o id do retorno (next_follow_up_id).
export const acaoDoCard = (card, { meuId, podePassar, podeMexer }) => {
  const grupo = grupoDoCard(card);
  const meu = ehMeu(card, meuId);
  const acaoDeNinguem = () => {
    if (podePassar) return 'passar';
    return podeMexer ? 'ficar' : '';
  };
  if (grupo === 'esperando') {
    if (meu) return 'responder';
    // Esperando e ninguém cuidando (nem pessoa, nem robô, nem atendente de
    // conversa oculta): o caso mais urgente ganha a ação de "Ninguém cuidando"
    // (Rodrigo, 28/10, revisão leiga do #2324).
    const ninguemCuida = !card.current_responsible && !card.conversation_hidden;
    return ninguemCuida ? acaoDeNinguem() : '';
  }
  if (grupo === 'retorno')
    return meu && podeMexer && card.next_follow_up_id ? 'feito' : '';
  if (grupo === 'ninguem') return acaoDeNinguem();
  if (grupo === 'parado') return podeMexer ? 'combinar' : '';
  return '';
};

const URGENTES = ['responder', 'feito', 'combinar', 'passar', 'ficar'];

// Junta as linhas em grupos, na ordem. Azul cheio só no primeiro cliente meu
// com ação; contorno no resto. Grupo com 0 no servidor não aparece.
export const montarGrupos = ({
  cards,
  contagem,
  grupoSo,
  meuId,
  opcoes,
  tomDaLinha,
}) => {
  let cheioUsado = false;
  return ORDEM_DOS_GRUPOS.filter(grupo => !grupoSo || grupo === grupoSo)
    .map(grupo => {
      const doGrupo = cards.filter(card => grupoDoCard(card) === grupo);
      const linhas = doGrupo.map(card => {
        const acao = acaoDoCard(card, { meuId, ...opcoes });
        const cheio =
          !cheioUsado && ehMeu(card, meuId) && URGENTES.includes(acao);
        if (cheio) cheioUsado = true;
        return { card, acao, cheio };
      });
      const vermelho = doGrupo.some(card => tomDaLinha(card) === 'vermelho');
      return {
        chave: grupo,
        conta: contagem[grupo] ?? doGrupo.length,
        deAcao: GRUPOS_DE_ACAO.includes(grupo),
        tom: TONS[vermelho ? 'vermelho' : GRUPOS[grupo].tom],
        icone: GRUPOS[grupo].icone,
        linhas,
      };
    })
    .filter(grupo => grupo.linhas.length && grupo.conta > 0);
};

// Contagem do servidor ({ groups: [{ key, count }] }) → { esperando: 3, … }.
export const contagemDoResumo = resumo =>
  Object.fromEntries(
    (resumo?.groups || []).map(grupo => [grupo.key, Number(grupo.count) || 0])
  );

export const somar = (contagem, grupos) =>
  grupos.reduce((soma, grupo) => soma + (contagem[grupo] || 0), 0);
