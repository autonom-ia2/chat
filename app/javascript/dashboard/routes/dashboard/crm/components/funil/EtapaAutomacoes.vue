<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import { useCanManage } from 'dashboard/composables/useCanManage';
import { useMapGetter } from 'dashboard/composables/store';
import { frontendURL } from 'dashboard/helper/URLHelper';
import {
  automacoesDaEtapa,
  gatilhoDe,
} from 'dashboard/routes/dashboard/automacoes/livre/gatilhosDemo';

// #2499 (F6) — "Automações desta etapa", em Editar funil › etapa: as automações
// novas que começam nesta etapa, com o que não dispara. As antigas continuam
// logo abaixo, no painel de sempre, com o selo "jeito antigo" (F6.5).
// PROTÓTIPO: a lista vem do adaptador falso (gatilhosDemo).
const props = defineProps({
  stage: { type: Object, required: true },
});

const { t } = useI18n();
const router = useRouter();
const accountId = useMapGetter('getCurrentAccountId');
const podeMontar = useCanManage('automation_manage');
const G = 'AUTOMACAO_LIVRE.GATILHOS_F6.ETAPA';

const lista = computed(() => automacoesDaEtapa(props.stage).novas);

const fraseDoGatilho = gatilho => {
  const entrada = gatilhoDe(gatilho.tipo);
  const base = entrada ? t(entrada.frase) : gatilho.tipo;
  return gatilho.dias ? t(`${G}.HA_DIAS`, { base, dias: gatilho.dias }) : base;
};

const abrir = automacao =>
  router.push(
    frontendURL(`accounts/${accountId.value}/automacoes/livre/${automacao.id}`)
  );
const nova = () =>
  router.push(frontendURL(`accounts/${accountId.value}/automacoes/livre/nova`));
</script>

<template>
  <section class="flex flex-col gap-3" data-tela="automacoes-da-etapa">
    <header class="flex items-center justify-between gap-3">
      <div class="flex flex-col gap-0.5">
        <h3 class="m-0 text-base font-medium text-n-slate-12">
          {{ $t(`${G}.TITULO`) }}
        </h3>
        <p class="m-0 text-sm text-n-slate-11">
          {{ $t(`${G}.SUBTITULO`, { etapa: stage.name }) }}
        </p>
      </div>
      <Button
        v-if="podeMontar"
        :label="$t(`${G}.NOVA`)"
        icon="i-lucide-plus"
        size="sm"
        @click="nova"
      />
    </header>

    <ul class="m-0 flex list-none flex-col gap-2 p-0">
      <li
        v-for="automacao in lista"
        :key="automacao.id"
        class="flex items-center justify-between gap-3 rounded-xl border border-n-weak bg-n-solid-1 px-4 py-3"
      >
        <button
          type="button"
          class="flex min-h-11 flex-1 flex-col items-start gap-0.5 text-left"
          @click="abrir(automacao)"
        >
          <span class="text-sm font-medium text-n-slate-12">{{
            automacao.nome
          }}</span>
          <span class="text-xs text-n-slate-11">{{
            fraseDoGatilho(automacao.gatilho)
          }}</span>
        </button>
        <span
          class="shrink-0 rounded-full px-2 py-0.5 text-xs"
          :class="
            automacao.ligada
              ? 'bg-n-teal-3 text-n-teal-11'
              : 'bg-n-alpha-2 text-n-slate-11'
          "
        >
          {{
            automacao.ligada
              ? $t(`${G}.LIGADA`, { cards: automacao.rodando })
              : $t(`${G}.DESLIGADA`)
          }}
        </span>
      </li>
    </ul>

    <p class="m-0 rounded-lg bg-n-alpha-2 px-3 py-2 text-xs text-n-slate-11">
      {{ $t(`${G}.NAO_DISPARA`) }}
    </p>

    <h4
      class="m-0 mt-2 flex items-center gap-2 text-sm font-medium text-n-slate-12"
    >
      {{ $t(`${G}.ANTIGAS`) }}
      <span
        class="rounded-full bg-n-amber-3 px-2 py-0.5 text-xs text-n-amber-11"
      >
        {{ $t(`${G}.JEITO_ANTIGO`) }}
      </span>
    </h4>
  </section>
</template>
