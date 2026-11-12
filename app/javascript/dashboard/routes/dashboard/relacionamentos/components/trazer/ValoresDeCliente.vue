<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  MODOS,
  alternarPreenchidas,
  alternarValor,
  marcouPreenchidas,
  valorMarcado,
} from '../../trazer/valoresDeCliente';

// #2896, E3 — as opções de "Quais destes querem dizer cliente?": a pessoa marca
// o que, naquela coluna, quer dizer cliente. A tela não adivinha pelo texto:
// nada vem marcado. A primeira opção ("toda linha com algo escrito") e os
// valores não ficam marcados juntos. Cada opção é uma caixa de marcar (padrão
// WAI-ARIA de checkbox: cada uma é uma parada do Tab, Espaço marca e desmarca),
// com a contagem de linhas ao lado; o texto longo quebra a linha. A coluna sem
// nada escrito é dita acima das opções, que continuam ali.
//   pergunta: { preenchidas, valores: [{ chave, valor, linhas }], outros }
//   v-model: a resposta (trazer/valoresDeCliente.js); null = nada marcado
const props = defineProps({
  pergunta: { type: Object, required: true },
  modelValue: { type: Object, default: null },
  rotuloId: { type: String, required: true },
  // Faltou marcar: a primeira opção aponta para o aviso.
  invalido: { type: Boolean, default: false },
  descritoPor: { type: String, default: undefined },
});
const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

const linhas = count =>
  t('RELACIONAMENTOS_TRAZER.PERGUNTAS.VALORES.LINHAS', { count }, count);

const opcoes = computed(() => [
  {
    id: MODOS.PREENCHIDAS,
    rotulo: t('RELACIONAMENTOS_TRAZER.PERGUNTAS.VALORES.PREENCHIDAS'),
    linhas: linhas(props.pergunta.preenchidas ?? 0),
    marcada: marcouPreenchidas(props.modelValue),
    primeira: true,
  },
  ...(props.pergunta.valores ?? []).map(({ chave, valor, linhas: conta }) => ({
    id: chave,
    rotulo: valor,
    linhas: linhas(conta),
    marcada: valorMarcado(props.modelValue, chave),
    primeira: false,
  })),
]);

const colunaVazia = computed(
  () =>
    (props.pergunta.preenchidas ?? 0) === 0 &&
    !(props.pergunta.valores ?? []).length
);

// "E mais 7 valores diferentes, em 9 linhas. …": cada número com o seu plural.
const outros = computed(() => {
  const resto = props.pergunta.outros;
  if (!resto) return '';
  return t('RELACIONAMENTOS_TRAZER.PERGUNTAS.VALORES.OUTROS', {
    valores: t(
      'RELACIONAMENTOS_TRAZER.PERGUNTAS.VALORES.OUTROS_VALORES',
      { count: resto.valores },
      resto.valores
    ),
    linhas: t(
      'RELACIONAMENTOS_TRAZER.PERGUNTAS.VALORES.OUTROS_LINHAS',
      { count: resto.linhas },
      resto.linhas
    ),
  });
});

const alternar = opcao => {
  emit(
    'update:modelValue',
    opcao.primeira
      ? alternarPreenchidas(props.modelValue)
      : alternarValor(props.modelValue, opcao.id)
  );
};
</script>

<template>
  <div
    role="group"
    :aria-labelledby="rotuloId"
    data-relacionamentos="valores-de-cliente"
    class="flex flex-col gap-4"
  >
    <p
      v-if="colunaVazia"
      data-relacionamentos="coluna-vazia"
      class="m-0 text-base text-n-slate-11"
    >
      {{ t('RELACIONAMENTOS_TRAZER.PERGUNTAS.VALORES.COLUNA_VAZIA') }}
    </p>
    <ul class="flex flex-col gap-2 p-0 m-0 list-none">
      <li
        v-for="opcao in opcoes"
        :key="opcao.id"
        :class="opcao.primeira ? 'pb-2' : ''"
      >
        <button
          type="button"
          role="checkbox"
          data-relacionamentos="resposta"
          :data-resposta="opcao.id"
          :aria-checked="opcao.marcada ? 'true' : 'false'"
          :aria-invalid="invalido && opcao.primeira ? 'true' : undefined"
          :aria-describedby="opcao.primeira ? descritoPor : undefined"
          class="flex items-start w-full gap-3 px-4 py-3 text-base transition-colors text-start min-h-11 rounded-xl focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :class="
            opcao.marcada
              ? 'bg-n-blue-3 text-n-slate-12 ring-2 ring-inset ring-n-blue-9'
              : 'bg-n-solid-1 text-n-slate-12 ring-1 ring-inset ring-n-weak hover:bg-n-alpha-1'
          "
          @click="alternar(opcao)"
        >
          <span
            class="flex items-center justify-center mt-0.5 rounded size-5 shrink-0 ring-1 ring-inset"
            :class="
              opcao.marcada ? 'bg-n-blue-9 ring-n-blue-9' : 'ring-n-slate-8'
            "
            aria-hidden="true"
          >
            <span
              v-if="opcao.marcada"
              class="text-white i-lucide-check size-4"
            />
          </span>
          <span
            data-relacionamentos="valor"
            class="flex-1 min-w-0 break-words"
            :class="opcao.primeira ? 'font-semibold' : ''"
          >
            {{ opcao.rotulo }}
          </span>
          <span
            data-relacionamentos="linhas-do-valor"
            class="mt-0.5 text-sm shrink-0 tabular-nums text-n-slate-11"
          >
            {{ opcao.linhas }}
          </span>
        </button>
      </li>
    </ul>
    <p
      v-if="outros"
      data-relacionamentos="outros-valores"
      class="m-0 text-base text-n-slate-11"
    >
      {{ outros }}
    </p>
  </div>
</template>
