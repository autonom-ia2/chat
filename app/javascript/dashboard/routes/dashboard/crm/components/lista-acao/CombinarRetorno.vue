<script setup>
import { computed, nextTick, ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import CampoQuando from '../card/CampoQuando.vue';
import { atalhosDeData } from '../card/atalhosDeData';

// #2283 — "Combinar retorno" (Parados e o menu "Alterar") e "Combinar outro"
// (Retornos): o CampoQuando com os atalhos do card (Hoje 17:00 só antes das
// 16h · Amanhã · Em 3 dias · Segunda · Outro dia). `aoCombinar` chama a API e
// devolve true quando deu certo; só aí a janela fecha.
const props = defineProps({
  aoCombinar: { type: Function, required: true },
});

const { t } = useI18n();
const dialogo = useTemplateRef('dialogo');
const cliente = ref(null);
const outro = ref(false);
const quando = ref('');
const salvando = ref(false);
const atalhos = computed(() => atalhosDeData(t));

const abrir = async (card, { nome, combinarOutro = false }) => {
  cliente.value = { card, nome };
  outro.value = combinarOutro;
  const amanha = atalhos.value.find(
    atalho => atalho.rotulo === t('CRM_CARD.RETORNO.ATALHO.AMANHA')
  );
  quando.value = (amanha || atalhos.value[0] || {}).valor || '';
  await nextTick();
  dialogo.value?.open();
};

const confirmar = async () => {
  if (!quando.value || salvando.value) return;
  salvando.value = true;
  try {
    const deuCerto = await props.aoCombinar(cliente.value.card, quando.value);
    if (deuCerto) dialogo.value?.close();
  } finally {
    salvando.value = false;
  }
};

defineExpose({ abrir });
</script>

<template>
  <Dialog
    ref="dialogo"
    width="md"
    :title="
      t(
        outro
          ? 'CRM_LISTA_ACAO.COMBINAR.TITULO_OUTRO'
          : 'CRM_LISTA_ACAO.COMBINAR.TITULO',
        { nome: cliente?.nome }
      )
    "
    :confirm-button-label="t('CRM_LISTA_ACAO.COMBINAR.CONFIRMAR')"
    :cancel-button-label="t('CRM_LISTA_ACAO.COMBINAR.CANCELAR')"
    :disable-confirm-button="!quando"
    :is-loading="salvando"
    @confirm="confirmar"
  >
    <div data-lista-acao-combinar>
      <CampoQuando
        v-model="quando"
        :rotulo="t('CRM_LISTA_ACAO.COMBINAR.QUANDO')"
        :atalhos="atalhos"
      />
    </div>
  </Dialog>
</template>
