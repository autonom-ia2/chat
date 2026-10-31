<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import LivrePassos from './LivrePassos.vue';
import {
  fraseDaCondicao,
  fraseDaMeta,
  fraseDoGatilho,
  frasesDoFreio,
} from '../prototipo/frases';
import { RAIZ } from '../prototipo/receita';

// #2414 F0 — o editor "Confira": a automação de cima para baixo, numa lista só.
// Quando (um gatilho) → Só se (condições) → Faça (passos) → Para quando… (meta
// de saída) → Freio. Cada item tem "Alterar".
const props = defineProps({
  receita: { type: Object, required: true },
  podeMudar: { type: Boolean, default: false },
  tudo: { type: Boolean, default: false },
});

const emit = defineEmits(['alterar', 'inserir', 'adicionarCondicao']);

const { t } = useI18n();

const freio = computed(() => frasesDoFreio(props.receita.freio, t));
const freioVisivel = computed(() =>
  props.tudo ? freio.value : freio.value.slice(0, 1)
);
const freioEscondido = computed(
  () => freio.value.length - freioVisivel.value.length
);

const BLOCOS = {
  QUANDO: { icone: 'i-lucide-zap', tom: 'bg-n-blue-3 text-n-blue-11' },
  SO_SE: {
    icone: 'i-lucide-list-filter',
    tom: 'bg-n-violet-3 text-n-violet-11',
  },
  FACA: { icone: 'i-lucide-play', tom: 'bg-n-teal-3 text-n-teal-11' },
  META: { icone: 'i-lucide-flag', tom: 'bg-n-amber-3 text-n-amber-11' },
  FREIO: {
    icone: 'i-lucide-shield-check',
    tom: 'bg-n-slate-3 text-n-slate-11',
  },
};
</script>

