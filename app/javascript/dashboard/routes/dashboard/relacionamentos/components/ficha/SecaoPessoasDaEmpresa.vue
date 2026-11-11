<script setup>
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import SeloDeEstado from '../comum/SeloDeEstado.vue';
import CartaoDaSecao from './CartaoDaSecao.vue';

// #2894 — as pessoas da empresa: cada linha leva à ficha da pessoa. Vazio é uma
// frase.
defineProps({
  pessoas: { type: Array, required: true },
});
const emit = defineEmits(['abrir']);

const { t } = useI18n();
</script>

<template>
  <CartaoDaSecao
    :titulo="t('RELACIONAMENTOS_FICHA.EMPRESA.PESSOAS')"
    data-relacionamentos="pessoas-da-empresa"
  >
    <p
      v-if="!pessoas.length"
      data-relacionamentos="vazio"
      class="m-0 text-base text-n-slate-11"
    >
      {{ t('RELACIONAMENTOS_FICHA.EMPRESA.PESSOAS_VAZIO') }}
    </p>
    <ul v-else class="flex flex-col gap-1 p-0 m-0 list-none">
      <li v-for="pessoa in pessoas" :key="pessoa.id">
        <button
          type="button"
          data-relacionamentos="pessoa-da-empresa"
          class="flex items-center w-full gap-3 px-2 py-2 text-start rounded-xl min-h-11 hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="emit('abrir', pessoa.id)"
        >
          <Avatar
            :name="pessoa.name"
            :src="pessoa.thumbnail"
            :size="40"
            rounded-full
          />
          <span class="flex-1 min-w-0">
            <span class="block text-base font-medium truncate text-n-slate-12">
              {{ pessoa.name }}
            </span>
            <span class="block text-sm truncate text-n-slate-11">
              {{ pessoa.email || pessoa.phone_number }}
            </span>
          </span>
          <SeloDeEstado v-if="pessoa.contact_type === 'customer'" tom="cliente">
            {{ t('RELACIONAMENTOS.COMUM.SELO_CLIENTE') }}
          </SeloDeEstado>
        </button>
      </li>
    </ul>
  </CartaoDaSecao>
</template>
