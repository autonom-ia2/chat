<script setup>
import { computed, ref } from 'vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import { ESTADOS, semAcento } from '../brasilEstados';

// Anúncios da Meta (#2198), criar: quem vê o anúncio. Primeiro a pergunta da categoria especial (a Meta exige o campo
// em toda campanha; anúncio de seguro, crédito, empréstimo ou investimento vai marcado, com as travas de público
// ligadas: idade 18 a 65+ e sem escolha de gênero). Depois onde (Brasil todo ou estados, pelo nome) e a idade.
// Público do CRM fica de fora (LGPD e o bloqueio de saúde e finanças da Meta).
const draft = defineModel({ type: Object, required: true });

const KEY = 'CRM_KANBAN.META_ADS_HUB.CRIAR.AUDIENCE';

const set = (field, value) => {
  draft.value = { ...draft.value, [field]: value };
};

const chooseSpecial = answer => {
  draft.value = answer
    ? { ...draft.value, special_category: true, age_min: 18, age_max: 65 }
    : { ...draft.value, special_category: false };
};

const search = ref('');
const states = computed(() => {
  const term = semAcento(search.value.trim());
  return term
    ? ESTADOS.filter(estado => semAcento(estado.name).includes(term))
    : ESTADOS;
});

const toggleState = uf => {
  const list = draft.value.states;
  set(
    'states',
    list.includes(uf) ? list.filter(item => item !== uf) : [...list, uf]
  );
};

const AGES = [18, 21, 25, 30, 35, 40, 45, 50, 55, 60, 65];
const ageLabel = age => (age === 65 ? '65+' : String(age));
const minOptions = AGES.filter(age => age < 65).map(age => ({
  value: age,
  label: ageLabel(age),
}));
const maxOptions = AGES.filter(age => age > 18).map(age => ({
  value: age,
  label: ageLabel(age),
}));

const chipClass = active =>
  active
    ? 'bg-n-brand/10 ring-2 ring-n-brand'
    : 'bg-n-solid-1 ring-1 ring-n-weak hover:ring-n-strong';
</script>

<template>
  <div class="flex min-w-0 max-w-2xl flex-col gap-6">
    <fieldset class="m-0 flex min-w-0 flex-col gap-3 border-0 p-0">
      <legend class="mb-2 p-0 text-sm font-medium text-n-slate-12">
        {{ $t(`${KEY}.SPECIAL`) }}
      </legend>
      <div class="flex flex-wrap gap-3">
        <button
          v-for="answer in [false, true]"
          :key="String(answer)"
          type="button"
          :data-create-special="String(answer)"
          :aria-pressed="draft.special_category === answer"
          class="min-h-11 min-w-20 rounded-xl border-0 px-4 text-sm font-medium text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          :class="chipClass(draft.special_category === answer)"
          @click="chooseSpecial(answer)"
        >
          {{ $t(`${KEY}.${answer ? 'YES' : 'NO'}`) }}
        </button>
      </div>
      <p
        v-if="draft.special_category"
        data-create-special-hint
        class="m-0 flex gap-2 rounded-xl bg-n-blue-2 p-3 text-sm text-n-blue-12"
      >
        <span class="i-lucide-info mt-0.5 size-4 shrink-0" aria-hidden="true" />
        {{ $t(`${KEY}.SPECIAL_HINT`) }}
      </p>
    </fieldset>

    <fieldset class="m-0 flex min-w-0 flex-col gap-3 border-0 p-0">
      <legend class="mb-2 p-0 text-sm font-medium text-n-slate-12">
        {{ $t(`${KEY}.WHERE`) }}
      </legend>
      <div class="flex flex-wrap gap-3">
        <button
          v-for="region in ['BR', 'STATES']"
          :key="region"
          type="button"
          :data-create-region="region"
          :aria-pressed="draft.region === region"
          class="min-h-11 rounded-xl border-0 px-4 text-sm font-medium text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          :class="chipClass(draft.region === region)"
          @click="set('region', region)"
        >
          {{ $t(`${KEY}.${region === 'BR' ? 'ALL_BRAZIL' : 'SOME_STATES'}`) }}
        </button>
      </div>
      <div
        v-if="draft.region === 'STATES'"
        data-create-states
        class="flex min-w-0 flex-col gap-3"
      >
        <Input
          v-model="search"
          data-create-state-search
          :placeholder="$t(`${KEY}.STATE_SEARCH`)"
          :aria-label="$t(`${KEY}.STATE_SEARCH`)"
        />
        <div class="flex flex-wrap gap-2">
          <button
            v-for="estado in states"
            :key="estado.uf"
            type="button"
            :data-create-state="estado.uf"
            :aria-pressed="draft.states.includes(estado.uf)"
            class="min-h-11 rounded-xl border-0 px-3 text-sm font-medium text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
            :class="chipClass(draft.states.includes(estado.uf))"
            @click="toggleState(estado.uf)"
          >
            {{ estado.name }}
          </button>
          <p v-if="!states.length" class="m-0 text-sm text-n-slate-11">
            {{ $t(`${KEY}.STATE_NONE`) }}
          </p>
        </div>
      </div>
    </fieldset>

    <fieldset class="m-0 flex min-w-0 flex-col gap-3 border-0 p-0">
      <legend class="mb-2 p-0 text-sm font-medium text-n-slate-12">
        {{ $t(`${KEY}.AGE`) }}
      </legend>
      <p
        v-if="draft.special_category"
        data-create-age-locked
        class="m-0 text-sm text-n-slate-12"
      >
        {{ $t(`${KEY}.AGE_LOCKED`) }}
      </p>
      <div
        v-else
        class="flex flex-wrap items-center gap-3 text-sm text-n-slate-11"
      >
        {{ $t(`${KEY}.FROM`) }}
        <ChoiceSelect
          :model-value="draft.age_min"
          data-create-age-min
          :options="minOptions"
          :aria-label="$t(`${KEY}.AGE_MIN`)"
          @update:model-value="set('age_min', $event)"
        />
        {{ $t(`${KEY}.TO`) }}
        <ChoiceSelect
          :model-value="draft.age_max"
          data-create-age-max
          :options="maxOptions"
          :aria-label="$t(`${KEY}.AGE_MAX`)"
          @update:model-value="set('age_max', $event)"
        />
        {{ $t(`${KEY}.YEARS`) }}
      </div>
    </fieldset>
  </div>
</template>
