<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import { relativeTime } from '../metaAdsHelpers';

// Uma Página do Facebook nos Formulários (#2195): os formulários dela, cada um com para onde vai quem preenche.
// O recebimento liga sozinho no primeiro funil escolhido; parar fica no menu "⋯", com confirmação. Formulário
// arquivado não recebe ninguém novo: fica recolhido em "Formulários antigos".
const props = defineProps({
  page: { type: Object, required: true },
  readOnly: { type: Boolean, default: false },
  busy: { type: Boolean, default: false },
});

const emit = defineEmits(['stop', 'resume', 'choose']);

const KEY = 'CRM_KANBAN.META_ADS_HUB.LEAD_FORMS';
const { t, locale } = useI18n();

const menuOpen = ref(false);
const confirmStop = ref(null);

const activeForms = computed(() =>
  props.page.forms.filter(form => form.status === 'ACTIVE')
);
const oldForms = computed(() =>
  props.page.forms.filter(form => form.status !== 'ACTIVE')
);
// Parada depois de ter funil escolhido: os destinos continuam guardados, mas ninguém novo entra até voltar.
const paused = computed(
  () =>
    !props.page.receiving && activeForms.value.some(form => form.destination)
);
const menuItems = computed(() => [
  {
    label: t(`${KEY}.STOP`),
    action: 'stop',
    value: 'stop',
    icon: 'i-lucide-circle-stop',
  },
]);

const formMeta = form => {
  const filled = t(
    `${KEY}.FILLED`,
    { count: form.leads_count },
    form.leads_count
  );
  if (!form.leads_count || !form.last_lead_at) return filled;
  const when = relativeTime(form.last_lead_at, locale.value);
  return t(`${KEY}.FILLED_LAST`, { filled, when });
};

const askStop = () => {
  menuOpen.value = false;
  confirmStop.value?.open();
};

const stop = () => {
  confirmStop.value?.close();
  emit('stop');
};
</script>

