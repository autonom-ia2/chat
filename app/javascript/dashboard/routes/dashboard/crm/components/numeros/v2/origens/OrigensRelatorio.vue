<script setup>
import { computed } from 'vue';
import CrmNumerosOrigensAPI from 'dashboard/api/crmNumerosOrigens';
import BaixarRelatorio from 'dashboard/components-next/relatorio/BaixarRelatorio.vue';
import { useNumerosFormato } from '../useNumerosFormato';
import { comMaiuscula } from '../numerosTextos';

// Números › Origens (#2001, F6) — "Baixar relatório": o mesmo botão e o mesmo diálogo do relatório de Anúncios
// (BaixarRelatorio). O servidor monta o PDF ou a planilha com os números do filtro da tela (mês e funil); o diálogo
// mostra o filtro antes de baixar e "Alterar mês ou funil" fecha e põe o foco nos filtros. A lista de clientes vai só
// para quem pode exportar o CRM (crm_export).
const props = defineProps({
  // O filtro da tela, igual ao do pedido dos números: { mes: 'AAAA-MM', funil: '<id>' | 'todos' }.
  filtro: { type: Object, required: true },
  mesNome: { type: String, required: true },
  // Nome do funil escolhido; vazio = "Todos os funis".
  funilNome: { type: String, default: '' },
});
const emit = defineEmits(['alterar']);

const O = 'CRM_NUMEROS_ORIGENS.RELATORIO';
const { t } = useNumerosFormato();

const filtroTexto = computed(() =>
  props.funilNome
    ? t(`${O}.FILTRO_FUNIL`, {
        mes: comMaiuscula(props.mesNome),
        funil: props.funilNome,
      })
    : t(`${O}.FILTRO_TODOS`, { mes: comMaiuscula(props.mesNome) })
);

const textos = computed(() => ({
  botao: t(`${O}.BUTTON`),
  titulo: t(`${O}.TITLE`),
  descricao: t(`${O}.DESCRIPTION`, { filtro: filtroTexto.value }),
  confirmar: t(`${O}.CONFIRM`),
  pdfTitulo: t(`${O}.PDF_TITLE`),
  pdfDica: t(`${O}.PDF_HINT`),
  planilhaTitulo: t(`${O}.SHEET_TITLE`),
  planilhaDica: t(`${O}.SHEET_HINT`),
  erro: t(`${O}.ERROR`),
  comPessoas: t(`${O}.WITH_PEOPLE`),
  semPessoas: t(`${O}.NO_PEOPLE`),
}));

const pedir = formato => CrmNumerosOrigensAPI.report(formato, props.filtro);
const nomeReserva = formato =>
  formato === 'pdf' ? 'de-onde-vieram.pdf' : 'de-onde-vieram.xlsx';

const alterar = fechar => {
  fechar();
  emit('alterar');
};
</script>

<template>
  <BaixarRelatorio
    data-origens-relatorio
    :textos="textos"
    :pedir="pedir"
    :nome-reserva="nomeReserva"
  >
    <template #default="{ fechar }">
      <button
        type="button"
        data-report-alterar
        class="mb-3 inline-flex min-h-11 items-center gap-1 text-sm font-medium text-n-blue-11 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        @click="alterar(fechar)"
      >
        {{ t(`${O}.ALTERAR`) }}
      </button>
    </template>
  </BaixarRelatorio>
</template>
