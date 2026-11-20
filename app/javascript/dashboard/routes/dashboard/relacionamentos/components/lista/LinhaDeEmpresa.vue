<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import SeloDeEstado from '../comum/SeloDeEstado.vue';
import SegundaLinha from './SegundaLinha.vue';
import { falouHa } from '../../lista/tempoRelativo';

// #2894 — uma empresa na lista (aba Empresas): iniciais, nome, "3 pessoas",
// selo Cliente quando alguma pessoa dela é cliente e a última conversa. O
// botão do nome estica a área de clique pela linha toda e abre a ficha.
// #3078 — com a foto da empresa (quando tem) e a cidade na segunda linha,
// como a lista antiga de Empresas. A caixa de marcar (`podeMarcar`, a página
// liga para quem pode apagar empresa) fica por cima e não abre a ficha. No
// celular ela ocupa os 44 px do toque sem somar espaço em volta (-mx-2).
const props = defineProps({
  empresa: { type: Object, required: true },
  marcada: { type: Boolean, default: false },
  podeMarcar: { type: Boolean, default: false },
  agora: { type: Number, default: () => Date.now() },
});
const emit = defineEmits(['abrir', 'alternar']);

const { t } = useI18n();

const pessoasDaEmpresa = computed(() => {
  const pessoas = props.empresa.contacts_count;
  return t(
    'RELACIONAMENTOS.LISTA.LINHA.PESSOAS_DA_EMPRESA',
    { count: pessoas },
    pessoas
  );
});
const quandoFalou = computed(() => {
  const quando = falouHa(props.empresa.last_activity_at, props.agora);
  return quando.count === undefined
    ? t(quando.chave)
    : t(quando.chave, { count: quando.count }, quando.count);
});
const partes = computed(() =>
  [pessoasDaEmpresa.value, props.empresa.city, quandoFalou.value].filter(
    Boolean
  )
);
</script>

<template>
  <li
    data-relacionamentos="linha"
    class="relative flex items-center min-w-0 gap-3 px-3 py-2 transition-colors sm:px-5 min-h-16 hover:bg-n-alpha-1 focus-within:bg-n-alpha-1"
    :class="{ 'bg-n-alpha-1': marcada }"
  >
    <label
      v-if="podeMarcar"
      class="relative z-10 flex items-center justify-center cursor-pointer size-11 shrink-0 max-sm:-mx-2"
    >
      <span class="sr-only">
        {{ t('RELACIONAMENTOS.LISTA.LINHA.MARCAR', { nome: empresa.name }) }}
      </span>
      <Checkbox
        data-relacionamentos="marcar"
        class="[&_input:checked:hover]:bg-n-brand"
        :model-value="marcada"
        @change="emit('alternar', empresa)"
      />
    </label>
    <Avatar :name="empresa.name" :src="empresa.thumbnail" :size="40" />
    <div class="flex flex-col flex-1 min-w-0 gap-0.5">
      <div class="flex flex-wrap items-center gap-x-2 gap-y-1">
        <button
          type="button"
          class="min-w-0 p-0 text-base font-semibold text-start truncate border-0 bg-transparent text-n-slate-12 after:absolute after:inset-0 focus-visible:outline-none focus-visible:after:outline focus-visible:after:outline-2 focus-visible:after:-outline-offset-2 focus-visible:after:outline-n-brand focus-visible:after:rounded-2xl"
          @click="emit('abrir', empresa)"
        >
          {{ empresa.name }}
        </button>
        <SeloDeEstado v-if="empresa.customers_count > 0" tom="cliente">
          {{ t('RELACIONAMENTOS.COMUM.SELO_CLIENTE') }}
        </SeloDeEstado>
      </div>
      <SegundaLinha :partes="partes" />
    </div>
  </li>
</template>
