<script setup>
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import { formatarCnpj } from '../../ficha/formatos';
import BotaoCopiar from './BotaoCopiar.vue';

// #2894 — o cabeçalho da ficha da empresa: nome, CNPJ com copiar e o site.
defineProps({
  empresa: { type: Object, required: true },
});

const { t } = useI18n();
</script>

<template>
  <header
    data-relacionamentos="cabecalho"
    class="flex w-full min-w-0 gap-4 p-5 border shadow-sm rounded-2xl border-n-weak bg-n-solid-1 md:gap-6 md:p-8"
  >
    <Avatar :name="empresa.name" :size="88" class="shrink-0" />
    <div class="flex flex-col min-w-0 gap-2">
      <h1
        class="m-0 text-3xl font-bold leading-tight tracking-tight break-words md:text-4xl text-n-slate-12"
      >
        {{ empresa.name }}
      </h1>
      <div
        v-if="empresa.cnpj"
        class="flex items-center gap-1 text-base text-n-slate-12"
      >
        <span class="tabular-nums">{{ formatarCnpj(empresa.cnpj) }}</span>
        <BotaoCopiar
          :valor="formatarCnpj(empresa.cnpj)"
          :item="t('RELACIONAMENTOS_FICHA.CABECALHO.ITEM_CNPJ')"
        />
      </div>
      <p
        v-if="empresa.domain"
        class="m-0 text-base break-all text-n-slate-11"
        :title="empresa.domain"
      >
        <span
          class="inline-block align-text-bottom me-1.5 i-lucide-globe size-4"
          aria-hidden="true"
        />
        {{ empresa.domain }}
      </p>
    </div>
  </header>
</template>
