<script setup>
import { computed, onMounted, ref } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import MetaAdsFunnelCard from './MetaAdsFunnelCard.vue';

// Anúncios da Meta (#1047), passo 4 (CA-1.8): os funis ligados ao WhatsApp oficial, cada um com o que
// falta para a Meta receber os avanços e as vendas. Grava no próprio funil, o mesmo que Editar funil.
const props = defineProps({
  connection: { type: Object, required: true },
});

const emit = defineEmits(['finished', 'later']);

const loading = ref(true);
const failed = ref(false);
const data = ref({ funnels: [], unlinked_numbers: [], ai_available: false });

const anyReady = computed(() =>
  data.value.funnels.some(funnel => funnel.missing.length === 0)
);
const unlinked = computed(() =>
  data.value.unlinked_numbers.map(number => number.name).join(', ')
);
const siteWithoutPixel = computed(
  () => props.connection.destinations?.site && !props.connection.pixel
);

const load = async () => {
  loading.value = true;
  failed.value = false;
  try {
    const response = await CrmMetaAdsConnectionAPI.funnels();
    data.value = response.data;
  } catch {
    failed.value = true;
  } finally {
    loading.value = false;
  }
};

onMounted(load);
</script>

<template>
  <section data-meta-ads-funnels class="flex flex-col gap-4">
    <header class="flex flex-col max-w-2xl gap-1">
      <h3 class="m-0 text-xl font-semibold tracking-tight text-n-slate-12">
        {{ $t('CRM_KANBAN.META_ADS_HUB.FUNNEL.TITLE') }}
      </h3>
      <p class="m-0 text-sm leading-6 text-n-slate-11">
        {{ $t('CRM_KANBAN.META_ADS_HUB.FUNNEL.HINT') }}
      </p>
    </header>

    <div
      v-if="loading"
      class="flex items-center gap-3 p-5 text-sm rounded-xl bg-n-alpha-1 text-n-slate-11"
    >
      <Spinner class="size-4" />
      {{ $t('CRM_KANBAN.META_ADS_HUB.FUNNEL.LOADING') }}
    </div>

    <div
      v-else-if="failed"
      role="alert"
      class="flex flex-wrap items-center gap-3 p-4 rounded-xl bg-n-amber-2"
    >
      <span class="text-sm text-n-amber-11">
        {{ $t('CRM_KANBAN.META_ADS_HUB.FUNNEL.LOAD_ERROR') }}
      </span>
      <Button
        class="!min-h-11 !rounded-xl"
        size="sm"
        icon="i-lucide-refresh-cw"
        :label="$t('CRM_KANBAN.META_ADS_HUB.FUNNEL.RETRY')"
        @click="load"
      />
    </div>

    <template v-else>
      <p
        v-if="siteWithoutPixel"
        class="p-4 m-0 text-sm rounded-xl bg-n-amber-2 text-n-amber-11"
      >
        {{ $t('CRM_KANBAN.META_ADS_HUB.FUNNEL.NEEDS_PIXEL') }}
      </p>

      <div
        v-if="!data.funnels.length"
        data-funnels-empty
        class="flex flex-wrap items-center gap-3 p-4 rounded-xl bg-n-alpha-1"
      >
        <span class="text-sm text-n-slate-11">
          {{ $t('CRM_KANBAN.META_ADS_HUB.FUNNEL.EMPTY') }}
        </span>
        <router-link
          :to="{ name: 'crm_kanban_index' }"
          class="text-sm font-semibold underline rounded text-n-blue-11 underline-offset-2"
        >
          {{ $t('CRM_KANBAN.META_ADS_HUB.FUNNEL.EMPTY_CTA') }}
        </router-link>
      </div>

      <MetaAdsFunnelCard
        v-for="funnel in data.funnels"
        :key="funnel.id"
        :funnel="funnel"
        :ai-available="data.ai_available"
        @updated="data = $event"
      />

      <p
        v-if="data.unlinked_numbers.length"
        data-funnels-unlinked
        class="flex items-start gap-2 p-4 m-0 text-sm rounded-xl bg-n-amber-2 text-n-amber-11"
      >
        <span
          class="flex-none mt-0.5 i-lucide-circle-alert size-4"
          aria-hidden="true"
        />
        {{
          $t(
            'CRM_KANBAN.META_ADS_HUB.FUNNEL.UNLINKED',
            { numbers: unlinked },
            data.unlinked_numbers.length
          )
        }}
      </p>
    </template>

    <div class="flex flex-wrap items-center gap-x-4 gap-y-2">
      <Button
        v-if="anyReady"
        data-funnels-finish
        class="!min-h-11 !rounded-xl"
        icon="i-lucide-check"
        :label="$t('CRM_KANBAN.META_ADS_HUB.FUNNEL.FINISH')"
        @click="emit('finished')"
      />
      <button
        v-else
        type="button"
        data-funnels-later
        class="inline-flex items-center px-2 text-sm underline bg-transparent border-0 rounded-lg min-h-11 text-n-slate-11 underline-offset-2 hover:text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        @click="emit('later')"
      >
        {{ $t('CRM_KANBAN.META_ADS_HUB.FUNNEL.LATER') }}
      </button>
    </div>
  </section>
</template>
