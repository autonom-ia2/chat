<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { useCanManage } from 'dashboard/composables/useCanManage';
import { automacoesDoCard } from 'dashboard/routes/dashboard/automacoes/livre/gatilhosDemo';

// #2499 (F6) — "Automações deste cartão": o que está rodando para este card,
// com o passo e até quando espera, o histórico em frases e "Parar para este
// cartão" (F6.3), que para só o que roda aqui; as outras seguem.
// Ver pede automation_view e ver o card; parar pede automation_manage e poder
// alterar o card (parecer de Funções). PROTÓTIPO: dados do adaptador falso.
const props = defineProps({
  card: { type: Object, required: true },
  formato: { type: Object, required: true },
});

const { t } = useI18n();
const G = 'AUTOMACAO_LIVRE.GATILHOS_F6.CARD';
const podeParar = useCanManage('automation_manage');

const dados = ref(automacoesDoCard(props.card));
const paradas = ref([]);
const rodando = computed(() =>
  dados.value.rodando.filter(item => !paradas.value.includes(item.execucao_id))
);

const parar = execucao => {
  paradas.value = [...paradas.value, execucao.execucao_id];
};
</script>

<template>
  <div class="flex flex-col gap-6" data-tela="automacoes-do-card">
    <section class="flex flex-col gap-3">
      <h3 class="m-0 text-sm font-semibold text-n-slate-12">
        {{ $t(`${G}.RODANDO`) }}
      </h3>
      <p v-if="!rodando.length" class="m-0 text-sm text-n-slate-11">
        {{ $t(`${G}.NADA_RODANDO`) }}
      </p>
      <article
        v-for="execucao in rodando"
        :key="execucao.execucao_id"
        class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm"
      >
        <div class="flex flex-col gap-0.5">
          <span class="text-sm font-medium text-n-slate-12">{{
            execucao.nome
          }}</span>
          <span class="text-sm text-n-slate-11">
            {{
              $t(`${G}.ESPERANDO`, {
                passo: execucao.passo,
                quando: formato.quando(execucao.ate),
              })
            }}
          </span>
        </div>
        <Button
          v-if="podeParar"
          :label="$t(`${G}.PARAR`)"
          variant="faded"
          color="ruby"
          size="sm"
          icon="i-lucide-octagon-x"
          class="self-start"
          @click="parar(execucao)"
        />
      </article>
      <p v-if="paradas.length" class="m-0 text-sm text-n-teal-11" role="status">
        {{ $t(`${G}.PARADA`) }}
      </p>
    </section>

    <section class="flex flex-col gap-3">
      <h3 class="m-0 text-sm font-semibold text-n-slate-12">
        {{ $t(`${G}.HISTORICO`) }}
      </h3>
      <ol class="m-0 flex list-none flex-col gap-2 p-0">
        <li
          v-for="(item, i) in dados.historico"
          :key="i"
          class="flex items-baseline justify-between gap-3 border-b border-n-weak pb-2 text-sm"
        >
          <span class="text-n-slate-12">{{ t(item.frase, item.args) }}</span>
          <span class="shrink-0 text-xs text-n-slate-11">{{
            formato.ha(item.em)
          }}</span>
        </li>
      </ol>
    </section>
  </div>
</template>
