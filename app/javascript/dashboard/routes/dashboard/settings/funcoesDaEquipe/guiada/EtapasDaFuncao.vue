<script setup>
// O alto de toda etapa (#2308, especificação 4): o voltar (o texto diz para onde) e as etapas, de uma cor só
// (feita = blue-3 com check, atual = brand). Durante o salvar, o voltar fica desabilitado; sem texto, não aparece.
const props = defineProps({
  voltar: { type: String, default: '' },
  desabilitado: { type: Boolean, default: false },
  etapas: { type: Array, required: true },
  atual: { type: Number, required: true },
});

const emit = defineEmits(['voltar']);

const estado = indice => {
  if (indice < props.atual) return 'feita';
  return indice === props.atual ? 'atual' : 'depois';
};
</script>

<template>
  <div class="flex flex-wrap items-center justify-between gap-4">
    <button
      v-if="voltar"
      type="button"
      data-voltar
      :disabled="desabilitado"
      class="inline-flex items-center gap-2 px-2 -mx-2 text-[0.9375rem] font-medium rounded-lg min-h-11 text-n-slate-12 hover:enabled:bg-n-alpha-2 disabled:text-n-slate-10 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      @click="emit('voltar')"
    >
      <span
        class="i-lucide-arrow-left size-4 rtl:rotate-180"
        aria-hidden="true"
      />
      {{ voltar }}
    </button>
    <ol
      v-if="etapas.length"
      class="hidden gap-3 p-0 m-0 list-none sm:flex sm:items-center"
      :aria-label="$t('FUNCOES_EQUIPE.GUIADA.PASSOS')"
    >
      <li
        v-for="(etapa, indice) in etapas"
        :key="etapa"
        class="flex items-center gap-2 text-sm"
        :aria-current="estado(indice) === 'atual' ? 'step' : undefined"
      >
        <span
          v-if="indice"
          class="w-8 h-px"
          :class="indice <= atual ? 'bg-n-blue-8' : 'bg-n-slate-6'"
          aria-hidden="true"
        />
        <span
          class="grid border rounded-full place-items-center size-7"
          :class="{
            'bg-n-blue-3 border-n-blue-3 text-n-blue-11':
              estado(indice) === 'feita',
            'bg-n-brand border-n-brand': estado(indice) === 'atual',
            'border-n-slate-7': estado(indice) === 'depois',
          }"
          aria-hidden="true"
        >
          <span
            v-if="estado(indice) === 'feita'"
            class="i-lucide-check size-3.5"
          />
          <span
            v-else-if="estado(indice) === 'atual'"
            class="bg-white rounded-full size-2"
          />
        </span>
        <span
          :class="
            estado(indice) === 'atual'
              ? 'font-semibold text-n-slate-12'
              : 'text-n-slate-11'
          "
        >
          {{ $t(`FUNCOES_EQUIPE.GUIADA.ETAPA.${etapa}`) }}
        </span>
      </li>
    </ol>
  </div>
</template>
