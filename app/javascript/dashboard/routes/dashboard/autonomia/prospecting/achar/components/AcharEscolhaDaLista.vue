<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { LISTA_NOVA } from '../composables/useFolhaDaLista';

// #2775 — F6, "Para qual lista?" na folha do Guardar lista: "Lista nova" (o
// padrão) ou uma lista que já existe, com os números dela embaixo do nome. A
// lista já enviada aparece desligada, com o porquê (ela não muda mais). Sem
// <select> nativo: a escolha do produto (ChoiceSelect).
const props = defineProps({
  // null enquanto as listas não chegam: só "Lista nova".
  listas: { type: Array, default: null },
});
const listaId = defineModel({ type: [String, Number], default: LISTA_NOVA });

const { t } = useI18n();
const NS = 'PROSPECTING_ACHAR.FOLHA';
const campoId = useId();

const numeros = lista =>
  t(`${NS}.NUMEROS_LISTA`, {
    empresas: lista.empresas,
    whatsapp: lista.whatsapp,
    email: lista.email,
  });

const opcoes = computed(() => [
  { value: LISTA_NOVA, label: t(`${NS}.LISTA_NOVA`) },
  ...(props.listas || []).map(lista => ({
    value: lista.id,
    label: lista.nome,
    hint: lista.enviada ? t(`${NS}.LISTA_ENVIADA_DICA`) : numeros(lista),
    disabled: lista.enviada,
  })),
]);
</script>

<template>
  <div class="flex flex-col gap-2" data-escolha-da-lista>
    <label :for="campoId" class="text-sm font-medium text-n-slate-11">
      {{ $t(`${NS}.QUAL_LISTA`) }}
    </label>
    <ChoiceSelect
      v-model="listaId"
      :trigger-id="campoId"
      :options="opcoes"
      :aria-label="$t(`${NS}.QUAL_LISTA`)"
      class="w-full"
    />
  </div>
</template>
