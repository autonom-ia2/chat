<script setup>
// Importar contatos (#1006): the "Empresas" block (C1–C6) with the "Criar e ligar" switch.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { companyPreview, formatCount } from './contactImportView';

const props = defineProps({
  contactImport: { type: Object, required: true },
  columnName: { type: String, default: '' },
  disabled: { type: Boolean, default: false },
});

const enabled = defineModel({ type: Boolean, default: true });

const NS = 'CONTACT_IMPORT_JOURNEY.COMPANIES';
const { t, locale } = useI18n();
const n = value => formatCount(locale.value, value);

const tiles = computed(() => {
  const preview = companyPreview(props.contactImport);
  return [
    { key: 'NEW', value: preview.created },
    { key: 'REUSED', value: preview.reused },
    { key: 'LINKED', value: preview.linked },
    { key: 'KEPT', value: preview.kept, warn: true },
  ];
});

const toggle = () => {
  enabled.value = !enabled.value;
};
</script>

<template>
  <section
    class="flex flex-col gap-3 rounded-xl border border-n-weak p-4"
    :aria-label="t(`${NS}.TITLE`)"
  >
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div>
        <h2 class="mb-0 text-sm font-semibold text-n-slate-12">
          {{ t(`${NS}.TITLE`) }}
        </h2>
        <p v-if="columnName" class="mb-0 text-xs text-n-slate-11">
          {{ t(`${NS}.HINT`, { column: columnName }) }}
        </p>
      </div>
      <button
        type="button"
        role="switch"
        :aria-checked="enabled"
        :aria-label="t(`${NS}.SWITCH_LABEL`)"
        :disabled="disabled"
        class="flex min-h-11 items-center gap-2 rounded-lg px-2 text-sm font-medium text-n-slate-12 disabled:opacity-50"
        data-test="companies-switch"
        @click="toggle"
      >
        <span
          class="relative h-5 w-9 rounded-full transition-colors"
          :class="enabled ? 'bg-n-brand' : 'bg-n-slate-6'"
          aria-hidden="true"
        >
          <span
            class="absolute top-0.5 size-4 rounded-full bg-n-background shadow transition-transform ltr:left-0.5 rtl:right-0.5"
            :class="enabled ? 'ltr:translate-x-4 rtl:-translate-x-4' : ''"
          />
        </span>
        {{ enabled ? t(`${NS}.ON`) : t(`${NS}.OFF`) }}
      </button>
    </div>
    <ul
      v-if="enabled"
      class="m-0 grid list-none grid-cols-2 gap-3 p-0 md:grid-cols-4"
    >
      <li
        v-for="tile in tiles"
        :key="tile.key"
        class="rounded-lg p-3"
        :class="tile.warn ? 'bg-n-amber-2' : 'bg-n-slate-2'"
        :data-company-tile="tile.key"
      >
        <p class="mb-0 text-xl font-semibold tabular-nums text-n-slate-12">
          {{ n(tile.value) }}
        </p>
        <p class="mb-0 text-xs text-n-slate-11">{{ t(`${NS}.${tile.key}`) }}</p>
      </li>
    </ul>
    <p v-else class="mb-0 text-xs text-n-slate-11" data-test="companies-off">
      {{ t(`${NS}.DISABLED`) }}
    </p>
  </section>
</template>
