<script setup>
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { formatarCnpj } from '../../ficha/formatos';
import BotaoCopiar from './BotaoCopiar.vue';

// #2894 — o cabeçalho da ficha da empresa: nome, CNPJ com copiar e o site, e as
// ações: "Mandar mensagem" (a única preenchida) e "Alterar" (discreta).
defineProps({
  empresa: { type: Object, required: true },
});
const emit = defineEmits(['mandarMensagem', 'alterar']);

const { t } = useI18n();
</script>

<template>
  <header
    data-relacionamentos="cabecalho"
    class="flex flex-col w-full min-w-0 gap-6 p-5 border shadow-sm rounded-2xl border-n-weak bg-n-solid-1 md:p-8 lg:flex-row lg:items-start lg:justify-between"
  >
    <div
      class="grid w-full min-w-0 grid-cols-[auto_1fr] items-center gap-x-4 gap-y-4 md:items-start md:gap-x-6 lg:flex-1"
    >
      <Avatar :name="empresa.name" :size="56" class="shrink-0 md:hidden" />
      <Avatar
        :name="empresa.name"
        :size="88"
        class="hidden shrink-0 md:row-span-2 md:inline-flex"
      />
      <h1
        class="m-0 text-2xl font-bold leading-tight tracking-tight break-words md:text-4xl text-n-slate-12"
      >
        {{ empresa.name }}
      </h1>
      <div
        data-relacionamentos="contato-da-empresa"
        class="flex flex-col min-w-0 col-span-2 gap-1 md:col-span-1 md:col-start-2"
      >
        <div
          v-if="empresa.cnpj"
          class="flex items-center gap-1 text-base text-n-slate-12"
        >
          <span class="tabular-nums whitespace-nowrap">
            {{ formatarCnpj(empresa.cnpj) }}
          </span>
          <BotaoCopiar
            class="-my-2"
            :valor="formatarCnpj(empresa.cnpj)"
            :item="t('RELACIONAMENTOS_FICHA.CABECALHO.ITEM_CNPJ')"
          />
        </div>
        <p
          v-if="empresa.domain"
          class="flex items-center min-w-0 gap-2 m-0 text-base text-n-slate-11"
        >
          <span
            class="i-lucide-globe size-4 shrink-0 text-n-slate-10"
            aria-hidden="true"
          />
          <span
            class="min-w-0 truncate whitespace-nowrap"
            :title="empresa.domain"
          >
            {{ empresa.domain }}
          </span>
        </p>
      </div>
    </div>
    <div
      role="group"
      :aria-label="
        t('RELACIONAMENTOS_FICHA.EMPRESA.ACOES', { nome: empresa.name })
      "
      class="flex flex-col w-full min-w-0 gap-3 lg:w-auto lg:shrink-0"
    >
      <div class="flex flex-col gap-3 sm:flex-row sm:items-center">
        <Button
          data-relacionamentos="mandar-mensagem"
          size="lg"
          class="w-full sm:w-auto whitespace-nowrap shrink-0"
          icon="i-lucide-send"
          :label="t('RELACIONAMENTOS_FICHA.EMPRESA.MANDAR')"
          @click="emit('mandarMensagem')"
        />
        <Button
          data-relacionamentos="alterar-empresa"
          slate
          faded
          size="lg"
          class="w-full sm:w-auto whitespace-nowrap shrink-0"
          :label="t('RELACIONAMENTOS_FICHA.EMPRESA.ALTERAR')"
          @click="emit('alterar')"
        />
      </div>
    </div>
  </header>
</template>
