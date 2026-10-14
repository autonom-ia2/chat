import { computed, nextTick, watch } from 'vue';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { useFixedPanelPresence } from 'dashboard/composables/useFixedPanelState';

// #1423 — abrir o card, re-hidratar e o teclado (DS-02, TK-02):
// - ao abrir outro card, começa no resumo (ou na tela da aba pedida pela
//   página: `initialTab`); atualização do mesmo card não apaga o que está
//   sendo digitado nem muda de tela;
// - a cada tela, volta ao topo e põe o foco no título;
// - Esc: diálogo aberto cuida de si; numa tela interna, volta (sem apagar o
//   que está num campo); no resumo, fecha a gaveta.
const TELA_DA_ABA = {
  summary: 'resumo',
  contact: 'contato',
  conversations: 'conversas',
  followups: 'agenda',
  timeline: 'historico',
};

export const useCardAbertura = ({
  props,
  abaInicial,
  editando,
  negocio,
  retorno,
  reuniao,
  tela,
  pilha,
  irPara,
  conteudo,
  raiz,
  fechar,
  voltarDoHeroi,
  descartando,
}) => {
  const comecar = () => {
    negocio.carregar(props.card);
    retorno.reiniciar();
    pilha.value = [];
    if (!editando.value) {
      tela.value = 'criar-1';
      return;
    }
    const destino = TELA_DA_ABA[abaInicial()] || 'resumo';
    tela.value = 'resumo';
    if (destino !== 'resumo') irPara(destino);
  };
  watch(
    () => [props.show, props.card],
    (_agora, antes) => {
      if (!props.show) return;
      const mesmoCard = antes?.[0] && props.card?.id === antes[1]?.id;
      if (mesmoCard && editando.value) {
        if (!negocio.sujo.value) negocio.carregar(props.card);
        return;
      }
      comecar();
    },
    { immediate: true }
  );
  watch(tela, async () => {
    await nextTick();
    if (conteudo.value) conteudo.value.scrollTop = 0;
    raiz.value?.querySelector('[data-card-titulo]')?.focus();
  });
  // Depois de agendar ou remarcar, a página recarrega o card: a reunião também.
  watch(
    () => props.card,
    (novo, velho) => {
      if (novo && velho && novo.id === velho.id) reuniao.recarregar();
    }
  );

  useKeyboardEvents({
    Escape: {
      action: () => {
        if (!props.show || descartando.value) return;
        if (document.querySelector('dialog[open]')) return;
        if (['resumo', 'criar-1'].includes(tela.value)) {
          fechar();
          return;
        }
        const campo = document.activeElement?.tagName;
        if (campo === 'INPUT' || campo === 'TEXTAREA') return;
        voltarDoHeroi();
      },
      allowOnFocusedInput: true,
    },
  });
  // #646 — a gaveta cobre o canto do lançador do Guia.
  useFixedPanelPresence(computed(() => props.show));
};
