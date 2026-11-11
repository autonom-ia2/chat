<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import SeloDeEstado from '../comum/SeloDeEstado.vue';
import { falouHa } from '../../lista/tempoRelativo';

// #2894 — uma empresa na lista (aba Empresas): iniciais, nome, "3 pessoas",
// selo Cliente quando alguma pessoa dela é cliente e a última conversa. O
// botão do nome estica a área de clique pela linha toda e abre a ficha.
const props = defineProps({
  empresa: { type: Object, required: true },
  agora: { type: Number, default: () => Date.now() },
});
const emit = defineEmits(['abrir']);

const { t } = useI18n();

const segundaLinha = computed(() => {
  const { contacts_count: pessoas, last_activity_at: ultima } = props.empresa;
  const quando = falouHa(ultima, props.agora);
  return [
    t(
      'RELACIONAMENTOS.LISTA.LINHA.PESSOAS_DA_EMPRESA',
      { count: pessoas },
      pessoas
    ),
    quando.count === undefined
      ? t(quando.chave)
      : t(quando.chave, { count: quando.count }, quando.count),
  ].join(' · ');
});
</script>

<template>
  <li
    data-relacionamentos="linha"
    class="relative flex items-center min-w-0 gap-3 px-3 py-2 transition-colors sm:px-5 min-h-16 hover:bg-n-alpha-1 focus-within:bg-n-alpha-1"
  >
    <Avatar :name="empresa.name" :size="40" />
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
      <p class="m-0 text-sm break-words text-n-slate-11">{{ segundaLinha }}</p>
    </div>
  </li>
</template>
