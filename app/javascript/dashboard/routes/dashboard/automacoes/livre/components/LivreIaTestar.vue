<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { custoMedio, testarPasso } from '../iaDemo';

// #2500 F7 — no "Alterar" de um passo de IA: quanto ele custa por vez, na chave
// da conta, e o "Testar este passo". O teste é a única chamada paga fora de uma
// execução: roda em até 3 conversas que a pessoa vê, não manda e não grava. O
// "extrair" não tem teste: gravar é o que ele faz.
const props = defineProps({
  passo: { type: Object, required: true },
});

const { t, locale } = useI18n();
const I = 'AUTOMACAO_LIVRE.IA';

const dinheiro = valor =>
  new Intl.NumberFormat(locale.value, {
    minimumFractionDigits: 4,
    maximumFractionDigits: 4,
  }).format(valor);

const media = computed(() => custoMedio(props.passo.tipo));
const testavel = computed(() =>
  ['decidir', 'escrever', 'resumir'].includes(props.passo.tipo)
);

const rodando = ref(false);
const resposta = ref(null);
watch(
  () => props.passo.tipo,
  () => {
    resposta.value = null;
  }
);

const testar = async () => {
  rodando.value = true;
  try {
    resposta.value = await testarPasso(props.passo);
  } finally {
    rodando.value = false;
  }
};

const linhaDaConversa = conversa => {
  if (props.passo.tipo !== 'decidir') return conversa.texto;
  return conversa.caminho
    ? t(`${I}.TESTAR.ESCOLHEU`, { caminho: conversa.caminho })
    : t(`${I}.TESTAR.NENHUM`);
};
</script>

<template>
  <section
    data-ia-testar
    class="flex flex-col gap-3 p-4 border rounded-xl border-n-weak bg-n-alpha-1"
  >
    <p data-ia-custo class="mb-0 text-sm text-n-slate-11">
      <span class="i-lucide-coins size-4 align-[-2px]" aria-hidden="true" />
      {{
        media
          ? $t(`${I}.CUSTO.MEDIA`, { valor: dinheiro(media) })
          : $t(`${I}.CUSTO.PRIMEIRA`)
      }}
    </p>

    <template v-if="testavel">
      <p class="mb-0 text-sm text-n-slate-11">
        {{ $t(`${I}.TESTAR.DICA`, { valor: dinheiro((media || 0) * 3) }) }}
      </p>
      <Button
        data-testar
        :label="rodando ? $t(`${I}.TESTAR.RODANDO`) : $t(`${I}.TESTAR.BOTAO`)"
        icon="i-lucide-flask-conical"
        faded
        class="self-start min-h-11"
        :disabled="rodando"
        @click="testar"
      />
      <ol v-if="resposta" class="flex flex-col gap-2 p-0 m-0 list-none">
        <li
          v-for="conversa in resposta.conversas"
          :key="conversa.id"
          data-teste-conversa
          class="flex flex-col gap-1 p-3 rounded-lg bg-n-solid-1"
        >
          <span class="text-xs font-medium text-n-slate-10">
            {{ $t(`${I}.TESTAR.CONVERSA`, { id: conversa.id }) }}
          </span>
          <span class="text-[0.9375rem] text-n-slate-12 whitespace-pre-line">
            {{ linhaDaConversa(conversa) }}
          </span>
          <span
            v-if="passo.tipo === 'decidir' && conversa.motivo"
            class="text-sm text-n-slate-11"
          >
            {{ $t(`${I}.TESTAR.MOTIVO`, { motivo: conversa.motivo }) }}
          </span>
        </li>
      </ol>
      <p v-if="resposta" class="mb-0 text-xs text-n-slate-10">
        {{ $t(`${I}.TESTAR.CUSTOU`, { valor: dinheiro(resposta.custo) }) }}
      </p>
    </template>
  </section>
</template>
