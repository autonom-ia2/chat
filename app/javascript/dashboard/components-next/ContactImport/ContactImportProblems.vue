<script setup>
// Importar contatos (#1006, B5): rows left out, with the reason; phone and e-mail come
// masked from the API and the name is never shown.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { formatCount } from './contactImportView';

const props = defineProps({
  contactImport: { type: Object, required: true },
  reasonText: { type: Function, required: true },
});

const emit = defineEmits(['download']);

const NS = 'CONTACT_IMPORT_JOURNEY.PEOPLE';
const { t, locale } = useI18n();
const n = value => formatCount(locale.value, value);
const open = ref(false);

const total = computed(() => props.contactImport.invalid_rows || 0);
const rows = computed(() => props.contactImport.problem_rows || []);
const contactOf = row => row.phone || row.email || t(`${NS}.EMPTY_CONTACT`);
</script>

<template>
  <div class="flex flex-col gap-3">
    <button
      type="button"
      class="flex flex-col items-start rounded-xl bg-n-amber-2 p-4 text-start disabled:cursor-default"
      :aria-expanded="open"
      :disabled="!total"
      data-test="problems-toggle"
      @click="open = !open"
    >
      <span class="text-2xl font-semibold tabular-nums text-n-slate-12">{{
        n(total)
      }}</span>
      <strong class="text-sm text-n-slate-12">{{ t(`${NS}.PROBLEMS`) }}</strong>
      <span v-if="total" class="text-xs font-semibold text-n-blue-11">
        {{ open ? t(`${NS}.HIDE_PROBLEMS`) : t(`${NS}.SHOW_PROBLEMS`) }}
      </span>
    </button>
    <div
      v-if="open && total"
      class="overflow-hidden rounded-xl border border-n-amber-6"
      data-test="problems"
    >
      <table class="w-full text-start text-xs">
        <thead class="bg-n-slate-2 text-n-slate-11">
          <tr>
            <th scope="col" class="px-3 py-2 text-start font-medium">
              {{ t(`${NS}.ROW`) }}
            </th>
            <th scope="col" class="px-3 py-2 text-start font-medium">
              {{ t(`${NS}.CONTACT`) }}
            </th>
            <th scope="col" class="px-3 py-2 text-start font-medium">
              {{ t(`${NS}.PROBLEM`) }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in rows"
            :key="row.row_number"
            class="border-t border-n-weak text-n-slate-12"
          >
            <td class="px-3 py-2 tabular-nums">{{ row.row_number }}</td>
            <td class="px-3 py-2 break-all">{{ contactOf(row) }}</td>
            <td class="px-3 py-2">
              {{ row.errors.map(reasonText).join(' · ') }}
            </td>
          </tr>
        </tbody>
      </table>
      <div
        class="flex flex-wrap items-center justify-between gap-2 border-t border-n-weak px-3 py-2"
      >
        <span class="text-xs text-n-slate-11">
          {{
            total > rows.length
              ? t(`${NS}.MORE`, { shown: n(rows.length), total: n(total) })
              : t(`${NS}.LEFT_OUT`)
          }}
        </span>
        <Button
          :label="t(`${NS}.DOWNLOAD`)"
          variant="faded"
          color="slate"
          size="sm"
          class="!min-h-11"
          @click="emit('download')"
        />
      </div>
    </div>
  </div>
</template>
