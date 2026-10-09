import { onBeforeUnmount, onMounted } from 'vue';

// Botão "voltar" do celular (RA-17): cada tela do agendamento vira uma entrada do histórico, sem mudar o endereço.
// Voltar pelo celular ou pelo botão "Voltar" da página leva à tela anterior em vez de sair da página. Abrir ou
// recarregar a página não empilha nada (substitui a entrada atual).
// A tela a refazer no `popstate` vem de `restoreWith` (quem usa só sabe montá-la depois de criar o histórico).
export function useStepHistory(win = window) {
  let onRestore = () => null;
  let depth = 0;
  // Profundidade da primeira tela (a que abriu a página): para onde `home` volta.
  let base = 0;

  const state = step => ({ bookingStep: step, bookingDepth: depth });

  const start = step => {
    depth = Number(win.history.state?.bookingDepth) || 0;
    base = depth;
    win.history.replaceState(state(step), '');
  };

  const push = step => {
    depth += 1;
    win.history.pushState(state(step), '');
  };

  const replace = step => {
    win.history.replaceState(state(step), '');
  };

  // true quando o histórico tem para onde voltar; a troca de tela vem no `popstate`.
  const back = () => {
    if (depth <= 0) return false;
    win.history.back();
    return true;
  };

  // Volta direto para a primeira tela (fim de uma ação na gestão da reunião), sem deixar telas já resolvidas para
  // o "voltar" do celular reabrir. true quando havia para onde voltar; a troca de tela vem no `popstate`.
  const home = () => {
    if (depth <= base) return false;
    win.history.go(base - depth);
    return true;
  };

  const onPopState = event => {
    depth = Number(event.state?.bookingDepth) || 0;
    onRestore(event.state?.bookingStep || null);
  };

  onMounted(() => win.addEventListener('popstate', onPopState));
  onBeforeUnmount(() => win.removeEventListener('popstate', onPopState));

  const restoreWith = handler => {
    onRestore = handler;
  };

  return { start, push, replace, back, home, restoreWith };
}
