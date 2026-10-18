// Texto longo com "Ler mais" (#1702), como no app: o balão mostra o começo e o botão
// abre o resto. O app corta por tamanho do texto, não por linhas; usamos 768
// caracteres (perto do corte que o app faz no celular e no WhatsApp Web) porque o
// corte por caractere é o mesmo em qualquer largura de tela e não depende de medir
// o balão já desenhado.
export const LIMITE_DO_TEXTO = 768;

// Devolve o começo do texto, cortado no último espaço antes do limite (para não partir
// palavra nem link ao meio), com "…" no fim; null quando o texto cabe inteiro.
export const cortarTextoLongo = (texto, limite = LIMITE_DO_TEXTO) => {
  if (typeof texto !== 'string' || texto.length <= limite) return null;
  const trecho = texto.slice(0, limite);
  const espaco = Math.max(trecho.lastIndexOf(' '), trecho.lastIndexOf('\n'));
  const fim = espaco > limite / 2 ? espaco : limite;
  return `${trecho.slice(0, fim).trimEnd()}…`;
};
