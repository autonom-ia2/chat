<script setup>
import { computed } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';

// #2775 — F6, uma empresa dentro da lista aberta: o nome, a empresa (quando o
// contato é a pessoa), os selos do que ela tem e "Tirar". A lista já enviada
// não muda: não há "Tirar".
const props = defineProps({
  membro: { type: Object, required: true },
  podeTirar: { type: Boolean, default: false },
  ocupado: { type: Boolean, default: false },
});
const emit = defineEmits(['tirar']);

const NS = 'PROSPECTING_ACHAR.LISTA';
const SELOS = [
  {
    id: 'whatsapp',
    chave: 'SELO_WHATSAPP',
    classe: 'bg-n-teal-3 text-n-teal-11',
  },
  { id: 'email', chave: 'SELO_EMAIL', classe: 'bg-n-blue-3 text-n-blue-11' },
  { id: 'noCrm', chave: 'SELO_FUNIL', classe: 'bg-n-iris-3 text-n-iris-11' },
];
const selos = computed(() => SELOS.filter(selo => props.membro[selo.id]));
const mostraEmpresa = computed(
  () => props.membro.empresa && props.membro.empresa !== props.membro.nome
);
</script>

<template>
  <li
    class="flex flex-col gap-2 p-4 border border-solid rounded-2xl border-n-weak bg-n-solid-1 sm:flex-row sm:items-center"
    data-membro
  >
    <div class="flex flex-col flex-1 min-w-0 gap-1">
      <span class="text-base font-semibold break-words text-n-slate-12">
        {{ membro.nome }}
      </span>
      <span v-if="mostraEmpresa" class="text-sm break-words text-n-slate-11">
        {{ membro.empresa }}
      </span>
      <span v-if="selos.length" class="flex flex-wrap gap-1.5">
        <span
          v-for="selo in selos"
          :key="selo.id"
          class="px-2.5 py-0.5 text-sm rounded-full"
          :class="selo.classe"
        >
          {{ $t(`${NS}.${selo.chave}`) }}
        </span>
      </span>
    </div>
    <Button
      v-if="podeTirar"
      :label="$t(`${NS}.TIRAR`)"
      :aria-label="$t(`${NS}.TIRAR_ROTULO`, { nome: membro.nome })"
      :disabled="ocupado"
      slate
      faded
      size="sm"
      class="!min-h-11 !rounded-xl self-start sm:self-center shrink-0"
      data-tirar
      @click="emit('tirar')"
    />
  </li>
</template>