<template>
  <article
    :data-lead-page="page.id"
    class="flex flex-col gap-4 p-4 border border-solid rounded-xl border-n-weak bg-n-solid-1 sm:p-5"
  >
    <header class="flex flex-wrap items-center justify-between gap-3">
      <div class="flex items-center min-w-0 gap-3">
        <span
          class="grid flex-none rounded-xl size-10 place-items-center bg-n-blue-3 text-n-blue-11"
          aria-hidden="true"
        >
          <span class="i-ri-facebook-circle-fill size-5" />
        </span>
        <div class="flex flex-col min-w-0 gap-0.5">
          <h3 class="m-0 text-base font-semibold truncate text-n-slate-12">
            {{ page.name }}
          </h3>
          <span
            v-if="page.receiving"
            data-lead-page-status
            class="inline-flex items-center gap-1 text-xs font-medium text-n-teal-11"
          >
            <span
              class="rounded-full size-1.5 bg-n-teal-9"
              aria-hidden="true"
            />
            {{ $t(`${KEY}.RECEIVING`) }}
          </span>
          <span
            v-else-if="paused"
            data-lead-page-paused
            class="inline-flex items-center gap-1 text-xs font-medium text-n-amber-11"
          >
            <span class="i-lucide-circle-pause size-3.5" aria-hidden="true" />
            {{ $t(`${KEY}.PAUSED`) }}
          </span>
          <span v-else class="text-xs text-n-slate-11">
            {{ $t(`${KEY}.FACEBOOK_PAGE`) }}
          </span>
        </div>
      </div>
      <Button
        v-if="paused && !readOnly"
        data-lead-page-resume
        class="!min-h-11 !rounded-xl w-full sm:w-auto sm:flex-none"
        variant="solid"
        color="blue"
        size="sm"
        :is-loading="busy"
        :label="$t(`${KEY}.RESUME`)"
        @click="emit('resume')"
      />
      <div
        v-if="page.receiving && !readOnly"
        v-on-clickaway="() => (menuOpen = false)"
        class="relative flex-none"
      >
        <Button
          data-lead-page-menu
          icon="i-lucide-ellipsis-vertical"
          color="slate"
          variant="ghost"
          class="!min-h-11 !min-w-11"
          :is-loading="busy"
          :aria-label="$t(`${KEY}.PAGE_MENU`, { page: page.name })"
          :aria-expanded="menuOpen"
          @click="menuOpen = !menuOpen"
        />
        <DropdownMenu
          v-if="menuOpen"
          data-lead-page-menu-list
          :menu-items="menuItems"
          class="ltr:right-0 rtl:left-0 mt-1 w-56 top-full"
          @action="askStop"
        />
      </div>
    </header>

    <p
      v-if="page.error"
      role="status"
      class="m-0 text-sm text-n-slate-11"
      data-lead-page-error
    >
      {{
        $t(
          page.error === 'meta_refused'
            ? `${KEY}.PAGE_REFUSED`
            : `${KEY}.PAGE_UNAVAILABLE`
        )
      }}
    </p>

    <p
      v-else-if="!activeForms.length"
      class="m-0 text-sm text-n-slate-11"
      data-lead-page-empty
    >
      {{ $t(`${KEY}.NO_FORMS`) }}
    </p>

    <ul v-else class="flex flex-col gap-2 p-0 m-0 list-none">
      <li
        v-for="form in activeForms"
        :key="form.id"
        :data-lead-form="form.id"
        class="flex flex-col gap-3 px-3 py-3 rounded-xl bg-n-alpha-1 sm:flex-row sm:items-center sm:justify-between"
      >
        <div class="flex flex-col min-w-0 gap-1">
          <span class="text-sm font-semibold text-n-slate-12">
            {{ form.name }}
          </span>
          <span class="text-xs text-n-slate-11">{{ formMeta(form) }}</span>
          <span
            v-if="form.destination && paused"
            data-lead-form-paused
            class="inline-flex items-center gap-1 text-sm text-n-amber-11"
          >
            <span class="i-lucide-circle-pause size-4" aria-hidden="true" />
            {{ $t(`${KEY}.PAUSED_LINE`) }}
          </span>
          <span
            v-else-if="form.destination"
            data-lead-form-destination
            class="flex items-start gap-1 text-sm text-n-slate-12"
          >
            <span
              class="flex-none mt-0.5 i-lucide-arrow-right size-4 text-n-teal-11"
              aria-hidden="true"
            />
            {{
              $t(`${KEY}.GOES_TO`, {
                pipeline: form.destination.pipeline_name,
                stage: form.destination.stage_name,
              })
            }}
          </span>
          <span
            v-else
            data-lead-form-missing
            class="inline-flex items-center gap-1 text-sm text-n-amber-11"
          >
            <span class="i-lucide-circle-alert size-4" aria-hidden="true" />
            {{ $t(`${KEY}.NOWHERE`) }}
          </span>
        </div>
        <Button
          v-if="!readOnly"
          data-lead-form-choose
          class="!min-h-11 !rounded-xl sm:flex-none"
          :variant="form.destination || paused ? 'faded' : 'solid'"
          :color="form.destination ? 'slate' : 'blue'"
          size="sm"
          :label="form.destination ? $t(`${KEY}.CHANGE`) : $t(`${KEY}.CHOOSE`)"
          @click="emit('choose', form, paused)"
        />
      </li>
    </ul>

    <details
      v-if="oldForms.length"
      data-lead-page-old
      class="group rounded-xl border border-solid border-n-weak"
    >
      <summary
        class="flex items-center justify-between gap-2 px-3 text-sm font-medium cursor-pointer min-h-11 text-n-slate-11 list-none focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand rounded-xl"
      >
        {{ $t(`${KEY}.OLD_FORMS`, { count: oldForms.length }) }}
        <span
          class="i-lucide-chevron-down size-4 transition-transform group-open:rotate-180"
          aria-hidden="true"
        />
      </summary>
      <ul class="flex flex-col gap-2 p-3 pt-0 m-0 list-none">
        <li
          v-for="form in oldForms"
          :key="form.id"
          :data-lead-form="form.id"
          class="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between"
        >
          <div class="flex flex-col min-w-0 gap-0.5">
            <span class="text-sm text-n-slate-12">{{ form.name }}</span>
            <span class="text-xs text-n-slate-11">{{ formMeta(form) }}</span>
            <span
              v-if="form.brought"
              data-lead-form-brought
              class="flex items-start gap-1 text-sm text-n-slate-12"
            >
              <span
                class="flex-none mt-0.5 i-lucide-check size-4 text-n-teal-11"
                aria-hidden="true"
              />
              {{
                $t(
                  `${KEY}.BROUGHT_LINE`,
                  {
                    count: form.brought.count,
                    pipeline: form.brought.pipeline_name,
                    stage: form.brought.stage_name,
                  },
                  form.brought.count
                )
              }}
            </span>
          </div>
          <Button
            v-if="!readOnly && !form.brought && form.past_count"
            data-lead-form-bring-old
            class="!min-h-11 !rounded-xl sm:flex-none"
            variant="faded"
            color="slate"
            size="sm"
            :label="$t(`${KEY}.BRING_OLD`)"
            @click="emit('choose', form)"
          />
        </li>
      </ul>
    </details>

    <Dialog
      ref="confirmStop"
      type="alert"
      :title="$t(`${KEY}.STOP_TITLE`, { page: page.name })"
      :description="$t(`${KEY}.STOP_HINT`)"
      :confirm-button-label="$t(`${KEY}.STOP`)"
      :cancel-button-label="$t(`${KEY}.KEEP`)"
      @confirm="stop"
    />
  </article>
</template>
