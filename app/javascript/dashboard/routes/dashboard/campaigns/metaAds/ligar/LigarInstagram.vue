<script setup>
import { ref } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';

// Passo 4 (#2338): o Instagram da Página vira caixa de entrada, com um login só que já pede mensagens, comentários
// e números do Instagram. Assim os comentários dos anúncios e Seus posts não pedem outra autorização depois.
// Sem Instagram ligado à Página, o passo é pulado (conta como feito).
defineProps({
  page: { type: Object, default: null },
});
const emit = defineEmits(['ligado']);

const KEY = 'CRM_KANBAN.META_ADS_HUB.LIGAR.INSTAGRAM';
const entrando = ref(false);
// PROTÓTIPO: no PR final, abre o login do Instagram com `purpose: meta_ads_ligar` e volta para ?ligar=instagram.
const entrar = () => {
  entrando.value = true;
  setTimeout(() => {
    entrando.value = false;
    emit('ligado');
  }, 600);
};
</script>

<template>
  <div data-ligar-instagram class="flex flex-col gap-5">
    <span
      class="flex items-center justify-center size-12 rounded-xl bg-n-ruby-3 text-n-ruby-11"
      aria-hidden="true"
    >
      <span class="i-ri-instagram-line size-6" />
    </span>
    <div class="flex flex-col gap-2">
      <h3 class="m-0 text-lg font-semibold text-n-slate-12">
        {{ $t(`${KEY}.TITLE`, { username: page?.instagram?.username || '' }) }}
      </h3>
      <p class="m-0 text-sm leading-6 text-n-slate-11">
        {{ $t(`${KEY}.TEXT`) }}
      </p>
    </div>
    <ul class="flex flex-col gap-2 p-0 m-0 list-none">
      <li
        v-for="item in ['MESSAGES', 'COMMENTS', 'NUMBERS']"
        :key="item"
        class="flex items-center gap-2 text-sm text-n-slate-12"
      >
        <span class="i-lucide-check size-4 text-n-teal-11" aria-hidden="true" />
        {{ $t(`${KEY}.${item}`) }}
      </li>
    </ul>
    <Button
      data-ligar-instagram-entrar
      class="self-start !min-h-11"
      icon="i-ri-instagram-line"
      :is-loading="entrando"
      :label="$t(`${KEY}.CTA`)"
      @click="entrar"
    />
  </div>
</template>
