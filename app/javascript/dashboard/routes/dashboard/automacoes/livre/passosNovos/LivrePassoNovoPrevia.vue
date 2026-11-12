<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { P } from './passosNovos';
import { linhaDoEnsaioNovo, linhaDoHistoricoNovo } from './frasesDosNovos';

// Protótipo #2931–#2936 — mostrar antes de fazer: como o passo aparece no
// ensaio ("o que aconteceria") e no histórico ("o que aconteceu"). O ensaio é o
// mesmo do botão Ensaiar; o histórico é um exemplo, até o motor existir.
const props = defineProps({
  passo: { type: Object, required: true },
});

const { t } = useI18n();
const ensaio = computed(() => linhaDoEnsaioNovo(props.passo, t));
const historico = computed(() => linhaDoHistoricoNovo(props.passo, t));
const dentroAberto = ref(false);
</script>

<template>
  <section
    data-previa
    class="flex flex-col gap-4 p-4 border rounded-2xl border-n-weak"
    :aria-label="$t(`${P}.PREVIA.TITULO`)"
  >
    <h4 class="mb-0 text-sm font-semibold text-n-slate-12">
      {{ $t(`${P}.PREVIA.TITULO`) }}
    </h4>

    <div data-previa-ensaio class="flex items-start gap-3">
      <span
        class="grid rounded-lg place-items-center size-8 shrink-0 bg-n-blue-3 text-n-blue-11"
        aria-hidden="true"
      >
        <span class="i-lucide-flask-conical size-4" />
      </span>
      <div class="flex flex-col flex-1 min-w-0 gap-2">
        <span class="text-xs font-medium text-n-slate-11">
          {{ $t(`${P}.PREVIA.NO_ENSAIO`) }}
        </span>
        <p class="mb-0 text-[0.9375rem] text-n-slate-12">
          {{ ensaio.destaque }}
        </p>
        <div
          v-if="ensaio.balao"
          data-previa-balao
          class="self-start max-w-[18rem] px-4 py-2.5 text-[0.9375rem] rounded-2xl rounded-ss-sm shadow-sm bg-n-teal-3 text-n-slate-12 whitespace-pre-line"
        >
          {{ ensaio.balao }}
        </div>
      </div>
    </div>

    <div data-previa-historico class="flex items-start gap-3">
      <span
        class="grid rounded-lg place-items-center size-8 shrink-0 bg-n-teal-3 text-n-teal-11"
        aria-hidden="true"
      >
        <span class="i-lucide-check size-4" />
      </span>
      <div class="flex flex-col flex-1 min-w-0 gap-1">
        <span class="text-xs font-medium text-n-slate-11">
          {{ $t(`${P}.PREVIA.NO_HISTORICO`) }}
        </span>
        <p class="mb-0 text-[0.9375rem] text-n-slate-12">
          {{ historico.texto }}
        </p>
        <p v-if="historico.detalhe" class="mb-0 text-sm text-n-slate-11">
          {{ historico.detalhe }}
        </p>
        <template v-if="historico.dentro?.length">
          <button
            type="button"
            data-previa-dentro
            :aria-expanded="dentroAberto"
            class="inline-flex items-center self-start gap-1.5 text-sm font-medium rounded-lg min-h-11 text-n-blue-11 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            @click="dentroAberto = !dentroAberto"
          >
            <span
              class="size-4 rtl:rotate-180"
              :class="
                dentroAberto
                  ? 'i-lucide-chevron-down'
                  : 'i-lucide-chevron-right'
              "
              aria-hidden="true"
            />
            {{ $t(`${P}.PREVIA.VER_DENTRO`) }}
          </button>
          <ol
            v-if="dentroAberto"
            class="flex flex-col gap-1 m-0 text-sm ps-5 text-n-slate-12"
          >
            <li v-for="(linha, i) in historico.dentro" :key="i">{{ linha }}</li>
          </ol>
        </template>
      </div>
    </div>
  </section>
</template>
