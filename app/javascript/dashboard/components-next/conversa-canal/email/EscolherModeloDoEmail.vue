<script setup>
// Janela "Modelo de e-mail" do "+" da resposta (#1786): os modelos salvos em Campanhas
// em cartões (miniatura e nome), com busca. Escolher fecha a janela e o modelo entra
// embaixo do texto da resposta, para conferir os campos.
import { computed, ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Icon from 'next/icon/Icon.vue';

const props = defineProps({
  modelos: { type: Array, default: () => [] },
  carregando: { type: Boolean, default: false },
});
const emit = defineEmits(['escolher']);

const { t } = useI18n();
const dialogo = useTemplateRef('dialogo');
const busca = ref('');

const minusculo = texto =>
  String(texto || '')
    .normalize('NFD')
    .split('')
    .filter(letra => letra.charCodeAt(0) < 0x300 || letra.charCodeAt(0) > 0x36f)
    .join('')
    .toLowerCase();

const visiveis = computed(() => {
  const termo = minusculo(busca.value.trim());
  if (!termo) return props.modelos;
  return props.modelos.filter(m =>
    minusculo(`${m.nome} ${m.categoria || ''}`).includes(termo)
  );
});

const escolher = modelo => {
  dialogo.value?.close();
  emit('escolher', modelo.id);
};

defineExpose({
  open: () => {
    busca.value = '';
    dialogo.value?.open();
  },
});
</script>

<template>
  <Dialog
    ref="dialogo"
    :title="t('CONVERSA_CANAL.EMAIL.MODELO_DE_EMAIL')"
    :description="t('CONVERSA_CANAL.EMAIL.MODELO_DICA')"
    :show-confirm-button="false"
    :cancel-button-label="t('CONVERSA_CANAL.EMAIL.FECHAR')"
    width="3xl"
    overflow-y-auto
  >
    <label class="relative block mb-4">
      <Icon
        icon="i-lucide-search"
        class="absolute start-3 top-1/2 -translate-y-1/2 size-4 text-n-slate-10"
      />
      <input
        v-model="busca"
        type="search"
        class="w-full h-11 ps-9 pe-3 !mb-0 rounded-xl border border-n-weak bg-n-alpha-1 text-sm text-n-slate-12 focus:outline focus:outline-2 focus:outline-n-brand"
        :placeholder="t('CONVERSA_CANAL.EMAIL.BUSCAR_MODELO_DE_EMAIL')"
        data-buscar-modelo-de-email
      />
    </label>
    <p
      v-if="carregando"
      class="flex items-center gap-2 py-8 justify-center text-sm text-n-slate-11"
    >
      <Icon icon="i-lucide-loader-circle" class="size-4 animate-spin" />
      {{ t('CONVERSA_CANAL.EMAIL.CARREGANDO_MODELOS') }}
    </p>
    <p
      v-else-if="!visiveis.length"
      class="py-8 text-center text-sm text-n-slate-11"
    >
      {{
        modelos.length
          ? t('CONVERSA_CANAL.EMAIL.NENHUM_MODELO_NA_BUSCA')
          : t('CONVERSA_CANAL.EMAIL.SEM_MODELOS_DE_EMAIL')
      }}
    </p>
    <ul
      v-else
      class="reset-base list-none grid grid-cols-2 sm:grid-cols-3 gap-3"
      data-lista-de-modelos-de-email
    >
      <li v-for="modelo in visiveis" :key="modelo.id" class="list-none">
        <button
          type="button"
          class="group flex flex-col w-full overflow-hidden rounded-xl border border-n-weak bg-n-surface-1 text-start hover:shadow-[0_1px_3px_rgba(0,0,0,0.12),0_4px_12px_rgba(0,0,0,0.08)] focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :data-modelo-de-email="modelo.id"
          @click="escolher(modelo)"
        >
          <span
            class="block aspect-[4/3] w-full overflow-hidden bg-n-alpha-1"
          >
            <img
              v-if="modelo.miniatura"
              :src="modelo.miniatura"
              :alt="modelo.nome"
              loading="lazy"
              class="size-full object-cover object-top transition-transform duration-300 group-hover:scale-[1.03]"
            />
            <span
              v-else
              class="grid place-content-center size-full text-n-teal-10"
            >
              <Icon icon="i-ph-layout-fill" class="size-10" />
            </span>
          </span>
          <span class="px-3 py-2.5">
            <span
              class="block truncate text-sm font-medium text-n-slate-12"
              :title="modelo.nome"
            >
              {{ modelo.nome }}
            </span>
            <span
              v-if="modelo.categoria"
              class="block truncate text-xs text-n-slate-11"
            >
              {{ modelo.categoria }}
            </span>
          </span>
        </button>
      </li>
    </ul>
  </Dialog>
</template>
