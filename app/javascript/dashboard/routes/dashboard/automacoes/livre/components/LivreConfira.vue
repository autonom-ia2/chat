<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import LivrePassos from './LivrePassos.vue';
import { fraseDaCondicao, fraseDoGatilho } from '../frases';
import { RAIZ } from '../receita';

// #2414 F5 — o editor "Confira": a automação de cima para baixo, numa lista só.
// Quando (o gatilho) → Só se (os filtros do gatilho) → Faça (os passos). Cada
// item tem "Alterar".
defineProps({
  receita: { type: Object, required: true },
  catalogo: { type: Object, required: true },
  podeMudar: { type: Boolean, default: false },
  tudo: { type: Boolean, default: false },
});

const emit = defineEmits(['alterar', 'inserir']);

const { t } = useI18n();

const BLOCOS = {
  QUANDO: { icone: 'i-lucide-zap', tom: 'bg-n-blue-3 text-n-blue-11' },
  SO_SE: {
    icone: 'i-lucide-list-filter',
    tom: 'bg-n-violet-3 text-n-violet-11',
  },
  FACA: { icone: 'i-lucide-play', tom: 'bg-n-teal-3 text-n-teal-11' },
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
            {{ fraseDoGatilho(receita.gatilho, catalogo, t) }}
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
            @click="emit('alterar', 'gatilho')"
          />
        </div>
      </div>
    </section>

    <section v-if="receita.gatilho" class="flex gap-4" data-bloco="SO_SE">
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
          v-if="!receita.gatilho.filtros?.length"
          class="mb-0 text-[0.9375rem] text-n-slate-11"
        >
          {{ $t('AUTOMACAO_LIVRE.CONFIRA.SEM_CONDICAO') }}
        </p>
        <div
          v-for="(condicao, indice) in receita.gatilho.filtros || []"
          :key="indice"
          data-filtro
          class="flex items-center gap-3 p-4 border rounded-2xl border-n-weak bg-n-solid-1"
        >
          <p class="flex-1 mb-0 text-base text-n-slate-12">
            {{ fraseDaCondicao(condicao, catalogo, t) }}
          </p>
          <Button
            v-if="podeMudar"
            :label="$t('AUTOMACAO_LIVRE.ALTERAR')"
            slate
            faded
            size="sm"
            class="min-h-11 shrink-0"
            @click="emit('alterar', `condicao@${indice}`)"
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
          @click="emit('alterar', 'condicao@novo')"
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
          :catalogo="catalogo"
          :pode-mudar="podeMudar"
          :tudo="tudo"
          @alterar="id => emit('alterar', id)"
          @inserir="posicao => emit('inserir', posicao)"
        />
      </div>
    </section>
  </div>
</template>
