<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

// #1423 — "Perdeu?" (ST-06): o motivo é opcional, com atalhos de um toque.
// Fora de venda, o título e o botão usam o nome do desfecho do funil.
const props = defineProps({
  rotulo: { type: String, required: true },
  venda: { type: Boolean, default: true },
});
const emit = defineEmits(['confirmar']);

const { t } = useI18n();
const dialogo = ref(null);
const motivo = ref('');
// #1498 — em Atender, motivos de quem não precisa mais (nada de "achou caro").
const atalhos = computed(() =>
  props.venda
    ? ['PRECO', 'SUMIU', 'OUTRO_LUGAR', 'NAO_ERA_HORA'].map(chave =>
        t(`CRM_CARD.DESFECHO.MOTIVO.${chave}`)
      )
    : ['RESOLVEU', 'SUMIU', 'NAO_PRECISA'].map(chave =>
        t(`CRM_CARD.DESFECHO.MOTIVO_ATENDER.${chave}`)
      )
);
const abrir = card => {
  motivo.value = card?.lost_reason || '';
  dialogo.value?.open();
};
const fechar = () => dialogo.value?.close();
const confirmar = () => {
  emit('confirmar', {
    result: 'lost',
    lost_reason: motivo.value.trim() || undefined,
  });
  fechar();
};
defineExpose({ abrir, fechar });
</script>

<template>
  <Dialog
    ref="dialogo"
    data-dialogo-perdeu
    type="alert"
    :title="
      venda
        ? t('CRM_CARD.DESFECHO.PERDEU_TITULO')
        : t('CRM_KANBAN.DRAWER.CLOSE_AS_TITLE', { label: props.rotulo })
    "
    :description="
      venda
        ? t('CRM_CARD.DESFECHO.PERDEU_TEXTO')
        : t('CRM_CARD.DESFECHO.CANCELOU_TEXTO')
    "
    width="md"
    @confirm="confirmar"
  >
    <div class="flex flex-wrap gap-2">
      <button
        v-for="atalho in atalhos"
        :key="atalho"
        type="button"
        :aria-pressed="motivo === atalho"
        class="min-h-11 rounded-xl px-3 ring-1 ring-inset text-sm font-medium transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
        :class="
          motivo === atalho
            ? 'ring-n-blue-8 bg-n-blue-2 text-n-blue-11'
            : 'ring-n-weak bg-n-solid-1 text-n-slate-12 hover:ring-n-slate-7'
        "
        @click="motivo = atalho"
      >
        {{ atalho }}
      </button>
    </div>
    <TextArea
      v-model="motivo"
      :label="t('CRM_CARD.DESFECHO.MOTIVO_ROTULO')"
      :placeholder="
        venda
          ? t('CRM_KANBAN.DRAWER.LOSE_REASON_PLACEHOLDER')
          : t('CRM_CARD.DESFECHO.CANCELAR_EXEMPLO')
      "
      :max-length="500"
      auto-height
    />
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
            venda
              ? t('CRM_CARD.DESFECHO.PERDEU_CONFIRMA')
              : t('CRM_KANBAN.DRAWER.MARK_AS', { label: props.rotulo })
          "
          icon="i-lucide-circle-x"
          ruby
          class="!min-h-11"
        />
      </div>
    </template>
  </Dialog>
</template>
