<script setup>
// Nome da etiqueta em Configurações › Etiquetas (#1823). F1a, flag
// `etiquetas_do_whatsapp`: o nome livre em destaque e o título técnico embaixo,
// porque é ele que o filtro e a automação usam; desligada, só o título, como no
// Chatwoot. F1b, flag `etiquetas_do_celular`: os selos do WhatsApp do celular
// (caixa, nome no celular quando difere do que está em destaque, criada pelo celular).
import { computed } from 'vue';
import { useNomeDaEtiqueta } from 'dashboard/composables/useNomeDaEtiqueta';

const props = defineProps({
  titulo: { type: String, required: true },
});

const { ligada, nomeDe, vinculosDe } = useNomeDaEtiqueta();

const nome = computed(() =>
  ligada.value ? nomeDe(props.titulo) : props.titulo
);
const vinculos = computed(() => vinculosDe(props.titulo));
const nomesNoCelular = computed(() => [
  ...new Set(
    vinculos.value
      .map(({ nomeNoCelular }) => nomeNoCelular)
      .filter(noCelular => noCelular && noCelular !== nome.value)
  ),
]);
const criadaPeloCelular = computed(() =>
  vinculos.value.some(({ criadaPeloCelular: criada }) => criada)
);

const SELO =
  'inline-flex items-center gap-1 min-h-5 px-1.5 rounded-md text-label-small break-words';
</script>

<template>
  <div class="flex flex-col gap-1 min-w-0">
    <span class="text-body-main text-n-slate-12 break-words">
      {{ nome }}
    </span>
    <code
      v-if="ligada"
      class="self-start text-label-small text-n-slate-11 break-all"
    >
      {{ titulo }}
    </code>
    <div v-if="vinculos.length" class="flex flex-wrap items-center gap-1.5">
      <span
        v-for="vinculo in vinculos"
        :key="vinculo.inboxId"
        :class="SELO"
        class="bg-n-teal-3 text-n-teal-11"
      >
        <span class="i-ri-whatsapp-line size-3 flex-shrink-0" />
        {{ $t('LABEL_MGMT.WHATSAPP.BADGE', { caixa: vinculo.caixa }) }}
      </span>
      <span
        v-for="noCelular in nomesNoCelular"
        :key="noCelular"
        :class="SELO"
        class="bg-n-alpha-2 text-n-slate-11"
      >
        {{ $t('LABEL_MGMT.WHATSAPP.NAME_ON_PHONE', { nome: noCelular }) }}
      </span>
      <span
        v-if="criadaPeloCelular"
        :class="SELO"
        class="bg-n-alpha-2 text-n-slate-11"
      >
        {{ $t('LABEL_MGMT.WHATSAPP.CREATED_BY_PHONE') }}
      </span>
    </div>
  </div>
</template>
