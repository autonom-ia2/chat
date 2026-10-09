<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import BookingField from '../BookingField.vue';
import { BASIC_LOCATIONS, CALENDAR_LOCATIONS, MAX_TEXT } from '../../constants';

// Passo 3: onde vai ser a conversa. Só mostra o que dá para usar agora:
// Google Meet e Teams aparecem apenas com uma caixa de e-mail com agenda já
// conectada (J3-A2). Escolher a caixa não é conectar caixa (J8-A5).
const props = defineProps({
  form: { type: Object, required: true },
  // [{ id, name, provider: 'google' | 'microsoft' }], do GET da página.
  calendarOptions: { type: Array, default: () => [] },
  error: { type: String, default: '' },
});

const emit = defineEmits(['change']);
const { t } = useI18n();

const providers = computed(
  () => new Set(props.calendarOptions.map(option => option.provider))
);
const calendarLocations = computed(() =>
  CALENDAR_LOCATIONS.filter(item => providers.value.has(item.provider))
);
const choices = computed(() => [
  ...BASIC_LOCATIONS,
  ...calendarLocations.value,
]);

const selected = type => props.form.locations.some(item => item.type === type);
const chosenCalendar = computed(() =>
  CALENDAR_LOCATIONS.find(item => selected(item.type))
);
const inboxOptions = computed(() =>
  props.calendarOptions
    .filter(option => option.provider === chosenCalendar.value?.provider)
    .map(option => ({ value: option.id, label: option.name }))
);

const calendarTypes = CALENDAR_LOCATIONS.map(item => item.type);

const turnOn = choice => {
  // Uma página usa uma caixa de agenda só: Meet e Teams não vão juntos.
  const others = calendarTypes.includes(choice.type)
    ? props.form.locations.filter(item => !calendarTypes.includes(item.type))
    : props.form.locations;
  const patch = {
    locations: [...others, { type: choice.type, url: '', address: '' }],
  };
  if (choice.provider) {
    const match = props.calendarOptions.find(
      option => option.provider === choice.provider
    );
    patch.calendarInboxId = match?.id ?? null;
  }
  emit('change', patch);
};

const toggle = choice => {
  if (!selected(choice.type)) {
    turnOn(choice);
    return;
  }
  emit('change', {
    locations: props.form.locations.filter(item => item.type !== choice.type),
  });
};

const updateLocation = (type, field, value) =>
  emit('change', {
    locations: props.form.locations.map(item =>
      item.type === type ? { ...item, [field]: value } : item
    ),
  });

const valueOf = (type, field) =>
  props.form.locations.find(item => item.type === type)?.[field] || '';

const errorText = key =>
  props.error === key ? t(`BOOKING.WIZARD.ERRORS.${key}`) : '';
</script>

<template>
  <section class="flex flex-col gap-6">
    <div class="flex flex-col gap-1">
      <h2 class="m-0 text-2xl font-semibold text-n-slate-12">
        {{ t('BOOKING.WHERE.TITLE') }}
      </h2>
      <p class="m-0 text-base text-n-slate-11">{{ t('BOOKING.WHERE.HINT') }}</p>
    </div>

    <ul class="flex flex-col gap-3 p-0 m-0 list-none">
      <li v-for="choice in choices" :key="choice.type">
        <button
          type="button"
          :data-location="choice.type"
          :aria-pressed="selected(choice.type) ? 'true' : 'false'"
          class="flex items-center w-full gap-4 p-4 text-start rounded-2xl ring-inset transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand min-h-11"
          :class="
            selected(choice.type)
              ? 'ring-2 ring-n-blue-9 bg-n-blue-2'
              : 'ring-1 ring-n-weak bg-n-solid-1 hover:ring-n-blue-7'
          "
          @click="toggle(choice)"
        >
          <span
            class="grid place-items-center size-12 shrink-0 rounded-xl bg-n-alpha-2 text-n-slate-12"
          >
            <span class="size-6" :class="choice.icon" aria-hidden="true" />
          </span>
          <span class="flex flex-col flex-1 gap-0.5 min-w-0">
            <span class="flex flex-wrap items-center gap-2">
              <span class="text-lg font-semibold text-n-slate-12">
                {{ t(`BOOKING.WHERE.${choice.type.toUpperCase()}.NAME`) }}
              </span>
              <span
                v-if="choice.recommended"
                class="px-2.5 py-0.5 text-sm font-semibold rounded-full bg-n-teal-3 text-n-teal-11"
              >
                {{ t('BOOKING.WHERE.RECOMMENDED') }}
              </span>
            </span>
            <span class="text-base text-n-slate-11">
              {{ t(`BOOKING.WHERE.${choice.type.toUpperCase()}.HINT`) }}
            </span>
          </span>
          <span
            class="grid place-items-center size-7 shrink-0 rounded-full"
            :class="
              selected(choice.type)
                ? 'bg-n-blue-9 text-white'
                : 'ring-1 ring-inset ring-n-slate-7'
            "
            aria-hidden="true"
          >
            <span v-if="selected(choice.type)" class="i-lucide-check size-4" />
          </span>
        </button>
      </li>
    </ul>

    <BookingField
      v-if="selected('custom_link')"
      data-link
      type="url"
      :maxlength="MAX_TEXT"
      :model-value="valueOf('custom_link', 'url')"
      :label="t('BOOKING.WHERE.LINK_LABEL')"
      :placeholder="t('BOOKING.WHERE.LINK_PLACEHOLDER')"
      :error="errorText('LINK')"
      @update:model-value="updateLocation('custom_link', 'url', $event)"
    />
    <BookingField
      v-if="selected('in_person')"
      data-address
      :maxlength="MAX_TEXT"
      :model-value="valueOf('in_person', 'address')"
      :label="t('BOOKING.WHERE.ADDRESS_LABEL')"
      :placeholder="t('BOOKING.WHERE.ADDRESS_PLACEHOLDER')"
      :error="errorText('ADDRESS')"
      @update:model-value="updateLocation('in_person', 'address', $event)"
    />

    <div v-if="chosenCalendar" class="flex flex-col gap-2">
      <p class="m-0 text-base font-semibold text-n-slate-12">
        {{ t('BOOKING.WHERE.CALENDAR_LABEL') }}
      </p>
      <ChoiceSelect
        data-calendar
        :model-value="form.calendarInboxId ?? ''"
        :options="inboxOptions"
        :aria-label="t('BOOKING.WHERE.CALENDAR_LABEL')"
        :invalid="error === 'CALENDAR'"
        @update:model-value="emit('change', { calendarInboxId: $event })"
      />
    </div>

    <p
      v-if="!calendarLocations.length"
      data-calendar-hint
      class="flex items-start gap-3 m-0 px-4 py-3 text-base rounded-xl bg-n-alpha-1 text-n-slate-11"
    >
      <span class="i-lucide-info mt-0.5 size-5 shrink-0" aria-hidden="true" />
      {{ t('BOOKING.WHERE.CALENDAR_HINT') }}
    </p>

    <p
      v-if="error === 'LOCATION' || error === 'CALENDAR'"
      role="alert"
      class="m-0 text-base text-n-ruby-11"
    >
      {{ t(`BOOKING.WIZARD.ERRORS.${error}`) }}
    </p>
  </section>
</template>
