<script setup>
import { computed, ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import DialogoDaFicha from '../ficha/DialogoDaFicha.vue';

// #3062 — "Baixar planilha": a lista que está na tela (grupo, busca, filtros e
// ordem) vira a planilha que a lista de contatos de hoje manda por e-mail. O
// diálogo diz quantas pessoas vão, para qual e-mail (o de quem está no painel,
// antes de pedir), de qual lista e o que vai em cada linha; "Mandar por e-mail"
// pede ao servidor, avisa e fecha. Se o pedido falha, avisa e fica aberto para
// tentar de novo.
// Uma planilha a cada poucos minutos (o servidor segura o pedido repetido com
// 429 e diz quantos segundos faltam): depois de pedir, até o prazo passar, o
// botão fica desligado e o diálogo diz por quê.
const props = defineProps({
  quantas: { type: Number, required: true },
  // "Clientes · busca “ana” · 2 filtros": a lista que vai.
  lista: { type: String, required: true },
  acoes: { type: Object, required: true },
  // A consulta da tela na hora do clique.
  consulta: { type: Function, required: true },
});

const PL = 'RELACIONAMENTOS.LISTA.PLANILHA';
const ESPERA_PADRAO = 300;
const { t } = useI18n();
const usuario = useMapGetter('getCurrentUser');
const dialogo = useTemplateRef('dialogo');
const pedindo = ref(false);
const travadaAte = ref(0);
const agora = ref(Date.now());
const travada = computed(() => travadaAte.value > agora.value);

const travar = segundos => {
  agora.value = Date.now();
  travadaAte.value = agora.value + (segundos ?? ESPERA_PADRAO) * 1000;
};

const pedir = async () => {
  if (pedindo.value || travada.value) return;
  pedindo.value = true;
  try {
    const { email, espera } = await props.acoes.exportar(props.consulta());
    travar(espera);
    useAlert(t(`${PL}.ENVIADA`, { email }));
    dialogo.value?.close();
  } catch (falha) {
    if (falha?.response?.status === 429) travar(falha.response.data?.espera);
    else useAlert(t(`${PL}.ERRO`));
  } finally {
    pedindo.value = false;
  }
};

defineExpose({
  abrir: () => {
    agora.value = Date.now();
    dialogo.value?.open();
  },
});
</script>

<template>
  <DialogoDaFicha
    ref="dialogo"
    :titulo="t(`${PL}.TITULO`)"
    :texto="
      t(`${PL}.TEXTO`, { count: quantas, email: usuario?.email }, quantas)
    "
    :confirmar="t(`${PL}.CONFIRMAR`)"
    :cancelar="t('RELACIONAMENTOS.COMUM.CANCELAR')"
    marca-confirmar="mandar-planilha"
    :carregando="pedindo"
    :desligado="travada"
    @confirm="pedir"
  >
    <ul
      data-relacionamentos="dialogo-planilha"
      class="flex flex-col gap-2 p-4 m-0 text-sm list-none rounded-xl bg-n-alpha-1 text-n-slate-12"
    >
      <li class="flex gap-2">
        <span
          class="i-lucide-list size-4 mt-0.5 shrink-0 text-n-slate-11"
          aria-hidden="true"
        />
        {{ t(`${PL}.QUAL_LISTA`, { lista }) }}
      </li>
      <li class="flex gap-2">
        <span
          class="i-lucide-sheet size-4 mt-0.5 shrink-0 text-n-slate-11"
          aria-hidden="true"
        />
        {{ t(`${PL}.O_QUE_VAI`) }}
      </li>
    </ul>
    <p
      role="status"
      data-relacionamentos="planilha-espera"
      class="m-0 text-sm text-n-amber-11"
    >
      {{ travada ? t(`${PL}.ESPERAR`) : '' }}
    </p>
  </DialogoDaFicha>
</template>
