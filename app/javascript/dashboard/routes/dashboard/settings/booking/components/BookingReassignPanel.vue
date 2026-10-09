<script setup>
import { computed, nextTick, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import BookingPagesAPI from 'dashboard/api/crmBookingPages';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import BookingToggle from './BookingToggle.vue';

// Passar reuniões (#1195, J8-A10): de quem, para quem, só desta página ou de
// todas. Primeiro mostra o que vai acontecer (prévia, sem gravar), depois passa.
// O servidor confere se a pessoa nova está livre em cada horário: o que bate
// com outro compromisso fica como está e aparece na lista.
const props = defineProps({
  page: { type: Object, required: true },
});

const emit = defineEmits(['close', 'done']);
const { t, locale } = useI18n();

const people = ref([]);
const loading = ref(true);
const fromId = ref(null);
const toId = ref(null);
const onlyThisPage = ref(true);
// null | { moved, conflicts }
const preview = ref(null);
const result = ref(null);
const busy = ref(false);
const problem = ref('');
const heading = ref(null);

const nameOf = id => people.value.find(person => person.id === id)?.name;
const toName = computed(() => nameOf(toId.value) || '');

const fromOptions = computed(() =>
  people.value.map(person => ({ value: person.id, label: person.name }))
);
const toOptions = computed(() =>
  fromOptions.value.filter(option => option.value !== fromId.value)
);
const ready = computed(
  () => fromId.value !== null && toId.value !== null && !busy.value
);

const resetPreview = () => {
  preview.value = null;
  result.value = null;
  problem.value = '';
};

const chooseFrom = value => {
  fromId.value = value;
  if (toId.value === value) toId.value = null;
  resetPreview();
};
const chooseTo = value => {
  toId.value = value;
  resetPreview();
};
const togglePage = () => {
  onlyThisPage.value = !onlyThisPage.value;
  resetPreview();
};

const request = () => ({
  fromUserId: fromId.value,
  toUserId: toId.value,
  pageId: onlyThisPage.value ? props.page.id : null,
});

const failure = error =>
  error?.response?.data?.error === 'crm.booking_v2.people_invalid'
    ? t('BOOKING.REASSIGN.PEOPLE_INVALID')
    : t('BOOKING.REASSIGN.ERROR');

const run = async action => {
  busy.value = true;
  problem.value = '';
  try {
    await action();
  } catch (error) {
    problem.value = failure(error);
  } finally {
    busy.value = false;
  }
};

const showPreview = () =>
  run(async () => {
    const { data } = await BookingPagesAPI.reassignPreview(request());
    preview.value = data.payload;
  });

const confirm = () =>
  run(async () => {
    const { data } = await BookingPagesAPI.reassign(request());
    preview.value = null;
    result.value = data.payload;
    emit('done', data.payload);
  });

const when = iso =>
  new Date(iso).toLocaleString(locale.value, {
    weekday: 'short',
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });

onMounted(async () => {
  try {
    const { data } = await BookingPagesAPI.people(props.page.id);
    people.value = data.payload || [];
  } catch {
    problem.value = t('BOOKING.REASSIGN.ERROR');
  } finally {
    loading.value = false;
  }
  await nextTick();
  heading.value?.focus();
});

const SECONDARY =
  'inline-flex items-center gap-2 min-h-11 px-4 rounded-xl text-base font-medium ring-1 ring-inset focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand disabled:opacity-60 disabled:cursor-not-allowed';
</script>

<template>
  <section
    data-reassign-panel
    class="flex flex-col gap-4 p-4 rounded-xl bg-n-alpha-1 ring-1 ring-inset ring-n-weak"
    :aria-label="t('BOOKING.REASSIGN.TITLE')"
  >
    <h4
      ref="heading"
      tabindex="-1"
      class="m-0 text-base font-semibold text-n-slate-12 focus:outline-none"
    >
      {{ t('BOOKING.REASSIGN.TITLE') }}
    </h4>
    <p class="m-0 text-base text-n-slate-11">
      {{ t('BOOKING.REASSIGN.HINT') }}
    </p>

    <p v-if="loading" aria-busy="true" class="m-0 text-base text-n-slate-11">
      {{ t('BOOKING.LIST.LOADING') }}
    </p>

    <template v-else-if="!result">
      <div class="grid gap-4 sm:grid-cols-2">
        <div class="flex flex-col gap-2">
          <p class="m-0 text-base font-semibold text-n-slate-12">
            {{ t('BOOKING.REASSIGN.FROM') }}
          </p>
          <ChoiceSelect
            data-from
            :model-value="fromId ?? ''"
            :options="fromOptions"
            :placeholder="t('BOOKING.REASSIGN.CHOOSE')"
            :aria-label="t('BOOKING.REASSIGN.FROM')"
            @update:model-value="chooseFrom"
          />
        </div>
        <div class="flex flex-col gap-2">
          <p class="m-0 text-base font-semibold text-n-slate-12">
            {{ t('BOOKING.REASSIGN.TO') }}
          </p>
          <ChoiceSelect
            data-to
            :model-value="toId ?? ''"
            :options="toOptions"
            :placeholder="t('BOOKING.REASSIGN.CHOOSE')"
            :aria-label="t('BOOKING.REASSIGN.TO')"
            :disabled="fromId === null"
            @update:model-value="chooseTo"
          />
        </div>
      </div>

      <div class="flex">
        <BookingToggle
          data-only-page
          :label="t('BOOKING.REASSIGN.ONLY_THIS_PAGE')"
          :pressed="onlyThisPage"
          @toggle="togglePage"
        />
      </div>

      <div
        v-if="preview"
        data-preview
        role="status"
        class="flex flex-col gap-3 p-4 rounded-xl bg-n-solid-1 ring-1 ring-inset ring-n-weak"
      >
        <p class="m-0 text-base font-medium text-n-slate-12">
          {{
            t(
              'BOOKING.REASSIGN.WILL_MOVE',
              { name: toName, count: preview.moved },
              preview.moved
            )
          }}
        </p>
        <template v-if="preview.conflicts.length">
          <p class="m-0 text-base text-n-amber-11">
            {{ t('BOOKING.REASSIGN.CONFLICTS', { name: toName }) }}
          </p>
          <ul class="flex flex-col gap-1 p-0 m-0 list-none">
            <li
              v-for="item in preview.conflicts"
              :key="item.meeting_id"
              :data-conflict="item.meeting_id"
              class="text-base text-n-slate-12"
            >
              {{ when(item.starts_at) }} · {{ item.title }}
            </li>
          </ul>
        </template>
      </div>

      <p v-if="problem" role="alert" class="m-0 text-base text-n-ruby-11">
        {{ problem }}
      </p>

      <div class="flex flex-wrap gap-2">
        <button
          v-if="!preview"
          type="button"
          data-preview-button
          :disabled="!ready"
          :class="SECONDARY"
          class="text-white bg-n-blue-9 ring-n-blue-9 hover:bg-n-blue-10"
          @click="showPreview"
        >
          {{ t('BOOKING.REASSIGN.PREVIEW') }}
        </button>
        <button
          v-else
          type="button"
          data-confirm-reassign
          :disabled="busy || !preview.moved"
          :class="SECONDARY"
          class="text-white bg-n-blue-9 ring-n-blue-9 hover:bg-n-blue-10"
          @click="confirm"
        >
          {{ t('BOOKING.REASSIGN.CONFIRM', { name: toName }) }}
        </button>
        <button
          type="button"
          data-cancel-reassign
          :class="SECONDARY"
          class="text-n-slate-12 bg-n-solid-1 ring-n-weak"
          @click="emit('close')"
        >
          {{ t('BOOKING.REASSIGN.CANCEL') }}
        </button>
      </div>
    </template>

    <template v-else>
      <p
        data-result
        role="status"
        class="m-0 text-base font-medium text-n-teal-11"
      >
        {{
          t(
            'BOOKING.REASSIGN.DONE',
            { name: toName, count: result.moved },
            result.moved
          )
        }}
      </p>
      <p v-if="result.conflicts.length" class="m-0 text-base text-n-amber-11">
        {{
          t(
            'BOOKING.REASSIGN.DONE_CONFLICTS',
            { name: toName, count: result.conflicts.length },
            result.conflicts.length
          )
        }}
      </p>
      <button
        type="button"
        data-close-reassign
        :class="SECONDARY"
        class="self-start text-n-slate-12 bg-n-solid-1 ring-n-weak"
        @click="emit('close')"
      >
        {{ t('BOOKING.REASSIGN.CLOSE') }}
      </button>
    </template>
  </section>
</template>
