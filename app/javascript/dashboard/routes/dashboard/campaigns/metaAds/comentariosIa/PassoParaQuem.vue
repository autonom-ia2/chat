<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { FOR_WHOM_LIMIT, FRASE_DO_DONO_LIMIT } from './useCuidado';

// #2458 (PR 2 do #2436), com a IA escrevendo as respostas: o passo 2 do cuidado. Os chips somam: cada um é um tema, e
// dá para marcar vários. O campo mostra os marcados numa frase ("Quem perguntar o preço ou pedir o link", pelo
// Intl.ListFormat) e o dono pode reescrever: é a frase que a IA lê. "Sobre o que eu não falo?": o comentário sobre esse
// assunto fica com o dono, mesmo que a IA saiba responder. Quem decide se o comentário é o caso é o modelo, nunca uma
// lista de palavras (regra do Rodrigo, 20/09/2026).
const forWhom = defineModel('forWhom', { type: String, required: true });
// Os chips marcados, pela chave estável (price, link, catalog): o texto de cada um vem do idioma de quem abre a tela.
const temas = defineModel('temas', { type: Array, required: true });
const naoFalo = defineModel('naoFalo', { type: String, required: true });

const { t, locale } = useI18n();
const KEY = 'META_ADS_COMMENTS_AI.DONO';
const TEMAS = ['price', 'link', 'catalog'];
const CHIP_ON = 'bg-n-blue-3 text-n-blue-11 ring-1 ring-inset ring-n-blue-8';
const CHIP_OFF = 'bg-n-alpha-2 text-n-slate-12 hover:bg-n-alpha-1';
const FIELD =
  '!mb-0 w-full resize-none rounded-xl bg-n-solid-1 px-3 py-2 text-base leading-6 text-n-slate-12 ring-1 ring-inset ring-n-weak focus:outline-none focus:ring-2 focus:ring-n-brand';

const parte = tema => t(`${KEY}.WHO.PARTS.${tema.toUpperCase()}`);
const frase = lista =>
  lista.length
    ? t(`${KEY}.WHO.CHIP`, {
        parte: new Intl.ListFormat(locale.value.replaceAll('_', '-'), {
          type: 'disjunction',
        }).format(lista),
      })
    : '';
// Os marcados na ordem dos chips, para a frase não mudar com a ordem dos toques.
const marcados = lista => TEMAS.filter(tema => lista.includes(tema)).map(parte);
// A lista nova é calculada aqui: o modelo só muda depois que o pai a repassa.
const marcar = tema => {
  const antes = frase(marcados(temas.value));
  const novos = temas.value.includes(tema)
    ? temas.value.filter(item => item !== tema)
    : [...temas.value, tema];
  temas.value = novos;
  // O campo acompanha os chips enquanto o dono não o reescreveu.
  if (!forWhom.value.trim() || forWhom.value === antes) {
    forWhom.value = frase(marcados(novos));
  }
};

const forWhomTooLong = computed(
  () => forWhom.value.trim().length > FOR_WHOM_LIMIT
);
const naoFaloTooLong = computed(
  () => naoFalo.value.trim().length > FRASE_DO_DONO_LIMIT
);
</script>

<template>
  <div data-ia-dono-para-quem class="flex flex-col gap-5">
    <div class="flex flex-wrap gap-2">
      <button
        v-for="tema in TEMAS"
        :key="tema"
        type="button"
        data-ia-dono-suggestion
        :aria-pressed="temas.includes(tema)"
        class="inline-flex min-h-11 items-center gap-1.5 rounded-full border-0 px-4 text-sm font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        :class="temas.includes(tema) ? CHIP_ON : CHIP_OFF"
        @click="marcar(tema)"
      >
        <span
          v-if="temas.includes(tema)"
          class="i-lucide-check size-4"
          aria-hidden="true"
        />
        {{ $t(`${KEY}.WHO.CHIP`, { parte: parte(tema) }) }}
      </button>
    </div>
    <label
      for="ia-dono-who"
      class="flex flex-col gap-2 text-sm font-medium text-n-slate-11"
    >
      {{ $t(`${KEY}.WHO.OWN`) }}
      <textarea
        id="ia-dono-who"
        v-model="forWhom"
        data-ia-dono-who
        rows="2"
        :aria-invalid="forWhomTooLong"
        :placeholder="$t(`${KEY}.WHO.PLACEHOLDER`)"
        :class="FIELD"
        class="min-h-[4.5rem] font-normal"
      />
    </label>
    <p
      v-if="forWhomTooLong"
      role="alert"
      data-ia-dono-who-too-long
      class="m-0 -mt-3 text-sm font-medium text-n-ruby-11"
    >
      {{ $t(`${KEY}.WHO.TOO_LONG`, { max: FOR_WHOM_LIMIT }) }}
    </p>
    <label
      for="ia-dono-nao-falo"
      class="flex flex-col gap-2 text-sm font-medium text-n-slate-11"
    >
      <span class="text-base font-semibold text-n-slate-12">
        {{ $t(`${KEY}.NAO_FALO.TITLE`) }}
        <span class="text-sm font-normal text-n-slate-11">
          {{ $t(`${KEY}.NAO_FALO.OPTIONAL`) }}
        </span>
      </span>
      {{ $t(`${KEY}.NAO_FALO.TEXT`) }}
      <input
        id="ia-dono-nao-falo"
        v-model="naoFalo"
        data-ia-dono-nao-falo
        type="text"
        :aria-invalid="naoFaloTooLong"
        :placeholder="$t(`${KEY}.NAO_FALO.PLACEHOLDER`)"
        :class="FIELD"
        class="min-h-11 font-normal"
      />
    </label>
    <p
      v-if="naoFaloTooLong"
      role="alert"
      data-ia-dono-nao-falo-too-long
      class="m-0 -mt-3 text-sm font-medium text-n-ruby-11"
    >
      {{ $t(`${KEY}.WHO.TOO_LONG`, { max: FRASE_DO_DONO_LIMIT }) }}
    </p>
  </div>
</template>
