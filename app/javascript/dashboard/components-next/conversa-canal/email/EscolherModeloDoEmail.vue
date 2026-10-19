<script setup>
// Janela "Modelo de e-mail" do "+" da resposta (#1786): os modelos salvos em Campanhas
// em cartões com a prévia do próprio e-mail, busca e filtro por categoria. Escolher
// fecha a janela e o modelo entra embaixo do texto da resposta, para conferir os campos.
import { computed, ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Icon from 'next/icon/Icon.vue';
import CartaoDoModelo from './CartaoDoModelo.vue';
import { semAcento } from 'dashboard/helper/semAcento';

const props = defineProps({
  modelos: { type: Array, default: () => [] },
  carregando: { type: Boolean, default: false },
});
const emit = defineEmits(['escolher']);

const { t } = useI18n();
const dialogo = useTemplateRef('dialogo');
const busca = ref('');
const categoria = ref('');

const categorias = computed(() => [
  ...new Set(props.modelos.map(m => m.categoria).filter(Boolean)),
]);

const visiveis = computed(() => {
  const termo = semAcento(busca.value.trim());
  return props.modelos.filter(
    m =>
      (!categoria.value || m.categoria === categoria.value) &&
      (!termo || semAcento(`${m.nome} ${m.categoria || ''}`).includes(termo))
  );
});

const fechar = () => dialogo.value?.close();
const escolher = modelo => {
  fechar();
  emit('escolher', modelo.id);
};

const CHIP =
  'inline-flex items-center h-8 px-3 rounded-full text-[13px] font-medium border transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand';

defineExpose({
  open: () => {
    busca.value = '';
    categoria.value = '';
    dialogo.value?.open();
  },
});
</script>

<template>
  <Dialog
    ref="dialogo"
    :show-cancel-button="false"
    :show-confirm-button="false"
    width="3xl"
    overflow-y-auto
  >
    <div class="flex flex-col gap-5" data-janela-de-modelos>
      <header class="flex items-start gap-3">
        <span
          class="grid place-content-center flex-shrink-0 size-11 rounded-xl bg-n-teal-3 text-n-teal-10"
          aria-hidden="true"
        >
          <Icon icon="i-ph-layout-fill" class="size-6" />
        </span>
        <div class="flex-1 min-w-0">
          <h3
            class="flex items-center gap-2 text-lg font-semibold text-n-slate-12"
          >
            {{ t('CONVERSA_CANAL.EMAIL.MODELO_DE_EMAIL') }}
            <span
              v-if="modelos.length"
              class="inline-flex items-center h-5 px-1.5 rounded-md bg-n-alpha-2 text-xs font-medium text-n-slate-11 tabular-nums"
            >
              {{ modelos.length }}
            </span>
          </h3>
          <p class="mt-0.5 text-sm text-n-slate-11">
            {{ t('CONVERSA_CANAL.EMAIL.MODELO_DICA') }}
          </p>
        </div>
        <button
          type="button"
          class="grid place-content-center flex-shrink-0 size-10 -me-2 -mt-1 rounded-full text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :aria-label="t('CONVERSA_CANAL.EMAIL.FECHAR')"
          :title="t('CONVERSA_CANAL.EMAIL.FECHAR')"
          data-fechar-modelos
          @click="fechar"
        >
          <Icon icon="i-lucide-x" class="size-5" />
        </button>
      </header>

      <div class="flex flex-col gap-3">
        <label class="relative block">
          <Icon
            icon="i-lucide-search"
            class="absolute start-3.5 top-1/2 -translate-y-1/2 size-[18px] text-n-slate-10 pointer-events-none"
          />
          <input
            v-model="busca"
            type="search"
            class="w-full h-11 !ps-11 !pe-4 !mb-0 !rounded-full !border !border-solid !border-n-weak !bg-n-alpha-1 text-sm text-n-slate-12 placeholder:text-n-slate-10 focus:!border-n-brand focus:outline-none focus:ring-2 focus:ring-n-brand/20"
            :placeholder="t('CONVERSA_CANAL.EMAIL.BUSCAR_MODELO_DE_EMAIL')"
            :aria-label="t('CONVERSA_CANAL.EMAIL.BUSCAR_MODELO_DE_EMAIL')"
            data-buscar-modelo-de-email
          />
        </label>
        <div
          v-if="categorias.length > 1"
          class="flex flex-wrap gap-2"
          role="group"
          :aria-label="t('CONVERSA_CANAL.EMAIL.CATEGORIAS')"
        >
          <button
            v-for="opcao in ['', ...categorias]"
            :key="opcao || 'todas'"
            type="button"
            :class="[
              CHIP,
              categoria === opcao
                ? 'bg-n-slate-12 text-n-surface-1 border-n-slate-12'
                : 'bg-transparent text-n-slate-11 border-n-weak hover:bg-n-alpha-1 hover:text-n-slate-12',
            ]"
            :aria-pressed="categoria === opcao"
            @click="categoria = opcao"
          >
            {{ opcao || t('CONVERSA_CANAL.EMAIL.TODAS') }}
          </button>
        </div>
      </div>

      <div
        v-if="carregando"
        class="grid grid-cols-2 sm:grid-cols-3 gap-4"
        aria-hidden="true"
      >
        <span
          v-for="n in 3"
          :key="n"
          class="aspect-[4/5] rounded-2xl bg-n-alpha-2 animate-pulse"
        />
      </div>
      <div
        v-else-if="!visiveis.length"
        class="flex flex-col items-center gap-2 py-12 text-center"
      >
        <span
          class="grid place-content-center size-12 rounded-full bg-n-alpha-2 text-n-slate-10"
        >
          <Icon icon="i-lucide-search-x" class="size-6" />
        </span>
        <p class="text-sm text-n-slate-11">
          {{
            modelos.length
              ? t('CONVERSA_CANAL.EMAIL.NENHUM_MODELO_NA_BUSCA')
              : t('CONVERSA_CANAL.EMAIL.SEM_MODELOS_DE_EMAIL')
          }}
        </p>
      </div>
      <ul
        v-else
        class="reset-base list-none grid grid-cols-2 sm:grid-cols-3 gap-4"
        data-lista-de-modelos-de-email
      >
        <li v-for="modelo in visiveis" :key="modelo.id" class="list-none">
          <CartaoDoModelo :modelo="modelo" @escolher="escolher" />
        </li>
      </ul>
    </div>
  </Dialog>
</template>
