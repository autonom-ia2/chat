<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import LivreDuracao from '../components/LivreDuracao.vue';
import { INTERVALOS, P, faixasProntas } from './passosNovos';

// #2936 — Pesquisa de satisfação: a pergunta (já vem pronta), as três faixas da
// nota, de quanto em quanto tempo a mesma pessoa pode ser perguntada de novo e
// quanto esperar a resposta. A prévia mostra a pergunta com os botões de 0 a
// 10. Resposta escrita ("nota 8, mas demorou") a IA entende.
const props = defineProps({
  modelValue: { type: Object, required: true },
  catalogo: { type: Object, required: true },
});

const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const Q = `${P}.PESQUISA`;
const NOTAS = Array.from({ length: 11 }, (_, nota) => nota);

const mudar = mudanca =>
  emit('update:modelValue', { ...props.modelValue, ...mudanca });

const opcoesDeNota = (de, ate) =>
  NOTAS.filter(nota => nota >= de && nota <= ate).map(nota => ({
    value: nota,
    label: String(nota),
  }));
const ateBaixa = computed(() => opcoesDeNota(0, 8));
const desdeAlta = computed(() => opcoesDeNota(2, 10));
const intervalos = computed(() =>
  INTERVALOS.map(dias => ({
    value: dias,
    label: t(`${Q}.DIAS`, { n: dias }),
  }))
);
const faixasOk = computed(() => faixasProntas(props.modelValue));
const media = computed(() => ({
  de: props.modelValue.baixa_ate + 1,
  ate: props.modelValue.alta_desde - 1,
}));
const TOM = {
  baixa: 'bg-n-ruby-3 text-n-ruby-12',
  media: 'bg-n-amber-3 text-n-amber-12',
  alta: 'bg-n-teal-3 text-n-teal-12',
};
</script>

<template>
  <div class="flex flex-col gap-5" data-passo-novo="pesquisa_nota">
    <TextArea
      data-pesquisa-pergunta
      :model-value="modelValue.pergunta || ''"
      :label="$t(`${Q}.PERGUNTA`)"
      :max-length="300"
      @update:model-value="pergunta => mudar({ pergunta })"
    />

    <figure
      data-pesquisa-previa
      class="flex flex-col gap-2 p-4 m-0 rounded-2xl bg-n-alpha-2"
    >
      <figcaption class="text-sm font-medium text-n-slate-11">
        {{ $t(`${Q}.COMO_O_CLIENTE_VE`) }}
      </figcaption>
      <div
        class="flex flex-col self-start w-full max-w-sm gap-3 p-3 shadow-sm rounded-2xl rounded-ss-sm bg-n-teal-3"
      >
        <p class="mb-0 text-[0.9375rem] text-n-slate-12 whitespace-pre-line">
          {{ modelValue.pergunta }}
        </p>
        <ol
          class="grid grid-cols-6 gap-1.5 p-0 m-0 list-none"
          :aria-label="$t(`${Q}.BOTOES`)"
        >
          <li
            v-for="nota in NOTAS"
            :key="nota"
            class="grid font-semibold rounded-lg place-items-center min-h-11 bg-n-solid-1 text-n-slate-12"
          >
            {{ nota }}
          </li>
        </ol>
      </div>
    </figure>

    <fieldset class="flex flex-col gap-3" data-pesquisa-faixas>
      <legend class="mb-1.5 text-sm font-medium text-n-slate-12">
        {{ $t(`${Q}.FAIXAS`) }}
      </legend>
      <div
        class="flex flex-wrap items-center gap-3 px-4 py-2 rounded-xl min-h-11"
        :class="TOM.baixa"
      >
        <span class="flex-1 text-[0.9375rem] font-medium">
          {{ $t(`${Q}.BAIXA`) }}
        </span>
        <span class="text-sm">{{ $t(`${Q}.DE_ZERO_ATE`) }}</span>
        <ChoiceSelect
          data-pesquisa-baixa
          :model-value="modelValue.baixa_ate"
          :aria-label="$t(`${Q}.BAIXA_ATE`)"
          :options="ateBaixa"
          compact
          @update:model-value="nota => mudar({ baixa_ate: nota })"
        />
      </div>
      <div
        class="flex flex-wrap items-center gap-3 px-4 py-2 rounded-xl min-h-11"
        :class="TOM.media"
      >
        <span class="flex-1 text-[0.9375rem] font-medium">
          {{ $t(`${Q}.MEDIA`) }}
        </span>
        <span v-if="faixasOk" class="text-sm" data-pesquisa-media>
          {{ $t(`${Q}.DE_ATE`, media) }}
        </span>
      </div>
      <div
        class="flex flex-wrap items-center gap-3 px-4 py-2 rounded-xl min-h-11"
        :class="TOM.alta"
      >
        <span class="flex-1 text-[0.9375rem] font-medium">
          {{ $t(`${Q}.ALTA`) }}
        </span>
        <span class="text-sm">{{ $t(`${Q}.DE`) }}</span>
        <ChoiceSelect
          data-pesquisa-alta
          :model-value="modelValue.alta_desde"
          :aria-label="$t(`${Q}.ALTA_DESDE`)"
          :options="desdeAlta"
          compact
          @update:model-value="nota => mudar({ alta_desde: nota })"
        />
        <span class="text-sm">{{ $t(`${Q}.ATE_DEZ`) }}</span>
      </div>
      <p
        v-if="!faixasOk"
        data-pesquisa-faixas-ruins
        role="alert"
        class="mb-0 text-sm text-n-ruby-11"
      >
        {{ $t(`${Q}.FAIXAS_RUINS`) }}
      </p>
    </fieldset>

    <div class="flex flex-col gap-1.5">
      <span class="text-sm font-medium text-n-slate-12">
        {{ $t(`${Q}.INTERVALO`) }}
      </span>
      <ChoiceSelect
        data-pesquisa-intervalo
        :model-value="modelValue.intervalo_dias"
        :aria-label="$t(`${Q}.INTERVALO`)"
        :options="intervalos"
        @update:model-value="dias => mudar({ intervalo_dias: dias })"
      />
    </div>

    <LivreDuracao
      :rotulo="$t(`${Q}.ESPERA`)"
      :model-value="modelValue.espera"
      :unidades="catalogo.unidades"
      @update:model-value="espera => mudar({ espera })"
    />

    <p
      data-pesquisa-resumo
      class="px-4 py-3 mb-0 text-sm rounded-xl bg-n-alpha-2 text-n-slate-12"
    >
      {{ $t(`${Q}.RESUMO_EXEMPLO`) }}
    </p>
    <p class="mb-0 text-sm text-n-slate-11">{{ $t(`${Q}.REGRAS`) }}</p>
  </div>
</template>
