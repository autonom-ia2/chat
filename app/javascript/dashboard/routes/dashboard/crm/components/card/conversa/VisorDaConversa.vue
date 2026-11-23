<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { fornecerConversaDaTela } from 'dashboard/components-next/conversa-canal/conversaDaTela';
import ListaDoVisor from './ListaDoVisor.vue';
import { useVisorDaConversa } from './useVisorDaConversa';
import { situacaoDaConversa } from './situacaoDaConversa';

// #3165 — a conversa escolhida na seção Conversas do card, inteira e só para ler, no
// lugar de "Onde está no funil". Responder continua em "Abrir a conversa", na lista.
const props = defineProps({
  // A conversa da lista do card (display_id, inbox_id, inbox_name, contact_name).
  conversa: { type: Object, required: true },
});

const { t } = useI18n();
const V = 'CRM_CARD.CONVERSAS.VISOR';
const visor = useVisorDaConversa(() => props.conversa.display_id);
fornecerConversaDaTela({ conversa: visor.conversa, anexos: visor.anexos });

// O nome do cliente já está no topo do card: o visor diz o canal e a situação.
const caixa = computed(
  () => props.conversa.inbox_name || t('CRM_KANBAN.DRAWER.NO_INBOX')
);
const subtitulo = computed(() =>
  t(`${V}.SUBTITULO`, {
    numero: props.conversa.display_id,
    situacao: situacaoDaConversa(t, props.conversa.status),
  })
);
</script>

<template>
  <section
    data-visor-conversa
    class="flex min-h-0 flex-col overflow-hidden rounded-2xl border border-n-weak bg-n-surface-1 shadow-sm"
    :aria-label="t(`${V}.ROTULO`, { numero: conversa.display_id })"
  >
    <header
      class="flex items-center gap-3 border-b border-n-weak bg-n-solid-1 px-4 py-3"
    >
      <div class="flex min-w-0 flex-1 flex-col">
        <p class="mb-0 truncate text-base font-semibold text-n-slate-12">
          {{ caixa }}
        </p>
        <p class="mb-0 truncate text-sm text-n-slate-11">{{ subtitulo }}</p>
      </div>
    </header>

    <div
      v-if="visor.carregando.value"
      class="flex flex-1 items-center justify-center"
      role="status"
    >
      <Spinner class="text-n-brand" />
      <span class="sr-only">{{ t(`${V}.CARREGANDO`) }}</span>
    </div>
    <div
      v-else-if="visor.erro.value"
      class="flex flex-1 flex-col items-center justify-center gap-3 px-6 text-center"
    >
      <p class="mb-0 text-base text-n-slate-12">{{ t(`${V}.ERRO`) }}</p>
      <Button
        :label="t(`${V}.TENTAR_DE_NOVO`)"
        icon="i-lucide-refresh-cw"
        slate
        faded
        class="!min-h-11"
        @click="visor.recarregar"
      />
    </div>
    <div
      v-else-if="!visor.mensagens.value.length"
      class="flex flex-1 items-center justify-center px-6 text-center"
    >
      <p class="mb-0 text-base text-n-slate-11">{{ t(`${V}.VAZIA`) }}</p>
    </div>
    <ListaDoVisor
      v-else
      class="flex-1"
      :mensagens="visor.mensagens.value"
      :caixa-id="conversa.inbox_id"
      :tem-antigas="visor.temAntigas.value"
      :carregando-antigas="visor.carregandoAntigas.value"
      :erro-antigas="visor.erroAntigas.value"
      :carregar-antigas="visor.carregarAntigas"
    />
    <p
      class="mb-0 border-t border-n-weak bg-n-solid-1 px-4 py-2.5 text-sm text-n-slate-11"
    >
      {{ t(`${V}.SO_LEITURA`) }}
    </p>
  </section>
</template>
