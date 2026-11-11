<script setup>
import { ref } from 'vue';
import SidePanel from 'dashboard/components-next/side-panel/SidePanel.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { classeDoTom } from 'dashboard/components-next/cartao-de-catalogo/tons';

// #2889 — o detalhe de um modelo, na gaveta lateral: o que ele faz, como fica pronto (o Guia pergunta só o que é da
// conta e nada liga sem a pessoa mandar) e um botão só, fixo embaixo. Mostrar antes de fazer, como a vitrine #2858.
defineProps({
  modelo: { type: Object, default: null },
  desabilitado: { type: Boolean, default: false },
});

const emit = defineEmits(['usar', 'close']);

const painel = ref(null);
const open = () => painel.value?.open();
const close = () => painel.value?.close();

defineExpose({ open, close });
</script>

<template>
  <SidePanel
    ref="painel"
    :title="modelo?.titulo || ''"
    width="lg"
    @close="emit('close')"
  >
    <!-- O título inteiro, sem corte, com o ícone do cartão tocado: a pessoa vê que abriu o que escolheu. -->
    <template #header>
      <div v-if="modelo" class="flex items-start min-w-0 gap-3">
        <span
          aria-hidden="true"
          class="grid rounded-xl place-items-center size-11 shrink-0"
          :class="classeDoTom(modelo.tom)"
        >
          <span :class="modelo.icone" class="size-6" />
        </span>
        <h3
          class="mb-0 text-xl font-semibold leading-snug break-words text-n-slate-12"
        >
          {{ modelo.titulo }}
        </h3>
      </div>
    </template>
    <div v-if="modelo" data-modelo-detalhe class="flex flex-col gap-6">
      <p class="mb-0 text-base leading-relaxed text-n-slate-12">
        {{ modelo.texto }}
      </p>
      <span
        v-if="modelo.ia"
        class="inline-flex items-center self-start gap-1.5 px-2.5 py-1 text-xs font-medium rounded-lg bg-n-iris-3 text-n-iris-11"
      >
        <span class="i-lucide-sparkles size-3.5" aria-hidden="true" />
        {{ $t('AUTOMACAO_MODELOS.USA_IA') }}
      </span>
      <section class="flex flex-col gap-3">
        <h3 class="mb-0 text-sm font-semibold text-n-slate-11">
          {{ $t('AUTOMACAO_MODELOS.COMO_TITULO') }}
        </h3>
        <ol class="flex flex-col gap-3 p-0 m-0 list-none">
          <li
            v-for="(chave, indice) in ['COMO_1', 'COMO_2', 'COMO_3']"
            :key="chave"
            class="flex items-start gap-3"
          >
            <span
              aria-hidden="true"
              class="grid text-sm font-semibold rounded-full place-items-center size-7 shrink-0 bg-n-alpha-2 text-n-slate-12"
            >
              {{ indice + 1 }}
            </span>
            <span class="text-[0.9375rem] leading-relaxed text-n-slate-12">
              {{ $t(`AUTOMACAO_MODELOS.${chave}`) }}
            </span>
          </li>
        </ol>
      </section>
    </div>
    <template #footer>
      <Button
        data-usar-modelo
        :label="$t('AUTOMACAO_MODELOS.USAR')"
        icon="i-lucide-arrow-right"
        trailing-icon
        size="lg"
        class="w-full !min-h-12 !rounded-xl"
        :disabled="desabilitado"
        @click="emit('usar', modelo)"
      />
    </template>
  </SidePanel>
</template>
