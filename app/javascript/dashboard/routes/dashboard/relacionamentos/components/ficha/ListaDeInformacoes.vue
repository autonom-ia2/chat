<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import BotaoCopiar from './BotaoCopiar.vue';

// #2894 — a lista "nome: valor" das informações. `linhas` vem de
// ficha/informacoes.js: { chave, valor, rotulo?, copiar? }. Sem `rotulo`, o nome
// vem do catálogo (`<raiz>.<CHAVE>`). O que falta mostra "Não informado" em cinza.
// `redes` são as redes sociais já preenchidas: { rede, usuario }.
// Sem nenhum valor e sem redes, mostra a frase de vazio em vez de uma lista de
// "Não informado".
const props = defineProps({
  linhas: { type: Array, required: true },
  raiz: { type: String, default: 'RELACIONAMENTOS_FICHA.INFORMACOES' },
  redes: { type: Array, default: () => [] },
});

const { t } = useI18n();
const semNada = computed(
  () => !props.redes.length && props.linhas.every(linha => !linha.valor)
);
</script>

<template>
  <p v-if="semNada" data-vazio class="m-0 text-base text-n-slate-11">
    {{ t('RELACIONAMENTOS_FICHA.INFORMACOES.VAZIO') }}
  </p>
  <dl v-else class="grid gap-4 m-0">
    <div
      v-for="linha in linhas"
      :key="linha.chave"
      :data-informacao="linha.chave"
      class="flex items-center justify-between gap-3 min-w-0"
    >
      <div class="min-w-0">
        <dt class="text-sm text-n-slate-11">
          {{ linha.rotulo || t(`${raiz}.${linha.chave.toUpperCase()}`) }}
        </dt>
        <dd
          class="m-0 text-base break-words tabular-nums"
          :class="linha.valor ? 'text-n-slate-12' : 'text-n-slate-10'"
        >
          {{ linha.valor || t('RELACIONAMENTOS.COMUM.NAO_INFORMADO') }}
        </dd>
      </div>
      <BotaoCopiar
        v-if="linha.copiar && linha.valor"
        :valor="linha.valor"
        :item="linha.rotulo || t(`${raiz}.${linha.chave.toUpperCase()}`)"
      />
    </div>
    <div v-for="item in redes" :key="item.rede" :data-informacao="item.rede">
      <dt class="text-sm text-n-slate-11">
        {{ t(`RELACIONAMENTOS_FICHA.GAVETA.REDE.${item.rede}`) }}
      </dt>
      <dd class="m-0 text-base break-words text-n-slate-12">
        {{ item.usuario }}
      </dd>
    </div>
  </dl>
</template>
