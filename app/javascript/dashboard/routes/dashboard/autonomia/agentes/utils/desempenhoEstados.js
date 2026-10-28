// #2226 (ESPEC 2.11) — as variantes do EstadoDoPainel.
// Por variante: a chave do texto, o ícone, se o botão é só de quem gerencia e o que quem só vê recebe.
export const VARIANTES = {
  sem_conversas: { chave: 'SEM_CONVERSAS', icone: 'i-lucide-calendar-search' },
  leitura_desligada: {
    chave: 'LEITURA_DESLIGADA',
    icone: 'i-lucide-book-open',
    soQuemGerencia: true,
  },
  lendo: { chave: 'LENDO', icone: 'i-lucide-hourglass' },
  teto: { chave: 'TETO', icone: 'i-lucide-circle-pause' },
  sem_ia: {
    chave: 'SEM_IA',
    icone: 'i-lucide-key-round',
    soQuemGerencia: true,
    botaoSemAcesso: true,
  },
  // #2301 — a última rodada da leitura automática caiu: a frase só avisa; a próxima rodada tenta de novo.
  erro: { chave: 'ERRO', icone: 'i-lucide-circle-alert', semBotao: true },
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
