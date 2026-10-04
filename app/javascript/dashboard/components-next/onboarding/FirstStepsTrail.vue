<script setup>
import { useI18n } from 'vue-i18n';

// A trilha inteira, agrupada por etapa. Passo feito encolhe para uma linha;
// passo pendente abre no painel ao clicar. Dependência pendente só avisa.
defineProps({
  etapas: { type: Array, required: true },
  emFocoId: { type: String, default: null },
});

const emit = defineEmits(['escolher']);

const { t } = useI18n();

const pendente = passo => passo.status === 'pendente';
</script>

<template>
  <div class="flex flex-col gap-5">
    <section v-for="(etapa, indice) in etapas" :key="etapa.id">
      <h3 class="mb-2 text-sm font-semibold text-n-slate-11">
        {{ indice + 1 }}. {{ t(`ONBOARDING_TRAIL.ETAPAS.${etapa.id}`) }}
      </h3>
      <ol
        class="m-0 list-none overflow-hidden rounded-xl border border-n-weak bg-n-solid-1 p-0"
      >
        <li
          v-for="passo in etapa.passos"
          :key="passo.id"
          class="border-t border-n-weak first:border-t-0"
        >
          <button
            type="button"
            class="flex min-h-[3.75rem] w-full items-center gap-4 px-4 py-2.5 text-left"
            :class="[
              passo.id === emFocoId
                ? 'bg-n-brand/5'
                : pendente(passo) && 'hover:bg-n-alpha-1',
              !pendente(passo) && 'cursor-default',
            ]"
            :disabled="!pendente(passo)"
            :aria-current="passo.id === emFocoId ? 'step' : undefined"
            @click="emit('escolher', passo)"
          >
            <span
              class="grid size-8 shrink-0 place-items-center rounded-full border text-sm font-semibold tabular-nums"
              :class="{
                'border-n-teal-9 bg-n-teal-9 text-white':
                  passo.status === 'feito',
                'border-n-brand bg-n-solid-1 text-n-blue-11':
                  passo.id === emFocoId,
                'border-n-weak text-n-slate-10':
                  passo.status !== 'feito' && passo.id !== emFocoId,
              }"
            >
              <span
                v-if="passo.status === 'feito'"
                class="i-lucide-check size-4"
              />
              <template v-else>{{ passo.numero }}</template>
            </span>

            <span class="flex min-w-0 flex-1 flex-col">
              <span
                class="font-medium"
                :class="pendente(passo) ? 'text-n-slate-12' : 'text-n-slate-11'"
              >
                {{ passo.titulo }}
              </span>
              <span
                v-if="pendente(passo)"
                class="truncate text-sm text-n-slate-11 max-sm:hidden"
              >
                {{ passo.por_que }}
              </span>
            </span>

            <span class="flex shrink-0 items-center gap-2.5">
              <span
                v-if="passo.video && pendente(passo)"
                class="i-lucide-clapperboard size-4 text-n-slate-10 max-sm:hidden"
                :title="t('ONBOARDING_TRAIL.HAS_VIDEO')"
              />
              <span
                v-if="passo.status === 'feito'"
                class="rounded-full bg-n-teal-3 px-2.5 py-0.5 text-xs font-medium text-n-teal-11"
              >
                {{ t('ONBOARDING_TRAIL.STATUS.DONE') }}
              </span>
              <span
                v-else-if="passo.status === 'pulado'"
                class="rounded-full bg-n-alpha-2 px-2.5 py-0.5 text-xs font-medium text-n-slate-11"
              >
                {{ t('ONBOARDING_TRAIL.STATUS.SKIPPED') }}
              </span>
              <span
                v-else-if="passo.id === emFocoId"
                class="rounded-full bg-n-brand px-2.5 py-0.5 text-xs font-semibold text-white"
              >
                {{ t('ONBOARDING_TRAIL.NOW') }}
              </span>
              <span
                v-else-if="passo.depende_de?.pendente"
                class="rounded-full bg-n-amber-3 px-2.5 py-0.5 text-xs font-medium text-n-amber-11"
              >
                {{
                  t('ONBOARDING_TRAIL.WAITS_FOR', {
                    titulo: passo.depende_de.titulo,
                  })
                }}
              </span>
              <span
                v-else-if="passo.pulavel"
                class="text-xs font-medium text-n-slate-10"
              >
                {{ t('ONBOARDING_TRAIL.OPTIONAL') }}
              </span>
            </span>
          </button>
        </li>
      </ol>
    </section>
  </div>
</template>
