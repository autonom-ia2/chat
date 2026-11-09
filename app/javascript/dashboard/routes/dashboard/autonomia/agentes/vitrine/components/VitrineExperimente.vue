<script setup>
import { ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteBotao from '../../components/AgenteBotao.vue';
import { useVitrine } from '../useVitrine';

// #2776 — testar antes de incluir: um valor de exemplo já preenchido, um botão, e o resultado em linhas legíveis, como
// o teste de verdade mostra. No protótipo o resultado é fictício (adaptador falso).
const props = defineProps({
  ferramentaId: { type: String, required: true },
  rotulo: { type: String, required: true },
  exemplo: { type: String, required: true },
});

const NS = 'AGENTS.VITRINE.DETALHE';
const { t } = useI18n();
const { experimentar } = useVitrine();
const campoId = `experimente-${useId()}`;

const valor = ref(props.exemplo);
const consultando = ref(false);
const linhas = ref([]);

watch(
  () => props.ferramentaId,
  () => {
    valor.value = props.exemplo;
    linhas.value = [];
  }
);

const rodar = async () => {
  if (consultando.value || !valor.value.trim()) return;
  consultando.value = true;
  linhas.value = [];
  linhas.value = await experimentar(props.ferramentaId, valor.value);
  consultando.value = false;
};
</script>

<template>
  <section data-vitrine-experimente class="flex flex-col gap-3">
    <h3 class="m-0 text-base font-semibold text-n-slate-12">
      {{ t(`${NS}.EXPERIMENTE`) }}
    </h3>
    <form class="flex flex-col gap-2 sm:flex-row" @submit.prevent="rodar">
      <div class="flex flex-col flex-1 gap-1">
        <label :for="campoId" class="text-sm text-n-slate-11">
          {{ rotulo }}
        </label>
        <input
          :id="campoId"
          v-model="valor"
          data-experimente-valor
          type="text"
          class="w-full px-3 mb-0 text-base border-0 rounded-xl min-h-11 bg-n-solid-1 text-n-slate-12 ring-1 ring-inset ring-n-slate-7 focus:ring-2 focus:ring-n-blue-11"
        />
      </div>
      <AgenteBotao
        type="submit"
        data-experimentar
        variante="contorno"
        icone="i-lucide-play"
        class="sm:self-end"
        :carregando="consultando"
      >
        {{ consultando ? t(`${NS}.EXPERIMENTANDO`) : t(`${NS}.EXPERIMENTAR`) }}
      </AgenteBotao>
    </form>
    <div aria-live="polite">
      <div
        v-if="linhas.length"
        data-experimente-resultado
        class="flex flex-col gap-2 p-4 rounded-2xl bg-n-teal-2 ring-1 ring-inset ring-n-teal-6"
      >
        <p
          class="flex items-center gap-2 m-0 text-sm font-semibold text-n-teal-11"
        >
          <span class="i-lucide-circle-check size-4" aria-hidden="true" />
          {{ t(`${NS}.DEU_CERTO`) }}
        </p>
        <dl class="grid gap-x-4 gap-y-1 m-0 grid-cols-[auto_1fr]">
          <template v-for="[nome, dado] in linhas" :key="nome">
            <dt class="text-sm text-n-slate-11">{{ nome }}</dt>
            <dd class="m-0 text-sm font-medium text-n-slate-12">{{ dado }}</dd>
          </template>
        </dl>
      </div>
    </div>
  </section>
</template>
