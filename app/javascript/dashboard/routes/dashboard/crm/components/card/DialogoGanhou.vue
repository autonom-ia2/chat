<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { MOEDAS } from './useCardNegocio';

// #1423 — "Ganhou?" (ST-05): o valor vem pronto (o do card, às vezes achado na
// conversa) e a moeda é por escolha (OB-06). Só manda o valor quando é maior
// que zero, como antes. Funil que não é de venda nem abre este diálogo.
const props = defineProps({
  rotulo: { type: String, required: true },
  achadoNaConversa: { type: Boolean, default: false },
  padrao: { type: Boolean, default: false },
});
const emit = defineEmits(['confirmar']);

const { t, te } = useI18n();
const dialogo = ref(null);
const valor = ref('');
const moeda = ref('BRL');
// #2075 — sem a chave de valores a pessoa não vê o valor: ganha sem mexer nele.
const oculto = ref(false);
const moedas = computed(() =>
  [...new Set([...MOEDAS, moeda.value])].map(codigo => ({
    value: codigo,
    label: te(`CRM_CARD.NEGOCIO.MOEDA.${codigo}`)
      ? t(`CRM_CARD.NEGOCIO.MOEDA.${codigo}`)
      : codigo,
  }))
);

const abrir = card => {
  oculto.value = Boolean(card?.value_hidden);
  valor.value = card?.value_cents ? Number(card.value_cents) / 100 : '';
  moeda.value = card?.currency || 'BRL';
  dialogo.value?.open();
};
const fechar = () => dialogo.value?.close();
const confirmar = () => {
  if (oculto.value) {
    emit('confirmar', { result: 'won' });
    fechar();
    return;
  }
  const numero = Number(valor.value);
  emit('confirmar', {
    result: 'won',
    value_cents:
      Number.isFinite(numero) && numero > 0
        ? Math.round(numero * 100)
        : undefined,
    currency: moeda.value || 'BRL',
  });
  fechar();
};
defineExpose({ abrir, fechar });
</script>

<template>
  <Dialog
    ref="dialogo"
    data-dialogo-ganhou
    :title="
      padrao
        ? t('CRM_CARD.DESFECHO.GANHOU_TITULO_PADRAO')
        : t('CRM_CARD.DESFECHO.GANHOU_TITULO', { rotulo: props.rotulo })
    "
    :description="oculto ? '' : t('CRM_CARD.DESFECHO.GANHOU_TEXTO')"
    width="md"
    @confirm="confirmar"
  >
    <p
      v-if="oculto"
      class="mb-0 rounded-xl bg-n-alpha-2 p-3 text-sm text-n-slate-11"
      data-ganhou-valor-oculto
    >
      {{ t('CRM_CARD.DESFECHO.VALOR_OCULTO') }}
    </p>
    <p
      v-else-if="achadoNaConversa"
      class="mb-0 flex items-center gap-2 rounded-xl bg-n-iris-2 p-3 text-sm text-n-slate-12"
    >
      <span
        class="i-lucide-sparkles size-4 text-n-iris-11"
        aria-hidden="true"
      />
      {{ t('CRM_CARD.DESFECHO.ACHADO') }}
    </p>
    <div
      v-if="!oculto"
      class="grid grid-cols-[minmax(0,8rem)_minmax(0,1fr)] gap-2"
    >
      <ChoiceSelect
        v-model="moeda"
        :options="moedas"
        :aria-label="t('CRM_CARD.NEGOCIO.MOEDA_ROTULO')"
        class="w-full"
      />
      <Input
        v-model="valor"
        type="number"
        min="0"
        step="0.01"
        :aria-label="t('CRM_CARD.DESFECHO.VALOR')"
        :placeholder="t('CRM_CARD.NEGOCIO.VALOR_EXEMPLO')"
      />
    </div>
    <template #footer>
      <div class="flex flex-wrap justify-end gap-2">
        <Button
          type="button"
          :label="t('CRM_CARD.CANCELAR')"
          slate
          faded
          class="!min-h-11"
          @click="fechar"
        />
        <Button
          type="submit"
          :label="
            padrao
              ? t('CRM_CARD.DESFECHO.GANHOU_CONFIRMA_PADRAO')
              : t('CRM_CARD.DESFECHO.GANHOU_CONFIRMA', { rotulo: props.rotulo })
          "
          icon="i-lucide-trophy"
          teal
          class="!min-h-11"
        />
      </div>
    </template>
  </Dialog>
</template>
