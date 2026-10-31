<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import LivreHistorico from './LivreHistorico.vue';
import { quando } from '../prototipo/frases';
import { useAutomacoesLivre } from '../prototipo/useAutomacoesLivre';

// #2414 F0 — "Automações deste cartão": o que está em andamento (com até quando
// espera), as últimas linhas do que aconteceu e "Parar para este cartão".
const props = defineProps({
  cartaoId: { type: Number, required: true },
});

const { t, locale } = useI18n();
const { execucoesDoCartao, registrosDe, pararParaCartao } =
  useAutomacoesLivre();

const execucoes = computed(() => execucoesDoCartao(props.cartaoId));
const linhas = computed(() =>
  registrosDe({ cartaoId: props.cartaoId }).slice(0, 6)
);

const estado = execucao =>
  t(`AUTOMACAO_LIVRE.CARTAO.ESTADO_${execucao.estado.toUpperCase()}`, {
    ate: quando(execucao.ate, locale?.value),
  });

const parar = execucao => {
  pararParaCartao(execucao.id);
  useAlert(t('AUTOMACAO_LIVRE.CARTAO.PAROU'));
};
</script>

<template>
  <div data-painel-cartao class="flex flex-col gap-5">
    <section
      class="flex flex-col gap-4 p-4 border shadow-sm rounded-2xl border-n-weak bg-n-solid-1 sm:p-5"
    >
      <div class="flex items-center gap-3">
        <span
          class="grid rounded-xl place-items-center size-12 shrink-0 bg-n-iris-3 text-n-iris-11"
        >
          <span class="i-lucide-zap size-6" aria-hidden="true" />
        </span>
        <h4 class="mb-0 text-base font-semibold text-n-slate-12">
          {{ $t('AUTOMACAO_LIVRE.CARTAO.TITULO') }}
        </h4>
      </div>
      <p
        v-if="!execucoes.length"
        data-cartao-sem-execucao
        class="mb-0 text-[0.9375rem] text-n-slate-11"
      >
        {{ $t('AUTOMACAO_LIVRE.CARTAO.NADA') }}
      </p>
      <ul v-else class="flex flex-col gap-2 p-0 m-0 list-none">
        <li
          v-for="execucao in execucoes"
          :key="execucao.id"
          data-execucao
          class="flex flex-col gap-3 p-4 border rounded-2xl border-n-weak bg-n-solid-1"
        >
          <div class="flex items-start gap-3">
            <span
              class="grid rounded-full place-items-center size-8 shrink-0 bg-n-blue-3 text-n-blue-11"
            >
              <span class="i-lucide-clock size-4" aria-hidden="true" />
            </span>
            <div class="flex flex-col min-w-0 gap-0.5">
              <span class="text-[0.9375rem] font-semibold text-n-slate-12">
                {{ execucao.automacao?.nome }}
              </span>
              <span class="text-sm text-n-blue-11">{{ estado(execucao) }}</span>
            </div>
          </div>
          <Button
            data-parar-cartao
            :label="$t('AUTOMACAO_LIVRE.CARTAO.PARAR')"
            icon="i-lucide-octagon-x"
            ruby
            faded
            size="sm"
            class="self-start min-h-11"
            @click="parar(execucao)"
          />
        </li>
      </ul>
    </section>

    <section
      class="flex flex-col gap-3 p-4 border shadow-sm rounded-2xl border-n-weak bg-n-solid-1 sm:p-5"
    >
      <h4 class="mb-0 text-base font-semibold text-n-slate-12">
        {{ $t('AUTOMACAO_LIVRE.CARTAO.ULTIMAS') }}
      </h4>
      <LivreHistorico :registros="linhas" sem-alvo />
    </section>
  </div>
</template>
