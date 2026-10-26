<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import BaixarRelatorio from 'dashboard/components-next/relatorio/BaixarRelatorio.vue';

// Relatório baixado de Anúncios (#1960): o painel do período em PDF (A4 deitado, para mostrar ou mandar) ou em
// planilha (para trabalhar os números), montado no servidor com os mesmos números da tela. O botão e o diálogo são
// o componente comum dos relatórios (BaixarRelatorio, #2001); aqui só os textos e o período.
const props = defineProps({
  // Período da tela (#2011): o arquivo sai com os mesmos números.
  period: { type: String, required: true },
});

const { t } = useI18n();
const R = 'CRM_KANBAN.META_ADS_HUB.PANEL.REPORT';

const textos = computed(() => ({
  botao: t(`${R}.BUTTON`),
  titulo: t(`${R}.TITLE`),
  descricao: t(`${R}.DESCRIPTION`, {
    name: t(`CRM_KANBAN.META_ADS_HUB.PANEL.PERIODS.${props.period}.NAME`),
  }),
  confirmar: t(`${R}.CONFIRM`),
  pdfTitulo: t(`${R}.PDF_TITLE`),
  pdfDica: t(`${R}.PDF_HINT`),
  planilhaTitulo: t(`${R}.SHEET_TITLE`),
  planilhaDica: t(`${R}.SHEET_HINT`),
  erro: t(`${R}.ERROR`),
  semPessoas: t(`${R}.NO_PEOPLE`),
}));

const pedir = formato => CrmMetaAdsConnectionAPI.report(formato, props.period);
const nomeReserva = formato =>
  formato === 'pdf' ? 'anuncios.pdf' : 'anuncios.xlsx';
</script>

<template>
  <BaixarRelatorio
    data-panel-report
    :textos="textos"
    :pedir="pedir"
    :nome-reserva="nomeReserva"
  />
</template>
