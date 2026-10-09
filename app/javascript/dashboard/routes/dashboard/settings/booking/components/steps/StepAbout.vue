<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import BookingField from '../BookingField.vue';
import BookingToggle from '../BookingToggle.vue';
import { DURATION_OPTIONS } from '../../constants';
import { formatMinutes } from '../../bookingFormat';

// Passo 2: nome que o cliente vê, quanto tempo dura e quem atende. Já vem
// preenchido pelo modelo; a pessoa só confere ou troca.
const props = defineProps({
  form: { type: Object, required: true },
  people: { type: Array, default: () => [] },
  // 'loading' | 'error' | 'ready'
  peopleState: { type: String, default: 'ready' },
  error: { type: String, default: '' },
});

const emit = defineEmits(['change', 'retryPeople']);
const { t } = useI18n();

const durationOptions = computed(() => {
  const values = DURATION_OPTIONS.includes(props.form.durationMinutes)
    ? DURATION_OPTIONS
    : [...DURATION_OPTIONS, props.form.durationMinutes].sort((a, b) => a - b);
  return values.map(value => ({ value, label: formatMinutes(t, value) }));
});

const togglePerson = id => {
  const ids = props.form.peopleIds;
  const next = ids.includes(id)
    ? ids.filter(item => item !== id)
    : [...ids, id];
  emit('change', { peopleIds: next });
};
</script>

<template>
  <section class="flex flex-col gap-6">
    <h2 class="m-0 text-2xl font-semibold text-n-slate-12">
      {{ t('BOOKING.ABOUT.TITLE') }}
    </h2>

    <BookingField
      data-title
      :model-value="form.title"
      :label="t('BOOKING.ABOUT.NAME_LABEL')"
      :error="error === 'TITLE' ? t('BOOKING.WIZARD.ERRORS.TITLE') : ''"
      @update:model-value="emit('change', { title: $event })"
    />

    <div class="flex flex-col gap-2">
      <p class="m-0 text-base font-semibold text-n-slate-12">
        {{ t('BOOKING.ABOUT.DURATION_LABEL') }}
      </p>
      <ChoiceSelect
        data-duration
        :model-value="form.durationMinutes"
        :options="durationOptions"
        :aria-label="t('BOOKING.ABOUT.DURATION_LABEL')"
        @update:model-value="emit('change', { durationMinutes: $event })"
      />
    </div>

    <fieldset class="flex flex-col gap-3 p-0 m-0 border-0">
      <legend class="p-0 mb-1 text-base font-semibold text-n-slate-12">
        {{ t('BOOKING.ABOUT.PEOPLE_LABEL') }}
      </legend>
      <p class="m-0 text-base text-n-slate-11">
        {{ t('BOOKING.ABOUT.PEOPLE_HINT') }}
      </p>
      <p
        v-if="peopleState === 'loading'"
        aria-busy="true"
        class="m-0 text-base text-n-slate-11"
      >
        {{ t('BOOKING.ABOUT.PEOPLE_LOADING') }}
      </p>
      <div
        v-else-if="peopleState === 'error'"
        role="alert"
        class="flex flex-wrap items-center gap-3"
      >
        <p class="m-0 text-base text-n-ruby-11">
          {{ t('BOOKING.ABOUT.PEOPLE_ERROR') }}
        </p>
        <button
          type="button"
          class="min-h-11 px-4 text-base font-medium rounded-xl text-n-blue-11 ring-1 ring-inset ring-n-weak"
          @click="emit('retryPeople')"
        >
          {{ t('BOOKING.LIST.RETRY') }}
        </button>
      </div>
      <p v-else-if="!people.length" class="m-0 text-base text-n-slate-11">
        {{ t('BOOKING.ABOUT.PEOPLE_EMPTY') }}
      </p>
      <div v-else data-people class="flex flex-wrap gap-2">
        <BookingToggle
          v-for="person in people"
          :key="person.id"
          :data-person="person.id"
          :label="person.name"
          :pressed="form.peopleIds.includes(person.id)"
          @toggle="togglePerson(person.id)"
        />
      </div>
      <p v-if="error === 'PEOPLE'" class="m-0 text-base text-n-ruby-11">
        {{ t('BOOKING.WIZARD.ERRORS.PEOPLE') }}
      </p>
    </fieldset>
  </section>
</template>
