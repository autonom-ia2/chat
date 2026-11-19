<script setup>
import { ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import DialogoDaFicha from '../ficha/DialogoDaFicha.vue';

// #3062 — "Baixar planilha": a lista que está na tela (grupo, busca, filtros e
// ordem) vira a planilha que a lista de contatos de hoje manda por e-mail. O
// diálogo diz quantas pessoas vão, de qual lista e o que vai em cada linha;
// "Mandar para o meu e-mail" pede ao servidor, avisa para qual e-mail vai e
// fecha. Se o pedido falha, avisa e fica aberto para tentar de novo.
const props = defineProps({
  quantas: { type: Number, required: true },
  // "Clientes · busca “ana” · 2 filtros": a lista que vai.
  lista: { type: String, required: true },
  acoes: { type: Object, required: true },
  // A consulta da tela na hora do clique.
  consulta: { type: Function, required: true },
});

const PL = 'RELACIONAMENTOS.LISTA.PLANILHA';
const { t } = useI18n();
const dialogo = useTemplateRef('dialogo');
const pedindo = ref(false);

const pedir = async () => {
  if (pedindo.value) return;
  pedindo.value = true;
  try {
    const { email } = await props.acoes.exportar(props.consulta());
    useAlert(t(`${PL}.ENVIADA`, { email }));
    dialogo.value?.close();
  } catch {
    useAlert(t(`${PL}.ERRO`));
  } finally {
    pedindo.value = false;
  }
};

defineExpose({ abrir: () => dialogo.value?.open() });
</script>

<template>
  <DialogoDaFicha
    ref="dialogo"
    :titulo="t(`${PL}.TITULO`)"
    :texto="t(`${PL}.TEXTO`, { count: quantas }, quantas)"
    :confirmar="t(`${PL}.CONFIRMAR`)"
    :cancelar="t('RELACIONAMENTOS.COMUM.CANCELAR')"
    marca-confirmar="mandar-planilha"
    :carregando="pedindo"
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
  </DialogoDaFicha>
</template>
