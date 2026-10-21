<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import { useCrmPermissions } from 'dashboard/routes/dashboard/crm/composables/useCrmPermissions';

// Relatório baixado de Anúncios (#1960): o painel do período em PDF (A4 deitado, para mostrar ou mandar) ou em
// planilha (para trabalhar os números). Um botão abre a escolha; "Baixar" pede o arquivo ao servidor, que monta com
// os mesmos números da tela. As listas de pessoas só vão no arquivo de quem pode exportar o CRM (crm_export, dado
// pessoal em lote); sem isso o servidor manda só os números, e o diálogo avisa.
const props = defineProps({
  // Período da tela (#2011): o arquivo sai com os mesmos números.
  period: { type: String, required: true },
});

const { t } = useI18n();
const { canExportCrm } = useCrmPermissions();
const dialog = ref(null);
const formato = ref('pdf');
const baixando = ref(false);

const REVOGAR_EM_MS = 60_000;

const OPCOES = [
  { key: 'pdf', icon: 'i-lucide-file-text', label: 'PDF' },
  { key: 'planilha', icon: 'i-lucide-file-spreadsheet', label: 'SHEET' },
];

// "attachment; filename=\"anuncios-2026-10-20.pdf\"; filename*=..." → o nome entre aspas.
const nomeDoArquivo = (headers, reserva) => {
  const parte = String(headers?.['content-disposition'] || '')
    .split(';')
    .map(item => item.trim())
    .find(item => item.startsWith('filename="'));
  return parte ? parte.slice('filename="'.length, -1) : reserva;
};

const salvar = (blob, nome) => {
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.setAttribute('href', url);
  link.setAttribute('download', nome);
  link.click();
  // Revogar na hora cancela o download no Safari: espera o navegador pegar o arquivo.
  setTimeout(() => URL.revokeObjectURL(url), REVOGAR_EM_MS);
};

const abrir = () => dialog.value?.open();

const baixar = async () => {
  if (baixando.value) return;
  baixando.value = true;
  try {
    const { data, headers } = await CrmMetaAdsConnectionAPI.report(
      formato.value,
      props.period
    );
    const reserva = formato.value === 'pdf' ? 'anuncios.pdf' : 'anuncios.xlsx';
    salvar(data, nomeDoArquivo(headers, reserva));
    dialog.value?.close();
  } catch {
    useAlert(t('CRM_KANBAN.META_ADS_HUB.PANEL.REPORT.ERROR'));
  } finally {
    baixando.value = false;
  }
};
</script>

<template>
  <Button
    data-panel-report
    icon="i-lucide-download"
    :label="t('CRM_KANBAN.META_ADS_HUB.PANEL.REPORT.BUTTON')"
    slate
    faded
    class="!min-h-11 !rounded-xl"
    @click="abrir"
  />
  <Dialog
    ref="dialog"
    :title="t('CRM_KANBAN.META_ADS_HUB.PANEL.REPORT.TITLE')"
    :description="
      t('CRM_KANBAN.META_ADS_HUB.PANEL.REPORT.DESCRIPTION', {
        name: t(`CRM_KANBAN.META_ADS_HUB.PANEL.PERIODS.${period}.NAME`),
      })
    "
    :confirm-button-label="t('CRM_KANBAN.META_ADS_HUB.PANEL.REPORT.CONFIRM')"
    :is-loading="baixando"
    @confirm="baixar"
  >
    <div
      role="group"
      :aria-label="t('CRM_KANBAN.META_ADS_HUB.PANEL.REPORT.TITLE')"
      class="grid gap-3 sm:grid-cols-2"
    >
      <button
        v-for="opcao in OPCOES"
        :key="opcao.key"
        type="button"
        :data-report-format="opcao.key"
        :aria-pressed="String(formato === opcao.key)"
        class="flex items-start gap-3 p-4 text-start bg-n-solid-1 border-0 rounded-xl min-h-11 ring-1 ring-inset focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        :class="
          formato === opcao.key
            ? 'ring-2 ring-n-brand bg-n-blue-2'
            : 'ring-n-weak hover:ring-n-strong'
        "
        @click="formato = opcao.key"
      >
        <span
          class="flex items-center justify-center flex-none rounded-lg size-10 bg-n-alpha-1 text-n-slate-12"
          aria-hidden="true"
        >
          <span :class="opcao.icon" class="size-5" />
        </span>
        <span class="flex flex-col min-w-0 gap-1">
          <span class="text-sm font-semibold text-n-slate-12">
            {{ t(`CRM_KANBAN.META_ADS_HUB.PANEL.REPORT.${opcao.label}_TITLE`) }}
          </span>
          <span class="text-sm text-n-slate-11">
            {{ t(`CRM_KANBAN.META_ADS_HUB.PANEL.REPORT.${opcao.label}_HINT`) }}
          </span>
        </span>
      </button>
    </div>
    <p
      v-if="!canExportCrm"
      data-report-no-people
      class="mt-3 text-sm text-n-slate-11"
    >
      {{ t('CRM_KANBAN.META_ADS_HUB.PANEL.REPORT.NO_PEOPLE') }}
    </p>
  </Dialog>
</template>
