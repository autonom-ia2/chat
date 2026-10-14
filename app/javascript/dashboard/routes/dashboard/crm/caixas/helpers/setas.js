// #1149 — setas num grupo de opções (padrão WAI-ARIA radio): direita/baixo vai
// para a próxima, esquerda/cima para a anterior, dando a volta. Escolhe a nova
// opção e leva o foco até ela. Só a marcada fica no Tab (tabindex 0).
const PROXIMA = ['ArrowRight', 'ArrowDown'];
const ANTERIOR = ['ArrowLeft', 'ArrowUp'];

export const aoTeclarNoGrupo = (evento, opcoes, atual, escolher) => {
  const passo =
    (PROXIMA.includes(evento.key) && 1) ||
    (ANTERIOR.includes(evento.key) && -1) ||
    0;
  if (!passo) return;
  evento.preventDefault();
  const indice = opcoes.indexOf(atual);
  const nova = opcoes[(indice + passo + opcoes.length) % opcoes.length];
  escolher(nova);
  const grupo = evento.currentTarget;
  requestAnimationFrame(() => {
    grupo.querySelector('[aria-checked="true"]')?.focus();
  });
};
