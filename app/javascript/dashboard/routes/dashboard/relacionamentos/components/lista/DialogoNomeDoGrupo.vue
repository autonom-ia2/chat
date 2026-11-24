<script setup>
import { computed, nextTick, ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TituloDoDialogo from '../comum/TituloDoDialogo.vue';
import CampoDeTexto from '../ficha/CampoDeTexto.vue';

// #3168 — o nome do grupo: "Guardar como grupo" (grupo novo) e "Trocar o nome
// do grupo" (`abrir(nomeAtual)`), o mesmo diálogo. Nome vazio mostra o erro na
// linha e não fecha; nome repetido pode (como os Segmentos de hoje). Quem
// grava é a tela, por `guardar(nome)`; ela fecha o diálogo com `fechar()`.
// No grupo novo, embaixo do nome, a frase de quem entra (`resumo`,
// lista/resumoDoGrupo.js) e o aviso de que o grupo se atualiza sozinho.
defineProps({
  salvando: { type: Boolean, default: false },
  resumo: { type: String, default: '' },
});
const emit = defineEmits(['guardar']);

const { t } = useI18n();
const MG = 'RELACIONAMENTOS.LISTA.MEUS_GRUPOS';
const dialogo = useTemplateRef('dialogo');
const caixa = useTemplateRef('caixa');
const nome = ref('');
const trocando = ref(false);
const mostrarErro = ref(false);

const erro = computed(() =>
  mostrarErro.value && !nome.value.trim() ? t(`${MG}.NOME_VAZIO`) : ''
);
const titulo = computed(() =>
  t(trocando.value ? `${MG}.TROCAR_NOME_TITULO` : `${MG}.GUARDAR_TITULO`)
);

const focarCampo = async () => {
  await nextTick();
  caixa.value?.querySelector('input')?.focus();
};

const abrir = (nomeAtual = '') => {
  nome.value = nomeAtual;
  trocando.value = Boolean(nomeAtual);
  mostrarErro.value = false;
  dialogo.value?.open();
  focarCampo();
};
const fechar = () => dialogo.value?.close();

const guardar = () => {
  const escrito = nome.value.trim();
  if (!escrito) {
    mostrarErro.value = true;
    focarCampo();
    return;
  }
  emit('guardar', escrito);
};

defineExpose({ abrir, fechar });
</script>

<template>
  <Dialog
    ref="dialogo"
    width="sm"
    :confirm-button-label="t(`${MG}.GUARDAR`)"
    :cancel-button-label="t('RELACIONAMENTOS.COMUM.CANCELAR')"
    :is-loading="salvando"
    @confirm="guardar"
  >
    <!-- Enter no campo envia o formulário do próprio Dialog (confirm). -->
    <div
      ref="caixa"
      class="flex flex-col gap-4"
      data-relacionamentos="dialogo-nome-do-grupo"
    >
      <TituloDoDialogo :titulo="titulo" />
      <CampoDeTexto
        v-model="nome"
        :rotulo="t(`${MG}.QUE_NOME`)"
        :erro="erro"
        :placeholder="t(`${MG}.NOME_EXEMPLO`)"
        maxlength="80"
        autocomplete="off"
      />
      <div
        v-if="!trocando && resumo"
        class="flex flex-col gap-1 px-4 py-3 rounded-xl bg-n-alpha-1"
        data-relacionamentos="resumo-do-grupo-novo"
      >
        <p class="m-0 text-sm break-words text-n-slate-12">
          <span class="font-medium">{{ t(`${MG}.QUEM_ENTRA`) }}</span>
          {{ resumo }}
        </p>
        <p class="m-0 text-sm text-n-slate-11">{{ t(`${MG}.SE_ATUALIZA`) }}</p>
      </div>
    </div>
  </Dialog>
</template>
