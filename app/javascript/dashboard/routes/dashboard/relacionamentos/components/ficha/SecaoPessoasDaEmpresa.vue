<script setup>
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import SeloDeEstado from '../comum/SeloDeEstado.vue';
import { partesDoEmail } from '../../trazer/emailEmPartes';
import CartaoDaSecao from './CartaoDaSecao.vue';
import FalhaDaParte from './FalhaDaParte.vue';

// #2894 — as pessoas da empresa: cada linha leva à ficha da pessoa. Vazio é uma
// frase. `falhou`: a leitura não veio. `total` é quantas pessoas a empresa tem:
// a ficha traz as primeiras, e quando há mais a lista diz quantas está mostrando.
defineProps({
  pessoas: { type: Array, required: true },
  falhou: { type: Boolean, default: false },
  total: { type: Number, default: 0 },
});
const emit = defineEmits(['abrir', 'conversar', 'tentar']);

const { t } = useI18n();

// Só o e-mail quebra de linha, e só no "@"; telefone vem inteiro.
const contato = pessoa =>
  pessoa.email ? partesDoEmail(pessoa.email) : [pessoa.phone_number];
</script>

<template>
  <CartaoDaSecao
    :titulo="t('RELACIONAMENTOS_FICHA.EMPRESA.PESSOAS')"
    data-relacionamentos="pessoas-da-empresa"
  >
    <FalhaDaParte v-if="falhou" @tentar="emit('tentar')" />
    <p
      v-else-if="!pessoas.length"
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
            class="row-span-3 self-start md:row-span-2 md:self-center"
            :name="pessoa.name"
            :src="pessoa.thumbnail"
            :size="40"
            rounded-full
          />
          <span
            class="col-start-2 min-w-0 text-base font-medium break-words line-clamp-2 md:truncate text-n-slate-12"
          >
            {{ pessoa.name }}
          </span>
          <span
            v-if="pessoa.contact_type === 'customer' || pessoa.opted_out_at"
            data-relacionamentos="selos-da-pessoa"
            class="flex flex-wrap col-start-2 gap-1 justify-self-start md:col-start-3 md:row-start-1 md:row-span-2 md:justify-self-end"
          >
            <SeloDeEstado
              v-if="pessoa.contact_type === 'customer'"
              tom="cliente"
            >
              {{ t('RELACIONAMENTOS.COMUM.SELO_CLIENTE') }}
            </SeloDeEstado>
            <SeloDeEstado v-if="pessoa.opted_out_at" tom="alerta">
              {{ t('RELACIONAMENTOS.COMUM.SELO_NAO_QUER_MENSAGENS') }}
            </SeloDeEstado>
          </span>
          <span
            data-relacionamentos="email-da-pessoa"
            class="col-start-2 min-w-0 text-sm break-words text-n-slate-11 md:truncate"
          >
            <template
              v-for="(parte, posicao) in contato(pessoa)"
              :key="posicao"
            >
              <wbr v-if="posicao" />{{ parte }}
            </template>
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
    <p
      v-if="!falhou && pessoas.length && total > pessoas.length"
      data-relacionamentos="mostrando-parte"
      class="m-0 mt-3 text-sm text-n-slate-11"
    >
      {{
        t('RELACIONAMENTOS_FICHA.EMPRESA.MOSTRANDO_PARTE', {
          mostradas: pessoas.length,
          total,
        })
      }}
    </p>
  </CartaoDaSecao>
</template>
