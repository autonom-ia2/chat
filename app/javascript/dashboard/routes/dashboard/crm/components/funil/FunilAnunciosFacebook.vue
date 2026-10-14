<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';

// #1384 — o que o Facebook e o Instagram recebem, numa tela própria. A venda
// feita vem marcada; avisar numa etapa antes da venda é um único seletor; o
// código do site fica fechado até a pessoa precisar.
const props = defineProps({
  // [{ editorKey, name, color }]
  etapas: { type: Array, default: () => [] },
  // editorKey da etapa em que também avisamos ('' = nenhuma).
  etapaAvisada: { type: String, default: '' },
});

const emit = defineEmits(['avisarEm']);

const meta = defineModel('meta', { type: Object, required: true });

const { t } = useI18n();
const A = 'CRM_FUNIL.ANUNCIOS';

const siteAberto = ref(Boolean(meta.value.pixelId || meta.value.datasetId));

const PIXEL_MAX = 20;
const soNumeros = valor =>
  [...String(valor || '')]
    .filter(letra => letra >= '0' && letra <= '9')
    .join('')
    .slice(0, PIXEL_MAX);

const mudar = mudanca => {
  meta.value = { ...meta.value, ...mudanca };
};
const marcar = (evento, valor) =>
  mudar({ events: { ...meta.value.events, [evento]: valor } });
// Pixel só tem números (contrato #1011, até 20): colar com espaço ou letra
// não falha ao salvar.
const aoDigitarPixel = evento => {
  const digitos = soNumeros(evento.target.value);
  mudar({ pixelId: digitos });
  evento.target.value = digitos;
};

const NENHUMA = '';
const opcoesEtapa = computed(() => [
  { value: NENHUMA, label: t(`${A}.FACEBOOK.SO_NA_VENDA`) },
  ...props.etapas.map(etapa => ({ value: etapa.editorKey, label: etapa.name })),
]);
const etapaEscolhida = computed(() =>
  meta.value.events.moved ? props.etapaAvisada : NENHUMA
);
const escolherEtapa = chave => {
  marcar('moved', chave !== NENHUMA);
  emit('avisarEm', chave);
};

const EVENTOS = ['won', 'lost'];
</script>

<template>
  <div data-anuncio-facebook class="flex flex-col gap-4">
    <label
      v-for="evento in EVENTOS"
      :key="evento"
      :data-evento="evento"
      class="flex min-h-11 cursor-pointer items-start gap-3 rounded-2xl border p-4 shadow-sm focus-within:outline focus-within:outline-2 focus-within:outline-n-brand"
      :class="[
        evento === 'lost' ? 'order-2' : 'order-none',
        meta.events[evento]
          ? 'border-n-blue-8 bg-n-blue-2'
          : 'border-n-weak bg-n-solid-1',
      ]"
    >
      <input
        type="checkbox"
        class="mt-0.5 size-5 shrink-0 rounded border-n-weak"
        :checked="meta.events[evento]"
        @change="marcar(evento, $event.target.checked)"
      />
      <span class="flex min-w-0 flex-col gap-0.5">
        <span class="text-base font-semibold text-n-slate-12">
          {{ $t(`${A}.EVENTOS.${evento.toUpperCase()}`) }}
        </span>
        <span class="text-[0.9375rem] text-n-slate-11">
          {{ $t(`${A}.POR_QUE.${evento.toUpperCase()}`) }}
        </span>
      </span>
    </label>

    <section
      data-anuncio-etapa
      class="order-1 flex flex-col gap-2 rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm"
    >
      <span
        id="funil-anuncio-etapa"
        class="text-base font-semibold text-n-slate-12"
      >
        {{ $t(`${A}.FACEBOOK.AVISAR_EM`) }}
      </span>
      <span class="text-[0.9375rem] text-n-slate-11">
        {{ $t(`${A}.POR_QUE.MOVED`) }}
      </span>
      <ChoiceSelect
        :model-value="etapaEscolhida"
        :options="opcoesEtapa"
        :aria-label="$t(`${A}.FACEBOOK.AVISAR_EM`)"
        class="mt-1 w-full sm:w-72"
        @update:model-value="escolherEtapa"
      />
    </section>

    <section class="order-3 flex flex-col gap-3">
      <button
        type="button"
        data-site
        :aria-expanded="siteAberto"
        class="flex min-h-11 w-fit items-center gap-2 rounded-xl px-1 text-start text-[0.9375rem] font-medium text-n-blue-11 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        @click="siteAberto = !siteAberto"
      >
        {{ $t(`${A}.SITE`) }}
        <span
          class="size-4"
          :class="siteAberto ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
          aria-hidden="true"
        />
      </button>
      <div
        v-show="siteAberto"
        class="flex flex-col gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-4"
      >
        <p class="mb-0 text-[0.9375rem] text-n-slate-11">
          {{ $t(`${A}.SITE_AJUDA`) }}
        </p>
        <label class="flex flex-col gap-1">
          <span class="text-sm font-medium text-n-slate-12">
            {{ $t(`${A}.PIXEL`) }}
          </span>
          <input
            :value="meta.pixelId"
            type="text"
            inputmode="numeric"
            autocomplete="off"
            aria-describedby="crm-pipeline-pixel-help"
            class="reset-base !mb-0 w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 font-mono text-sm text-n-slate-12 placeholder:font-sans placeholder:text-n-slate-10 focus:outline focus:outline-2 focus:outline-n-brand"
            :placeholder="
              $t('CRM_KANBAN.PIPELINE_DRAWER.META_SYNC_PIXEL_PLACEHOLDER')
            "
            @input="aoDigitarPixel"
          />
          <span id="crm-pipeline-pixel-help" class="text-sm text-n-slate-11">
            {{ $t(`${A}.PIXEL_AJUDA`) }}
          </span>
        </label>
        <Input
          :model-value="meta.datasetId"
          :label="$t(`${A}.DATASET`)"
          :placeholder="$t(`${A}.DATASET_EXEMPLO`)"
          custom-input-class="!h-11 !rounded-xl !bg-n-solid-1 !px-3"
          @update:model-value="mudar({ datasetId: $event })"
        />
      </div>
    </section>
  </div>
</template>
