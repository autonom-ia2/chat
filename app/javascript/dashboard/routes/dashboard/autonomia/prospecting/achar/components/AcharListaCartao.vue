<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

// #2775 — F6, uma lista guardada em "Suas listas": o nome, quantas empresas, os
// números (WhatsApp, e-mail, já no funil) e "Abrir" explícito. A já enviada
// ganha o selo cinza "Já enviada". Um foco de teclado só, o "Abrir": o resto
// do cartão abre no clique (atalho do mouse e do toque), sem segundo foco que
// o leitor de tela leria duas vezes.
const props = defineProps({
  lista: { type: Object, required: true },
});
const emit = defineEmits(['abrir']);

const { t } = useI18n();
const NS = 'PROSPECTING_ACHAR.LISTAS';
const numeros = computed(() =>
  [
    t(`${NS}.COM_WHATSAPP`, { n: props.lista.whatsapp }),
    t(`${NS}.COM_EMAIL`, { n: props.lista.email }),
    t(`${NS}.NO_FUNIL`, { n: props.lista.noCrm }),
  ].join(t('PROSPECTING_ACHAR.COMUM.SEPARADOR'))
);
</script>

<template>
  <li
    class="flex flex-col gap-3 p-5 transition border border-solid shadow-sm cursor-pointer rounded-2xl bg-n-solid-1 border-n-weak hover:border-n-blue-6 sm:flex-row sm:items-center"
    data-lista
    @click="emit('abrir')"
  >
    <div class="flex flex-col flex-1 min-w-0 gap-1" data-lista-corpo>
      <span class="flex flex-wrap items-center gap-2">
        <span class="text-lg font-semibold break-words text-n-slate-12">
          {{ lista.nome }}
        </span>
        <span
          v-if="lista.enviada"
          class="px-3 py-0.5 text-sm rounded-full bg-n-slate-3 text-n-slate-11"
          data-enviada
        >
          {{ $t(`${NS}.ENVIADA`) }}
        </span>
      </span>
      <span class="text-base text-n-slate-12" data-empresas>
        {{ $t(`${NS}.EMPRESAS`, { n: lista.empresas }, lista.empresas) }}
      </span>
      <span class="text-sm text-n-slate-11" data-numeros>{{ numeros }}</span>
    </div>
    <Button
      :label="$t('PROSPECTING_ACHAR.COMUM.ABRIR')"
      :aria-label="
        $t('PROSPECTING_ACHAR.COMUM.ABRIR_ROTULO', { nome: lista.nome })
      "
      slate
      faded
      class="!min-h-11 !rounded-xl self-start sm:self-center shrink-0"
      data-abrir-lista
      @click.stop="emit('abrir')"
    />
  </li>
</template>
