<script setup>
// #2084/#2085 — "Este contato é" na página do contato, atrás da chave `contato_relacao`.
// Sem acesso, a seção inteira some (e não só a escolha, deixando o título sozinho).
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { ESTADO } from 'dashboard/components-next/painel-do-contato/useParteDoPainel';
import EscolhaDaRelacao from './EscolhaDaRelacao.vue';

defineProps({
  contactId: { type: [Number, String], required: true },
  readOnly: { type: Boolean, default: false },
});

const { t } = useI18n();
const estado = ref(ESTADO.CARREGANDO);
const visivel = computed(
  () => ![ESTADO.ESCONDIDO, ESTADO.VAZIO].includes(estado.value)
);
</script>

<template>
  <div
    v-show="visivel"
    class="flex flex-col items-start w-full gap-4 pt-6 border-t border-n-strong"
    data-test-id="secao-relacao"
  >
    <h6 class="text-base font-medium text-n-slate-12">
      {{ t('PAINEL_DO_CONTATO.RELACAO.TITULO') }}
    </h6>
    <div class="w-full max-w-md">
      <EscolhaDaRelacao
        :contact-id="contactId"
        :pode-editar="!readOnly"
        @estado="estado = $event"
      />
    </div>
  </div>
</template>
