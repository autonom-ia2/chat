<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import { fraseDoGatilho, nomeDaEtapa } from '../prototipo/frases';
import { useAutomacoesLivre } from '../prototipo/useAutomacoesLivre';

// #2414 F0 — "Automações desta etapa" (versão protótipo do lugar onde hoje fica
// o CrmStageAutomationsPanel): as do jeito antigo, com "Trazer para o novo", e
// as novas. "+ Automação nesta etapa" abre o editor já com o gatilho da etapa.
const props = defineProps({
  etapaId: { type: String, required: true },
});

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const { automacoes } = useAutomacoesLivre();

const daEtapa = automacao =>
  automacao.etapaAntiga === props.etapaId ||
  automacao.versao?.receita?.gatilho?.etapa === props.etapaId;

const antigas = computed(() =>
  automacoes.value.filter(item => item.jeitoAntigo && daEtapa(item))
);
const novas = computed(() =>
  automacoes.value.filter(item => !item.jeitoAntigo && daEtapa(item))
);

const ir = (name, { params = {}, query = {} } = {}) =>
  router.push({
    name,
    params: { accountId: route.params.accountId, ...params },
    query,
  });

const abrir = automacao =>
  ir('automacoes_livre_editar', { params: { id: automacao.id } });
const trazer = automacao =>
  ir('automacoes_livre_editar', {
    params: { id: automacao.id },
    query: { trazer: '1' },
  });
const nova = () =>
  ir('automacoes_livre_nova', { query: { etapa: props.etapaId } });
const pedirAoGuia = () =>
  ir('automacoes_livre_conte', { query: { etapa: props.etapaId } });
</script>

<template>
  <div data-painel-etapa class="flex flex-col gap-6">
    <p class="mb-0 text-[0.9375rem] text-n-slate-11">
      {{ $t('AUTOMACAO_LIVRE.ETAPA.EXPLICA', { etapa: nomeDaEtapa(etapaId) }) }}
    </p>

    <div class="flex flex-wrap gap-2">
      <Button
        data-nova-na-etapa
        :label="$t('AUTOMACAO_LIVRE.ETAPA.NOVA')"
        icon="i-lucide-plus"
        class="min-h-11"
        @click="nova"
      />
      <Button
        data-pedir-guia
        :label="$t('AUTOMACAO_LIVRE.ETAPA.GUIA')"
        icon="i-lucide-sparkles"
        slate
        faded
        class="min-h-11"
        @click="pedirAoGuia"
      />
    </div>

    <p
      v-if="!antigas.length && !novas.length"
      data-etapa-vazia
      class="mb-0 text-[0.9375rem] text-n-slate-11"
    >
      {{ $t('AUTOMACAO_LIVRE.ETAPA.VAZIA') }}
    </p>

    <ul v-else class="flex flex-col gap-2 p-0 m-0 list-none">
      <li
        v-for="automacao in antigas"
        :key="automacao.id"
        data-etapa-antiga
        class="flex flex-col gap-3 p-4 border rounded-2xl border-n-amber-6 bg-n-amber-2"
      >
        <div class="flex flex-wrap items-center gap-2">
          <span class="text-base font-semibold text-n-slate-12">
            {{ automacao.nome }}
          </span>
          <span
            class="inline-flex items-center gap-1 px-2.5 py-0.5 text-xs font-medium rounded-full bg-n-amber-3 text-n-amber-11"
          >
            <span class="i-lucide-history size-3" aria-hidden="true" />
            {{ $t('AUTOMACAO_LIVRE.ORIGEM.ANTIGO') }}
          </span>
        </div>
        <p class="mb-0 text-sm text-n-slate-11">
          {{ fraseDoGatilho(automacao.versao.receita.gatilho, t) }}
        </p>
        <Button
          data-trazer-da-etapa
          :label="$t('AUTOMACAO_LIVRE.TRAZER')"
          icon="i-lucide-arrow-up-right"
          amber
          class="self-start min-h-11"
          @click="trazer(automacao)"
        />
      </li>
      <li
        v-for="automacao in novas"
        :key="automacao.id"
        data-etapa-nova
        class="flex items-center gap-3 p-4 border rounded-2xl border-n-weak bg-n-solid-1"
      >
        <div class="flex flex-col flex-1 min-w-0 gap-1">
          <span class="text-base font-semibold text-n-slate-12">
            {{ automacao.nome }}
          </span>
          <span class="text-sm text-n-slate-11">
            {{ fraseDoGatilho(automacao.versao.receita.gatilho, t) }}
          </span>
          <span
            class="text-sm font-medium"
            :class="automacao.ativa ? 'text-n-teal-11' : 'text-n-slate-10'"
          >
            {{
              automacao.ativa
                ? $t('AUTOMACAO_LIVRE.LIGADA')
                : $t('AUTOMACAO_LIVRE.DESLIGADA')
            }}
          </span>
        </div>
        <Button
          :label="$t('AUTOMACAO_LIVRE.LISTA.ABRIR')"
          slate
          faded
          size="sm"
          class="min-h-11 shrink-0"
          @click="abrir(automacao)"
        />
      </li>
    </ul>

    <p
      class="flex items-start gap-2 p-3 mb-0 text-sm rounded-xl bg-n-alpha-1 text-n-slate-11"
    >
      <span class="i-lucide-info size-4 mt-0.5 shrink-0" aria-hidden="true" />
      {{ $t('AUTOMACAO_LIVRE.ETAPA.NAO_DISPARA') }}
    </p>
  </div>
</template>
