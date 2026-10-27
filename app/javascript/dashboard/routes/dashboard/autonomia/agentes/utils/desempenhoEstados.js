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
  sem_resultado: {
    chave: 'SEM_RESULTADO',
    icone: 'i-lucide-flag',
    soQuemGerencia: true,
  },
  conferencia_baixa: {
    chave: 'CONFERENCIA_BAIXA',
    icone: 'i-lucide-triangle-alert',
    faixa: true,
  },
};
