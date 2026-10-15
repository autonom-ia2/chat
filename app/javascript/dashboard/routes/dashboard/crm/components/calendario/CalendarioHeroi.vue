<script setup>
// Calendário Ouro — o topo escuro, na família do CardHeroi (#1423): que dia é,
// um "oi" e, numa frase, quanto tem para hoje e quanto ficou para trás.
// A única ação do topo é marcar um lembrete novo.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatarDia } from './tempoNaConta';

const props = defineProps({
  hoje: { type: String, required: true },
  idioma: { type: String, required: true },
  nome: { type: String, default: '' },
  minutos: { type: Number, required: true },
  pendentes: { type: Number, default: 0 },
  atrasados: { type: Number, default: 0 },
});
defineEmits(['novo']);
const { t } = useI18n();
const N = 'CRM_CALENDARIO.HEROI';
const MEIO_DIA = 12 * 60;
const FIM_DA_TARDE = 18 * 60;

const data = computed(() =>
  formatarDia(props.hoje, props.idioma, {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
  })
);
const saudacao = computed(() => {
  let chave = 'NOITE';
  if (props.minutos < MEIO_DIA) chave = 'MANHA';
  else if (props.minutos < FIM_DA_TARDE) chave = 'TARDE';
  return props.nome
    ? t(`${N}.OI_${chave}`, { nome: props.nome })
    : t(`${N}.OI_${chave}_SEM_NOME`);
});
</script>

<template>
  <header
    data-calendario-heroi
    class="relative shrink-0 overflow-hidden bg-n-heroi px-4 py-6 text-white sm:px-8 sm:py-8"
  >
    <span
      aria-hidden="true"
      class="pointer-events-none absolute -end-16 -top-24 size-80 rounded-full border-[3rem] border-n-blue-9 opacity-15"
    />
    <span
      aria-hidden="true"
      class="pointer-events-none absolute -bottom-36 end-40 size-56 rounded-full border-[2rem] border-n-blue-7 opacity-10"
    />
    <div
      class="relative mx-auto flex w-full max-w-[90rem] flex-col gap-5 sm:flex-row sm:items-end"
    >
      <div class="flex min-w-0 flex-1 flex-col gap-1.5">
        <span
          class="inline-flex items-center gap-2 text-sm font-semibold text-n-blue-6 dark:text-n-blue-11"
        >
          <span class="i-lucide-calendar-days size-4" aria-hidden="true" />
          <span class="first-letter:uppercase">{{
            t(`${N}.ROTULO`, { data })
          }}</span>
        </span>
        <h1
          class="mb-0 text-2xl font-bold leading-tight tracking-tight text-white sm:text-3xl"
        >
          {{ saudacao }}
        </h1>
        <p
          class="mb-0 flex flex-wrap gap-x-1.5 text-base leading-relaxed text-white/80"
        >
          <span>
            {{
              pendentes
                ? t(`${N}.HOJE`, { n: pendentes }, pendentes)
                : t(`${N}.HOJE_NADA`)
            }}
          </span>
          <span
            v-if="atrasados"
            class="font-semibold text-n-ruby-6 dark:text-n-ruby-11"
          >
            {{ t(`${N}.ATRASADOS`, { n: atrasados }, atrasados) }}
          </span>
          <span v-else>{{ t(`${N}.EM_DIA`) }}</span>
        </p>
      </div>
      <button
        type="button"
        data-calendario-novo
        class="inline-flex min-h-12 shrink-0 items-center justify-center gap-2 rounded-xl bg-white px-5 text-base font-semibold text-n-heroi shadow-lg transition hover:bg-n-blue-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white"
        @click="$emit('novo')"
      >
        <span class="i-lucide-plus size-5" aria-hidden="true" />
        {{ t(`${N}.NOVO`) }}
      </button>
    </div>
  </header>
</template>
