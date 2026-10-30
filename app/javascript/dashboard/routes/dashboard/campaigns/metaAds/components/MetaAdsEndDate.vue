<script setup>
import { computed, ref } from 'vue';
import { addDays } from '../dinheiroDoAnuncio';
import CampoDeData from './CampoDeData.vue';

// Anúncios da Meta (#2198): até quando o anúncio fica no ar. Três respostas prontas e "Escolher data", em vez de
// checkbox e campo de data do navegador. Valor: 'AAAA-MM-DD' ou '' (sem data para terminar).
const props = defineProps({
  // Primeiro dia que pode ser escolhido (o começo do anúncio ou hoje).
  from: { type: String, required: true },
  allowNoEnd: { type: Boolean, default: true },
});

const model = defineModel({ type: String, default: '' });

const KEY = 'CRM_KANBAN.META_ADS_HUB.CRIAR.END';
const QUICK = [7, 30];

const quickDate = days => addDays(props.from, days - 1);

const initial = () => {
  if (!model.value) return props.allowNoEnd ? 'NONE' : 'PICK';
  const quick = QUICK.find(days => quickDate(days) === model.value);
  return quick ? `D${quick}` : 'PICK';
};
const choice = ref(initial());

const options = computed(() => [
  ...(props.allowNoEnd ? ['NONE'] : []),
  ...QUICK.map(days => `D${days}`),
  'PICK',
]);

const choose = option => {
  choice.value = option;
  if (option === 'NONE') model.value = '';
  else if (option === 'PICK') model.value = model.value || '';
  else model.value = quickDate(Number(option.slice(1)));
};
</script>

<template>
  <fieldset data-end-date class="m-0 flex min-w-0 flex-col gap-3 border-0 p-0">
    <legend class="mb-2 p-0 text-sm font-medium text-n-slate-12">
      {{ $t(`${KEY}.LABEL`) }}
    </legend>
    <div class="grid grid-cols-2 gap-2">
      <button
        v-for="option in options"
        :key="option"
        type="button"
        :data-end-date-option="option"
        :aria-pressed="choice === option"
        class="min-h-11 rounded-xl border-0 px-4 text-sm font-medium text-n-slate-12 transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        :class="
          choice === option
            ? 'bg-n-brand/10 ring-2 ring-n-brand'
            : 'bg-n-solid-1 ring-1 ring-n-weak hover:ring-n-strong'
        "
        @click="choose(option)"
      >
        {{ $t(`${KEY}.${option}`) }}
      </button>
    </div>
    <CampoDeData
      v-if="choice === 'PICK'"
      v-model="model"
      :label="$t(`${KEY}.PICK_LABEL`)"
      :placeholder="$t(`${KEY}.PICK_PLACEHOLDER`)"
      :min="from"
    />
  </fieldset>
</template>
