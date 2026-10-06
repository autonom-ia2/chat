<script setup>
// Importar contatos (#1006): what the import did.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { resultCounts, formatCount } from './contactImportView';

const props = defineProps({
  contactImport: { type: Object, required: true },
});

const emit = defineEmits(['seeContacts', 'newImport', 'download']);

const NS = 'CONTACT_IMPORT_JOURNEY';
const { t, locale } = useI18n();
const n = value => formatCount(locale.value, value);

const counts = computed(() => resultCounts(props.contactImport));
const partial = computed(
  () => props.contactImport.status === 'completed_with_failures'
);
const tiles = computed(() => [
  { key: 'IMPORTED', value: counts.value.imported },
  { key: 'CREATED', value: counts.value.created },
  { key: 'COMPANIES', value: counts.value.companies },
  { key: 'ATTRIBUTES', value: counts.value.attributes },
  { key: 'FAILED', value: counts.value.failed, warn: true },
]);
</script>

<template>
  <section
    class="flex flex-col items-center gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-6 text-center shadow-sm"
    data-test="result"
  >
    <span
      class="i-lucide-circle-check size-10 text-n-teal-10"
      aria-hidden="true"
    />
    <h2 class="mb-0 text-xl font-semibold text-n-slate-12">
      {{ partial ? t(`${NS}.RESULT.PARTIAL_TITLE`) : t(`${NS}.RESULT.TITLE`) }}
    </h2>
    <ul class="m-0 grid w-full list-none grid-cols-2 gap-3 p-0 md:grid-cols-5">
      <li
        v-for="tile in tiles"
        :key="tile.key"
        class="rounded-lg p-3"
        :class="tile.warn ? 'bg-n-amber-2' : 'bg-n-slate-2'"
        :data-result="tile.key"
      >
        <p class="mb-0 text-xl font-semibold tabular-nums text-n-slate-12">
          {{ n(tile.value) }}
        </p>
        <p class="mb-0 text-xs text-n-slate-11">
          {{ t(`${NS}.RESULT.${tile.key}`) }}
        </p>
      </li>
    </ul>
    <div class="flex flex-wrap justify-center gap-3">
      <Button
        v-if="contactImport.downloads?.error_csv"
        :label="t(`${NS}.PEOPLE.DOWNLOAD`)"
        variant="faded"
        color="slate"
        class="!min-h-11"
        @click="emit('download')"
      />
      <Button
        :label="t(`${NS}.ACTIONS.NEW_IMPORT`)"
        variant="faded"
        color="slate"
        class="!min-h-11"
        @click="emit('newImport')"
      />
      <Button
        :label="t(`${NS}.ACTIONS.SEE_CONTACTS`)"
        class="!min-h-11"
        @click="emit('seeContacts')"
      />
    </div>
  </section>
</template>
