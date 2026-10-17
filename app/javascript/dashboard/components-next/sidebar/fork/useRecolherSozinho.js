import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { usePreferredReducedMotion } from '@vueuse/core';

// Recolher sozinho nas telas de trabalho (#1781, como o google-saas DashboardSidebar.tsx): ao entrar numa
// delas o menu aberto conta 30 s com uma barrinha e recolhe para o trilho de ícones. "Abrir menu" ali conta
// de novo. Mouse ou foco de teclado dentro do menu pausa. Clicar num item que leva a uma tela de trabalho
// recolhe em 0,6 s. Recolher sozinho não grava nada: a escolha salva da pessoa vale nas outras telas.
export const TEMPO_ABERTO = 30000;
export const TEMPO_APOS_CLIQUE = 600;
const PASSO = 100;

const TELAS_DE_TRABALHO = new Set([
  // Conversa aberta
  'inbox_conversation',
  'conversation_through_inbox',
  'conversations_through_label',
  'conversations_through_team',
  'conversations_through_folders',
  'conversation_through_mentions',
  'conversation_through_unattended',
  'conversation_through_participating',
  'inbox_view_conversation',
  // CRM
  'crm_kanban_index',
  'crm_calendar_index',
  'crm_dashboard_index',
  // Agenda
  'settings_booking',
  'crm_my_booking_hours',
  'crm_booking_results',
]);

export const ehTelaDeTrabalho = nome => TELAS_DE_TRABALHO.has(nome);

// Foco que veio do teclado. O clique do mouse também foca o botão, e aí a pausa nunca acabaria.
const focoDeTeclado = alvo => {
  try {
    return Boolean(alvo?.matches?.(':focus-visible'));
  } catch {
    return false;
  }
};

// Depois do clique, espera a rota de destino até este limite; clicar na tela já aberta não deixa nada pendente.
const ESPERA_DO_DESTINO = 3000;

export function useRecolherSozinho({
  route,
  telaDeTrabalho,
  isCollapsed,
  recolher,
  restaurar,
  raiz = ref(null),
}) {
  // 1 = barra cheia, 0 = sem barra.
  const progresso = ref(0);
  const sobre = ref(false);
  const focado = ref(false);
  // Com movimento reduzido a barra fica parada, mas a contagem continua.
  const movimento = usePreferredReducedMotion();
  const reduzido = computed(() => movimento.value === 'reduce');

  // Um relógio só, para os 30 s e para os 0,6 s depois do clique.
  let relogio = null;
  let restante = 0;
  let total = 0;
  let aposClique = false;
  let caminhoNoClique = '';

  const parar = () => {
    clearInterval(relogio);
    relogio = null;
    aposClique = false;
    progresso.value = 0;
    sobre.value = false;
    focado.value = false;
  };

  // Foco que ficou num item que já saiu da tela (o recolher desmontou) não pausa mais.
  const focoAindaNoMenu = () => {
    const ativo = document.activeElement;
    return Boolean(ativo?.isConnected && raiz.value?.contains(ativo));
  };
  const pausado = () => {
    if (focado.value && !focoAindaNoMenu()) focado.value = false;
    return sobre.value || focado.value;
  };

  const recolherAgora = () => {
    parar();
    if (!isCollapsed.value) recolher();
  };

  // Depois do clique a decisão é da rota de destino: tela de trabalho recolhe; outra tela cancela (no relógio de rota).
  const tiqueAposClique = () => {
    restante -= PASSO;
    const chegou = route.path !== caminhoNoClique;
    if (chegou && restante <= 0) {
      if (telaDeTrabalho.value) recolherAgora();
      else parar();
      return;
    }
    if (restante <= -ESPERA_DO_DESTINO) parar();
  };

  const tique = () => {
    if (aposClique) {
      tiqueAposClique();
      return;
    }
    if (pausado()) return;
    restante -= PASSO;
    progresso.value = Math.max(restante, 0) / total;
    if (restante <= 0) recolherAgora();
  };

  const iniciar = (ms, depoisDoClique = false) => {
    clearInterval(relogio);
    total = ms;
    restante = ms;
    aposClique = depoisDoClique;
    progresso.value = depoisDoClique ? 0 : 1;
    relogio = setInterval(tique, PASSO);
  };

  const contarSeAberto = () => {
    if (telaDeTrabalho.value && !isCollapsed.value) iniciar(TEMPO_ABERTO);
    else parar();
  };

  // Saiu da tela de trabalho (outra rota ou a janela passou para celular): volta a largura que a pessoa escolheu.
  watch(telaDeTrabalho, (agora, antes) => {
    if (antes && !agora) restaurar();
    if (!aposClique) contarSeAberto();
  });

  // Só troca de tela reinicia a contagem: filtro do CRM (query) ou âncora (hash) não.
  watch(
    () => route.path,
    () => {
      if (!aposClique) {
        contarSeAberto();
        return;
      }
      if (!telaDeTrabalho.value) parar();
    },
    { immediate: true }
  );

  watch(isCollapsed, recolhido => {
    if (recolhido) parar();
    else if (!aposClique) contarSeAberto();
  });

  const depoisDoClique = () => {
    if (isCollapsed.value) return;
    caminhoNoClique = route.path;
    iniciar(TEMPO_APOS_CLIQUE, true);
  };

  const entrar = () => {
    sobre.value = true;
  };
  const sair = () => {
    sobre.value = false;
  };
  const focoEntrou = evento => {
    focado.value = focoDeTeclado(evento.target);
  };
  const focoSaiu = evento => {
    if (!evento.currentTarget?.contains?.(evento.relatedTarget)) {
      focado.value = false;
    }
  };

  onBeforeUnmount(parar);

  return {
    progresso,
    reduzido,
    depoisDoClique,
    entrar,
    sair,
    focoEntrou,
    focoSaiu,
  };
}
