<script setup>
// "Encaminhada" / "Encaminhada com frequência" no topo do balão (#1702), numa linha
// própria antes do texto, como no WhatsApp Web (prints do Rodrigo, 16/10): o ícone de
// encaminhar em traço fino (seta dupla quando é com frequência) e a palavra em itálico,
// cinza, 13 px, sem negrito. Vale para a recebida e para a que nós encaminhamos.
// O cinza é o da hora (visualWhatsapp.js, HORA_NO_ENVIADO), não o #8696A0 do WhatsApp:
// no escuro ele dá ~3:1 sobre o verde do enviado, abaixo dos 4,5:1 para texto de 13 px.
// Quem decide se aparece é o balão (Base.vue), com a pele.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { ENCAMINHADA } from './marcasDaMensagem';

const props = defineProps({
  tipo: { type: String, required: true },
});

const { t } = useI18n();
const frequente = computed(() => props.tipo === ENCAMINHADA.FREQUENTE);
</script>

<template>
  <div
    class="flex items-center gap-1 px-1 pb-0.5 text-[13px] leading-[18px] font-normal italic text-[#666666] dark:text-[#B5C2BC] [[data-bubble-name=text]_&]:px-0"
    data-rotulo-encaminhada
    :data-frequente="frequente"
  >
    <span
      class="size-4 shrink-0"
      :class="
        frequente
          ? 'i-ph-arrow-bend-double-up-right'
          : 'i-ph-arrow-bend-up-right'
      "
      aria-hidden="true"
    />
    <span>
      {{
        frequente
          ? t('CONVERSA_CANAL.ENCAMINHADA.FREQUENTE')
          : t('CONVERSA_CANAL.ENCAMINHADA.SIMPLES')
      }}
    </span>
  </div>
</template>
