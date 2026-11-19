<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import LembreteGaveta from './LembreteGaveta.vue';
import { usePodeCriarLembrete } from './usePodeCriarLembrete';

// #1461 — "Novo lembrete" na ficha do cliente e da empresa (Relacionamento):
// a mesma gaveta do calendário, com o cliente (ou a empresa) já escolhido.
// Com a flag crm_lembretes_v2 e quem pode mexer em cards.
const props = defineProps({
  contato: { type: Object, default: null },
  empresa: { type: Object, default: null },
});

const { t } = useI18n();
const podeCriarLembrete = usePodeCriarLembrete();
const visivel = computed(
  () =>
    podeCriarLembrete.value && Boolean(props.contato?.id || props.empresa?.id)
);
const aberta = ref(false);
</script>

<template>
  <div class="contents">
    <template v-if="visivel">
      <Button
        type="button"
        sm
        outline
        slate
        icon="i-lucide-bell-plus"
        class="min-h-11"
        data-ficha-novo-lembrete
        :label="t('CRM_LEMBRETE.FICHA.NOVO')"
        @click="aberta = true"
      />
      <LembreteGaveta
        :show="aberta"
        :contato="contato"
        :empresa="empresa"
        @close="aberta = false"
      />
    </template>
  </div>
</template>
