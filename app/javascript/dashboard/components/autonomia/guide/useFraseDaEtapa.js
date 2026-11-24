import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// A frase do que o Guia está fazendo agora, a partir do nome da última
// ferramenta que ele chamou (`etapa`, que o servidor devolve enquanto o pedido
// espera). Ferramenta sem frase aqui cai no "Pensando…" de sempre: a tela nunca
// mostra o nome técnico.
export const useFraseDaEtapa = etapa => {
  const { t } = useI18n();
  const frases = computed(() => ({
    ler_da_conta: t('AUTONOMIA_GUIDE.STEP.READ_ACCOUNT'),
    relatorio_de_atendimento: t('AUTONOMIA_GUIDE.STEP.READ_REPORTS'),
    ler_da_central: t('AUTONOMIA_GUIDE.STEP.READ_HELP'),
    ler_anexo: t('AUTONOMIA_GUIDE.STEP.READ_ATTACHMENT'),
    ler_pagina: t('AUTONOMIA_GUIDE.STEP.READ_PAGE'),
    classificar_com_jev: t('AUTONOMIA_GUIDE.STEP.CLASSIFY'),
    formato_da_acao: t('AUTONOMIA_GUIDE.STEP.CHECK_FORMAT'),
    mostrar_tela: t('AUTONOMIA_GUIDE.STEP.PICK_SCREEN'),
    executar_acao: t('AUTONOMIA_GUIDE.STEP.CHANGE'),
    propor_acao: t('AUTONOMIA_GUIDE.STEP.PROPOSE'),
    planejar_tarefa: t('AUTONOMIA_GUIDE.STEP.PLAN_TASK'),
    anotar_lembranca: t('AUTONOMIA_GUIDE.STEP.REMEMBER'),
    apagar_lembranca: t('AUTONOMIA_GUIDE.STEP.FORGET'),
  }));
  return computed(() => frases.value[etapa.value] || '');
};

export default useFraseDaEtapa;
