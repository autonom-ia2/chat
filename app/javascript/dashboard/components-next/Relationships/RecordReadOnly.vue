<script setup>
defineProps({ rows: { type: Array, default: () => [] } });
</script>

<template>
  <section class="grid w-full min-w-0 gap-5" data-record-read-only>
    <p
      class="m-0 flex items-start gap-2 rounded-xl border border-n-weak bg-n-solid-2 p-4 text-sm leading-6 text-n-slate-11"
    >
      <span
        class="i-lucide-eye mt-1 size-4 shrink-0 text-n-blue-11"
        aria-hidden="true"
      />
      {{ $t('CRM_KANBAN.RELATIONSHIP.READ_ONLY') }}
    </p>
    <dl v-if="rows.length" class="m-0 grid grid-cols-1 gap-5 sm:grid-cols-2">
      <div v-for="row in rows" :key="row.key" class="min-w-0">
        <dt class="mb-1 text-xs text-n-slate-11">{{ $t(row.label) }}</dt>
        <dd class="m-0 break-words text-sm leading-6 text-n-slate-12">
          {{
            row.value === '' || row.value == null
              ? $t('CRM_KANBAN.RELATIONSHIP.NOT_INFORMED')
              : row.value
          }}
        </dd>
      </div>
    </dl>
  </section>
</template>
