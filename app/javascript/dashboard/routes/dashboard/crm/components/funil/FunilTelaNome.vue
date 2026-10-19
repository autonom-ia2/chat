<script setup>
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import FunilTipo from './FunilTipo.vue';
import FunilModelos from './FunilModelos.vue';

// #1384 — Criar, passo 1: o nome do funil e um modelo para começar pronto.
// Trocar de modelo depois de mudar as etapas pede confirmação (`pendente`).
// #1498 — a primeira pergunta é para que serve o funil. Só depois dela
// aparecem os modelos daquele tipo (quando há mais de um) e o nome.
defineProps({
  tipo: { type: String, default: '' },
  modelo: { type: String, default: '' },
  modelos: { type: Array, default: () => [] },
  pendente: { type: String, default: '' },
});

defineEmits(['tipo', 'escolher', 'confirmar', 'manter']);

const nome = defineModel({ type: String, default: '' });
</script>

<template>
  <FunilTipo :tipo="tipo" @escolher="$emit('tipo', $event)" />
  <template v-if="tipo">
    <FunilModelos
      v-if="modelos.length > 1"
      :tipo="tipo"
      :modelo="modelo"
      :modelos="modelos"
      @escolher="$emit('escolher', $event)"
    />
    <div
      v-if="pendente"
      data-funil-trocar-modelo
      role="alert"
      class="flex flex-col gap-3 rounded-2xl border border-n-amber-6 bg-n-amber-2 p-4 sm:flex-row sm:items-center"
    >
      <p class="mb-0 min-w-0 flex-1 text-[0.9375rem] text-n-amber-12">
        {{
          $t('CRM_FUNIL.MODELOS.TROCAR_AVISO', {
            nome: $t(`CRM_FUNIL.MODELOS.${pendente}.NOME`),
          })
        }}
      </p>
      <div class="flex flex-wrap gap-2">
        <Button
          data-funil-manter-modelo
          :label="$t('CRM_FUNIL.MODELOS.TROCAR_NAO')"
          slate
          faded
          class="!min-h-11"
          @click="$emit('manter')"
        />
        <Button
          data-funil-confirmar-modelo
          :label="$t('CRM_FUNIL.MODELOS.TROCAR_SIM')"
          amber
          class="!min-h-11"
          @click="$emit('confirmar')"
        />
      </div>
    </div>
    <Input
      v-model="nome"
      data-funil-nome
      maxlength="120"
      :label="$t('CRM_FUNIL.NOME')"
      :placeholder="$t('CRM_KANBAN.PIPELINE_DRAWER.NAME_PLACEHOLDER')"
      :message="!nome.trim() ? $t('CRM_FUNIL.NOME_FALTA') : ''"
      :message-type="!nome.trim() ? 'error' : 'info'"
      custom-input-class="!h-12 !rounded-xl !bg-n-solid-1 !px-4 !text-base shadow-sm"
    />
  </template>
</template>