<template>
  <div data-confira class="flex flex-col gap-6">
    <section class="flex gap-4" data-bloco="QUANDO">
      <span
        class="grid rounded-2xl place-items-center size-11 shrink-0"
        :class="BLOCOS.QUANDO.tom"
      >
        <span class="size-5" :class="BLOCOS.QUANDO.icone" aria-hidden="true" />
      </span>
      <div class="flex flex-col flex-1 min-w-0 gap-2">
        <h3 class="mb-0 text-sm font-semibold text-n-slate-11">
          {{ $t('AUTOMACAO_LIVRE.CONFIRA.QUANDO') }}
        </h3>
        <div
          class="flex items-center gap-3 p-4 border rounded-2xl bg-n-solid-1"
          :class="
            receita.gatilho ? 'border-n-weak' : 'border-dashed border-n-blue-7'
          "
        >
          <p data-gatilho class="flex-1 mb-0 text-base text-n-slate-12">
            {{ fraseDoGatilho(receita.gatilho, t) }}
          </p>
          <Button
            v-if="podeMudar"
            data-alterar-gatilho
            :label="
              receita.gatilho
                ? $t('AUTOMACAO_LIVRE.ALTERAR')
                : $t('AUTOMACAO_LIVRE.CONFIRA.ESCOLHER')
            "
            slate
            faded
            size="sm"
            class="min-h-11 shrink-0"
            @click="emit('alterar', { tipo: 'gatilho' })"
          />
        </div>
      </div>
    </section>

    <section class="flex gap-4" data-bloco="SO_SE">
      <span
        class="grid rounded-2xl place-items-center size-11 shrink-0"
        :class="BLOCOS.SO_SE.tom"
      >
        <span class="size-5" :class="BLOCOS.SO_SE.icone" aria-hidden="true" />
      </span>
      <div class="flex flex-col flex-1 min-w-0 gap-2">
        <h3 class="mb-0 text-sm font-semibold text-n-slate-11">
          {{ $t('AUTOMACAO_LIVRE.CONFIRA.SO_SE') }}
        </h3>
        <p
          v-if="!receita.condicoes.length"
          class="mb-0 text-[0.9375rem] text-n-slate-11"
        >
          {{ $t('AUTOMACAO_LIVRE.CONFIRA.SEM_CONDICAO') }}
        </p>
        <div
          v-for="(condicao, indice) in receita.condicoes"
          :key="indice"
          class="flex items-center gap-3 p-4 border rounded-2xl border-n-weak bg-n-solid-1"
        >
          <p class="flex-1 mb-0 text-base text-n-slate-12">
            {{ fraseDaCondicao(condicao, t) }}
          </p>
          <Button
            v-if="podeMudar"
            :label="$t('AUTOMACAO_LIVRE.ALTERAR')"
            slate
            faded
            size="sm"
            class="min-h-11 shrink-0"
            @click="emit('alterar', { tipo: 'condicao', indice })"
          />
        </div>
        <Button
          v-if="podeMudar"
          data-adicionar-condicao
          :label="$t('AUTOMACAO_LIVRE.CONFIRA.ADICIONAR_CONDICAO')"
          icon="i-lucide-plus"
          link
          slate
          class="self-start min-h-11"
          @click="emit('adicionarCondicao')"
        />
      </div>
    </section>

    <section class="flex gap-4" data-bloco="FACA">
      <span
        class="grid rounded-2xl place-items-center size-11 shrink-0"
        :class="BLOCOS.FACA.tom"
      >
        <span class="size-5" :class="BLOCOS.FACA.icone" aria-hidden="true" />
      </span>
      <div class="flex flex-col flex-1 min-w-0 gap-2">
        <h3 class="mb-0 text-sm font-semibold text-n-slate-11">
          {{ $t('AUTOMACAO_LIVRE.CONFIRA.FACA') }}
        </h3>
        <LivrePassos
          :passos="receita.passos"
          :lista-id="RAIZ"
          :pode-mudar="podeMudar"
          :tudo="tudo"
          @alterar="id => emit('alterar', { tipo: 'passo', id })"
          @inserir="posicao => emit('inserir', posicao)"
        />
      </div>
    </section>

    <section class="flex gap-4" data-bloco="META">
      <span
        class="grid rounded-2xl place-items-center size-11 shrink-0"
        :class="BLOCOS.META.tom"
      >
        <span class="size-5" :class="BLOCOS.META.icone" aria-hidden="true" />
      </span>
      <div class="flex flex-col flex-1 min-w-0 gap-2">
        <h3 class="mb-0 text-sm font-semibold text-n-slate-11">
          {{ $t('AUTOMACAO_LIVRE.CONFIRA.META') }}
        </h3>
        <div
          class="flex items-center gap-3 p-4 border rounded-2xl border-n-weak bg-n-solid-1"
        >
          <p class="flex-1 mb-0 text-base text-n-slate-12">
            {{ fraseDaMeta(receita.meta, t) }}
          </p>
          <Button
            v-if="podeMudar"
            :label="$t('AUTOMACAO_LIVRE.ALTERAR')"
            slate
            faded
            size="sm"
            class="min-h-11 shrink-0"
            @click="emit('alterar', { tipo: 'meta' })"
          />
        </div>
      </div>
    </section>

    <section class="flex gap-4" data-bloco="FREIO">
      <span
        class="grid rounded-2xl place-items-center size-11 shrink-0"
        :class="BLOCOS.FREIO.tom"
      >
        <span class="size-5" :class="BLOCOS.FREIO.icone" aria-hidden="true" />
      </span>
      <div class="flex flex-col flex-1 min-w-0 gap-2">
        <h3 class="mb-0 text-sm font-semibold text-n-slate-11">
          {{ $t('AUTOMACAO_LIVRE.CONFIRA.FREIO') }}
        </h3>
        <div
          class="flex items-center gap-3 p-4 border rounded-2xl border-n-weak bg-n-solid-1"
        >
          <ul class="flex flex-col flex-1 gap-1 p-0 m-0 list-none">
            <li
              v-for="linha in freioVisivel"
              :key="linha"
              class="text-base text-n-slate-12"
            >
              {{ linha }}
            </li>
            <li v-if="freioEscondido" class="text-sm text-n-slate-10">
              {{
                $t(
                  'AUTOMACAO_LIVRE.CONFIRA.FREIO_MAIS',
                  { n: freioEscondido },
                  freioEscondido
                )
              }}
            </li>
          </ul>
          <Button
            v-if="podeMudar"
            :label="$t('AUTOMACAO_LIVRE.ALTERAR')"
            slate
            faded
            size="sm"
            class="min-h-11 shrink-0"
            @click="emit('alterar', { tipo: 'freio' })"
          />
        </div>
      </div>
    </section>
  </div>
</template>
