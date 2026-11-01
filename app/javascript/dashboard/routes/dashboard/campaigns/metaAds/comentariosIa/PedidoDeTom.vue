<script setup>
import { computed, ref } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { FRASE_DO_DONO_LIMIT } from './useCuidado';

// #2458 (PR 2 do #2436): "Quer de outro jeito?" no passo 3. O pedido de tom, numa frase, vale para todas as respostas
// que a IA escreve. "Ajustar" grava o pedido aqui e avisa (`change`): a prévia é escrita de novo com ele.
const emit = defineEmits(['change']);
const tom = defineModel('tom', { type: String, required: true });

const KEY = 'META_ADS_COMMENTS_AI.DONO.TONE';
const FIELD =
  '!mb-0 w-full rounded-xl bg-n-solid-1 px-3 py-2 text-base leading-6 text-n-slate-12 ring-1 ring-inset ring-n-weak focus:outline-none focus:ring-2 focus:ring-n-brand';

const rascunho = ref('');
const tooLong = computed(
  () => rascunho.value.trim().length > FRASE_DO_DONO_LIMIT
);
const ajustar = () => {
  tom.value = rascunho.value.trim();
  emit('change');
};
const desfazer = () => {
  tom.value = '';
  rascunho.value = '';
  emit('change');
};
</script>

<template>
  <div
    data-ia-dono-tom
    class="flex flex-col gap-2 rounded-2xl bg-n-alpha-1 p-4"
  >
    <template v-if="!tom">
      <label for="ia-dono-tom" class="text-sm font-semibold text-n-slate-12">
        {{ $t(`${KEY}.LABEL`) }}
      </label>
      <div class="flex flex-col gap-2 sm:flex-row">
        <input
          id="ia-dono-tom"
          v-model="rascunho"
          data-ia-dono-tom-campo
          type="text"
          :aria-invalid="tooLong"
          :placeholder="$t(`${KEY}.PLACEHOLDER`)"
          :class="FIELD"
          class="min-h-11"
          @keydown.enter.prevent="rascunho.trim() && !tooLong && ajustar()"
        />
        <Button
          data-ia-dono-tom-ajustar
          variant="faded"
          color="slate"
          icon="i-lucide-wand-sparkles"
          :label="$t(`${KEY}.BUTTON`)"
          :disabled="!rascunho.trim() || tooLong"
          class="!min-h-11 shrink-0 !rounded-xl"
          @click="ajustar"
        />
      </div>
      <p
        v-if="tooLong"
        role="alert"
        class="m-0 text-sm font-medium text-n-ruby-11"
      >
        {{ $t(`${KEY}.TOO_LONG`, { max: FRASE_DO_DONO_LIMIT }) }}
      </p>
    </template>
    <p
      v-else
      data-ia-dono-tom-pronto
      class="m-0 flex flex-wrap items-center gap-x-2 text-sm text-n-slate-12"
    >
      <span class="i-lucide-check size-4 text-n-teal-11" aria-hidden="true" />
      {{ $t(`${KEY}.DONE`, { tom }) }}
      <button
        type="button"
        data-ia-dono-tom-desfazer
        class="min-h-11 rounded-lg border-0 bg-transparent px-1 text-sm font-medium text-n-blue-11 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        @click="desfazer"
      >
        {{ $t(`${KEY}.UNDO`) }}
      </button>
    </p>
  </div>
</template>
