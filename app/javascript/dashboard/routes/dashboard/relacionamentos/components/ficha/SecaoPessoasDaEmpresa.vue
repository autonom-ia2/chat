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
const emit = defineEmits(['abrir', 'conversar']);

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
      <li
        v-for="pessoa in pessoas"
        :key="pessoa.id"
        class="relative flex items-center min-w-0 gap-1"
      >
        <button
          type="button"
          data-relacionamentos="pessoa-da-empresa"
          class="grid items-center flex-1 min-w-0 grid-cols-[auto_1fr] px-2 py-2 pe-14 md:pe-2 md:grid-cols-[auto_1fr_auto] gap-x-3 gap-y-0.5 text-start rounded-xl min-h-11 hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="emit('abrir', pessoa.id)"
        >
          <Avatar
            class="md:row-span-2"
            :name="pessoa.name"
            :src="pessoa.thumbnail"
            :size="40"
            rounded-full
          />
          <span
            class="min-w-0 text-base font-medium break-words line-clamp-2 md:truncate text-n-slate-12"
          >
            {{ pessoa.name }}
          </span>
          <SeloDeEstado
            v-if="pessoa.contact_type === 'customer'"
            tom="cliente"
            class="col-start-2 justify-self-start md:col-start-3 md:row-start-1 md:row-span-2 md:justify-self-end"
          >
            {{ t('RELACIONAMENTOS.COMUM.SELO_CLIENTE') }}
          </SeloDeEstado>
          <span
            data-relacionamentos="email-da-pessoa"
            class="min-w-0 col-span-2 col-start-1 text-sm break-words text-n-slate-11 md:col-span-1 md:col-start-2 md:truncate"
          >
            {{ pessoa.email || pessoa.phone_number }}
          </span>
        </button>
        <button
          type="button"
          data-relacionamentos="conversar-com-pessoa"
          :aria-label="
            t('RELACIONAMENTOS_FICHA.EMPRESA.CONVERSAR_COM', {
              nome: pessoa.name,
            })
          "
          class="absolute top-1 end-0 md:static inline-flex items-center justify-center rounded-xl size-11 shrink-0 text-n-slate-11 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="emit('conversar', pessoa)"
        >
          <span class="i-lucide-message-circle size-5" aria-hidden="true" />
        </button>
      </li>
    </ul>
  </CartaoDaSecao>
</template>
