<script setup>
import Input from 'dashboard/components-next/input/Input.vue';
import FunilListaEtapas from './FunilListaEtapas.vue';

// #1384 — a tela das etapas: ao criar (passo 2) e em "Etapas" de um funil
// que já existe, onde o nome também se muda aqui.
defineProps({
  comNome: { type: Boolean, default: false },
  fraseDe: { type: Function, required: true },
  ia: { type: Boolean, default: false },
  travada: { type: Boolean, default: false },
});

defineEmits(['alterar', 'criar', 'adicionar']);

const etapas = defineModel('etapas', { type: Array, required: true });
const nome = defineModel('nome', { type: String, default: '' });
</script>

<template>
  <Input
    v-if="comNome"
    v-model="nome"
    :label="$t('CRM_FUNIL.NOME')"
    :placeholder="$t('CRM_KANBAN.PIPELINE_DRAWER.NAME_PLACEHOLDER')"
    :message="!nome.trim() ? $t('CRM_FUNIL.NOME_FALTA') : ''"
    :message-type="!nome.trim() ? 'error' : 'info'"
    custom-input-class="!h-12 !rounded-xl !bg-n-solid-1 !px-4 !text-base shadow-sm"
  />
  <header class="flex flex-col gap-1">
    <h3 class="mb-0 text-xl font-semibold text-n-slate-12">
      {{ $t('CRM_FUNIL.ETAPAS.TITULO') }}
    </h3>
    <p class="mb-0 text-[0.9375rem] text-n-slate-11">
      {{ $t('CRM_FUNIL.ETAPAS.AJUDA') }}
    </p>
  </header>
  <FunilListaEtapas
    v-model="etapas"
    :frase-de="fraseDe"
    :ia="ia"
    :travada="travada"
    @alterar="$emit('alterar', $event)"
    @criar="$emit('criar', $event)"
  />
  <button
    type="button"
    data-funil-adicionar
    class="flex min-h-14 items-center justify-center gap-2 rounded-2xl border-2 border-dashed border-n-slate-6 text-[0.9375rem] font-medium text-n-slate-12 transition hover:border-n-blue-8 hover:text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
    @click="$emit('adicionar')"
  >
    <span class="i-lucide-plus size-5" aria-hidden="true" />
    {{ $t('CRM_KANBAN.PIPELINE_DRAWER.ADD_STAGE') }}
  </button>
  <p class="mb-0 text-sm text-n-slate-11">
    {{ $t('CRM_FUNIL.ETAPAS.ORDEM') }}
  </p>
</template>
