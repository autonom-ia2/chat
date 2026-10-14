<script setup>
import { computed, ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';

// #1423 — escolher dia (e hora) no padrão da casa, sem o campo nativo do
// navegador (OB-01): atalhos prontos, um calendário do mês e a hora numa
// lista de escolha. O valor é texto local: "2026-10-14T10:00" com hora,
// "2026-10-14" sem hora (os mesmos formatos que a gaveta antiga enviava).
const props = defineProps({
  rotulo: { type: String, required: true },
  comHora: { type: Boolean, default: true },
  atalhos: { type: Array, default: () => [] },
  limpar: { type: Boolean, default: false },
  desligado: { type: Boolean, default: false },
});
const valor = defineModel({ type: String, default: '' });

const { t, locale } = useI18n();
const id = useId();
const idioma = computed(() => locale.value.replace('_', '-'));
const dois = numero => String(numero).padStart(2, '0');
const textoDoDia = data =>
  `${data.getFullYear()}-${dois(data.getMonth() + 1)}-${dois(data.getDate())}`;
const lerDia = texto => {
  const [ano, mes, dia] = (texto || '').slice(0, 10).split('-').map(Number);
  return ano ? new Date(ano, mes - 1, dia) : null;
};

const dia = computed(() => lerDia(valor.value));
const hora = computed(() =>
  props.comHora && valor.value.includes('T') ? valor.value.slice(11, 16) : ''
);
const montar = (data, horario) => {
  if (!data) return '';
  return props.comHora
    ? `${textoDoDia(data)}T${horario || '09:00'}`
    : textoDoDia(data);
};

// Mês à vista no calendário.
const mes = ref(new Date());
watch(
  dia,
  escolhido => {
    if (escolhido)
      mes.value = new Date(escolhido.getFullYear(), escolhido.getMonth(), 1);
  },
  { immediate: true }
);
const calendarioAberto = ref(false);
const hoje = textoDoDia(new Date());
const nomeDoMes = computed(() => {
  const texto = new Intl.DateTimeFormat(idioma.value, {
    month: 'long',
    year: 'numeric',
  }).format(mes.value);
  return texto.charAt(0).toLocaleUpperCase(idioma.value) + texto.slice(1);
});
// Cabeçalho de domingo a sábado, tirado de uma semana conhecida (4/1/1970
// foi domingo), no idioma da pessoa.
const semana = computed(() =>
  Array.from({ length: 7 }, (_, indice) =>
    new Intl.DateTimeFormat(idioma.value, { weekday: 'narrow' }).format(
      new Date(1970, 0, 4 + indice)
    )
  )
);
const nomeLongo = data =>
  new Intl.DateTimeFormat(idioma.value, { dateStyle: 'full' }).format(data);
const dias = computed(() => {
  const primeiro = new Date(mes.value.getFullYear(), mes.value.getMonth(), 1);
  const total = new Date(
    mes.value.getFullYear(),
    mes.value.getMonth() + 1,
    0
  ).getDate();
  const vazios = Array.from({ length: primeiro.getDay() }, (_, indice) => ({
    chave: `v${indice}`,
  }));
  const cheios = Array.from({ length: total }, (_, indice) => {
    const data = new Date(
      primeiro.getFullYear(),
      primeiro.getMonth(),
      indice + 1
    );
    const texto = textoDoDia(data);
    return {
      chave: texto,
      numero: indice + 1,
      data,
      hoje: texto === hoje,
      escolhido: dia.value && texto === textoDoDia(dia.value),
      passado: texto < hoje,
    };
  });
  return [...vazios, ...cheios];
});
const andarMes = passo => {
  mes.value = new Date(
    mes.value.getFullYear(),
    mes.value.getMonth() + passo,
    1
  );
};
const escolherDia = data => {
  valor.value = montar(data, hora.value);
};

const horas = computed(() =>
  Array.from({ length: 48 }, (_, indice) => {
    const texto = `${dois(Math.floor(indice / 2))}:${indice % 2 ? '30' : '00'}`;
    return { value: texto, label: texto };
  })
);
const escolherHora = horario => {
  valor.value = montar(dia.value || new Date(), horario);
};

const resumo = computed(() => {
  if (!dia.value) return t('CRM_CARD.QUANDO.NADA');
  const data = new Intl.DateTimeFormat(idioma.value, {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
  }).format(dia.value);
  return hora.value
    ? t('CRM_CARD.QUANDO.ESCOLHIDO_HORA', { dia: data, hora: hora.value })
    : t('CRM_CARD.QUANDO.ESCOLHIDO', { dia: data });
});
</script>

<template>
  <fieldset
    class="m-0 flex min-w-0 flex-col gap-3 border-0 p-0"
    :disabled="desligado"
    :aria-describedby="`${id}-resumo`"
  >
    <legend class="mb-1 p-0 text-sm font-medium text-n-slate-12">
      {{ rotulo }}
    </legend>
    <div v-if="atalhos.length || limpar" class="flex flex-wrap gap-2">
      <button
        v-for="atalho in atalhos"
        :key="atalho.rotulo"
        type="button"
        :aria-pressed="valor === atalho.valor"
        class="min-h-11 rounded-xl px-3 ring-1 ring-inset text-sm font-medium transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
        :class="
          valor === atalho.valor
            ? 'ring-n-blue-8 bg-n-blue-2 text-n-blue-11'
            : 'ring-n-weak bg-n-solid-1 text-n-slate-12 hover:ring-n-slate-7'
        "
        @click="valor = atalho.valor"
      >
        {{ atalho.rotulo }}
      </button>
      <button
        type="button"
        :aria-expanded="calendarioAberto"
        :aria-controls="`${id}-calendario`"
        class="inline-flex min-h-11 items-center gap-2 rounded-xl bg-n-solid-1 px-3 ring-1 ring-inset ring-n-weak text-sm font-medium text-n-slate-12 hover:ring-n-slate-7 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
        @click="calendarioAberto = !calendarioAberto"
      >
        <span class="i-lucide-calendar size-4" aria-hidden="true" />
        {{ t('CRM_CARD.QUANDO.OUTRO_DIA') }}
      </button>
      <button
        v-if="limpar && valor"
        type="button"
        class="min-h-11 rounded-xl px-3 text-sm font-medium text-n-slate-11 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
        @click="valor = ''"
      >
        {{ t('CRM_CARD.QUANDO.LIMPAR') }}
      </button>
    </div>

    <div
      v-show="calendarioAberto || !atalhos.length"
      :id="`${id}-calendario`"
      data-campo-calendario
      class="w-full max-w-[22rem] rounded-2xl border border-n-weak bg-n-solid-1 p-3"
    >
      <div class="mb-2 flex items-center justify-between gap-2">
        <button
          type="button"
          class="grid size-11 place-items-center rounded-xl text-n-slate-12 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
          :aria-label="t('CRM_CARD.QUANDO.MES_ANTERIOR')"
          @click="andarMes(-1)"
        >
          <span
            class="i-lucide-chevron-left size-5 rtl:rotate-180"
            aria-hidden="true"
          />
        </button>
        <span class="text-sm font-semibold text-n-slate-12" aria-live="polite">
          {{ nomeDoMes }}
        </span>
        <button
          type="button"
          class="grid size-11 place-items-center rounded-xl text-n-slate-12 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
          :aria-label="t('CRM_CARD.QUANDO.PROXIMO_MES')"
          @click="andarMes(1)"
        >
          <span
            class="i-lucide-chevron-right size-5 rtl:rotate-180"
            aria-hidden="true"
          />
        </button>
      </div>
      <div class="grid grid-cols-7 gap-0.5 text-center" aria-hidden="true">
        <span
          v-for="(letra, indice) in semana"
          :key="indice"
          class="py-1 text-xs font-semibold text-n-slate-11"
        >
          {{ letra }}
        </span>
      </div>
      <div class="grid grid-cols-7 gap-0.5">
        <template v-for="item in dias" :key="item.chave">
          <span v-if="!item.data" aria-hidden="true" />
          <button
            v-else
            type="button"
            :aria-label="nomeLongo(item.data)"
            :aria-pressed="Boolean(item.escolhido)"
            class="grid aspect-square min-h-11 place-items-center rounded-xl text-sm transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
            :class="[
              item.escolhido
                ? 'bg-n-blue-9 font-semibold text-white'
                : 'hover:bg-n-alpha-2',
              !item.escolhido && item.hoje
                ? 'font-bold text-n-blue-11 ring-1 ring-inset ring-n-blue-8'
                : '',
              !item.escolhido && !item.hoje && item.passado
                ? 'text-n-slate-10'
                : '',
              !item.escolhido && !item.hoje && !item.passado
                ? 'text-n-slate-12'
                : '',
            ]"
            @click="escolherDia(item.data)"
          >
            {{ item.numero }}
          </button>
        </template>
      </div>
    </div>

    <label v-if="comHora" class="flex max-w-[22rem] flex-col gap-1">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('CRM_CARD.QUANDO.HORA') }}
      </span>
      <ChoiceSelect
        :model-value="hora"
        :options="horas"
        :placeholder="t('CRM_CARD.QUANDO.ESCOLHA_HORA')"
        :aria-label="t('CRM_CARD.QUANDO.HORA')"
        :disabled="desligado"
        class="w-full"
        @update:model-value="escolherHora"
      />
    </label>
    <p
      :id="`${id}-resumo`"
      class="mb-0 text-sm text-n-slate-11"
      aria-live="polite"
    >
      {{ resumo }}
    </p>
  </fieldset>
</template>
