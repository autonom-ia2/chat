// Setas num grupo de opções (role="radiogroup"), como pede o padrão WAI-ARIA:
// direita/baixo vai para a próxima, esquerda/cima para a anterior, dando a volta.
// A opção nova é escolhida e recebe o foco.
const PROXIMA = ['ArrowRight', 'ArrowDown'];
const ANTERIOR = ['ArrowLeft', 'ArrowUp'];

export const andarComSetas = evento => {
  const passo =
    (PROXIMA.includes(evento.key) && 1) ||
    (ANTERIOR.includes(evento.key) && -1) ||
    0;
  if (!passo) return;
  const opcoes = Array.from(
    evento.currentTarget.querySelectorAll('[role="radio"]:not([disabled])')
  );
  const atual = opcoes.indexOf(document.activeElement);
  if (atual === -1) return;
  evento.preventDefault();
  const nova = opcoes[(atual + passo + opcoes.length) % opcoes.length];
  nova.focus();
  nova.click();
};
