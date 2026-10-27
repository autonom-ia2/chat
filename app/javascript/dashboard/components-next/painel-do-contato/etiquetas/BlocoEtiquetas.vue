<script setup>
// #2202 (PR 3) — bloco "Etiquetas" do painel: as etiquetas da conversa, cada uma
// com cor e nome. Só aparece quando a conversa tem etiqueta. Quem opera a
// conversa toca nelas e abre a escolha ("Etiquetas desta conversa"); quem só lê
// vê as etiquetas sem botão (o servidor recusa do mesmo jeito).
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useConversationLabels } from 'dashboard/composables/useConversationLabels';
import { useNomeDaEtiqueta } from 'dashboard/composables/useNomeDaEtiqueta';
import BlocoDoPainel from '../BlocoDoPainel.vue';
import EtiquetasDaConversaDialog from './EtiquetasDaConversaDialog.vue';

defineProps({
  podeOperar: { type: Boolean, default: false },
});

const { t } = useI18n();
const { activeLabels } = useConversationLabels();
const { nomeDe } = useNomeDaEtiqueta();
const escolha = ref(null);
// O nome do botão diz quais etiquetas a conversa tem (o leitor de tela lê só ele).
const nomeDoBotao = computed(() =>
  t('PAINEL_DO_CONTATO.ETIQUETAS.MUDAR', {
    etiquetas: activeLabels.value.map(label => nomeDe(label.title)).join(', '),
  })
);
</script>

<template>
  <BlocoDoPainel
    v-if="activeLabels.length"
    :titulo="t('PAINEL_DO_CONTATO.ETIQUETAS.TITULO')"
    data-test-id="bloco-etiquetas"
  >
    <component
      :is="podeOperar ? 'button' : 'div'"
      :type="podeOperar ? 'button' : undefined"
      :aria-label="podeOperar ? nomeDoBotao : undefined"
      class="flex items-center w-full gap-2 px-2 py-1.5 -mx-2 text-left rounded-lg min-h-11"
      :class="
        podeOperar
          ? 'hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand'
          : ''
      "
      data-test-id="etiquetas-da-conversa"
      @click="podeOperar && escolha?.abrir()"
    >
      <span class="flex flex-wrap flex-1 min-w-0 gap-2">
        <span
          v-for="label in activeLabels"
          :key="label.id"
          class="flex items-center min-w-0 gap-1.5 px-2 rounded-md h-7 bg-n-alpha-2"
          data-test-id="etiqueta"
        >
          <span
            class="flex-shrink-0 rounded-full size-2.5 outline outline-1 outline-n-weak"
            :style="{ backgroundColor: label.color }"
          />
          <span class="text-sm truncate text-n-slate-12">
            {{ nomeDe(label.title) }}
          </span>
        </span>
      </span>
      <span
        v-if="podeOperar"
        class="flex-shrink-0 i-lucide-pencil size-4 text-n-slate-11"
      />
    </component>
  </BlocoDoPainel>
  <!-- Fora do bloco: tirar a última etiqueta some com o bloco, não com a escolha. -->
  <EtiquetasDaConversaDialog v-if="podeOperar" ref="escolha" />
</template>
