// #2226 (ESPEC 2.11) — as variantes do EstadoDoPainel.
// Por variante: a chave do texto, o ícone, se o botão é só de quem gerencia e o que quem só vê recebe.
// `acao`: o botão de quem gerencia faz algo fora do painel (conectar ou conferir a chave); os outros só
// navegam pelos números e somem no painel vazio (#2301).
export const VARIANTES = {
  sem_conversas: { chave: 'SEM_CONVERSAS', icone: 'i-lucide-calendar-search' },
  leitura_desligada: {
    chave: 'LEITURA_DESLIGADA',
    icone: 'i-lucide-book-open',
    soQuemGerencia: true,
  },
  // #2301 — a leitura automática ainda não leu este agente: não há o que ver, então sem botão.
  lendo: { chave: 'LENDO', icone: 'i-lucide-hourglass', semBotao: true },
  teto: { chave: 'TETO', icone: 'i-lucide-circle-pause' },
  sem_ia: {
    chave: 'SEM_IA',
    icone: 'i-lucide-key-round',
    soQuemGerencia: true,
    botaoSemAcesso: true,
    acao: true,
  },
  // #2301 — a última rodada da leitura automática caiu: a frase só avisa e diz o que fazer se continuar.
  erro: { chave: 'ERRO', icone: 'i-lucide-circle-alert', semBotao: true },
  // #2301 — a IA recusou a chave da conta: quem gerencia vai à tela da chave, como no sem_ia.
  chave_recusada: {
    chave: 'CHAVE_RECUSADA',
    icone: 'i-lucide-key-round',
    soQuemGerencia: true,
    botaoSemAcesso: true,
    acao: true,
  },
  // Definir o que conta como resultado volta no PR que grava a escolha (o #2251 tirou a gaveta que não gravava).
  sem_resultado: {
    chave: 'SEM_RESULTADO',
    icone: 'i-lucide-flag',
    semBotao: true,
  },
  conferencia_baixa: {
    chave: 'CONFERENCIA_BAIXA',
    icone: 'i-lucide-triangle-alert',
    faixa: true,
  },
};
