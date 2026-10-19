<script setup>
// Nome da etiqueta em Configurações › Etiquetas (#1823, F1a): o nome livre em
// destaque e o título técnico embaixo, porque é ele que o filtro e a automação
// usam. Flag `etiquetas_do_whatsapp` desligada: só o título, como no Chatwoot.
import { useNomeDaEtiqueta } from 'dashboard/composables/useNomeDaEtiqueta';

defineProps({
  titulo: { type: String, required: true },
});

const { ligada, nomeDe } = useNomeDaEtiqueta();
</script>

<template>
  <div v-if="ligada" class="flex flex-col gap-1 min-w-0">
    <span class="text-body-main text-n-slate-12 break-words">
      {{ nomeDe(titulo) }}
    </span>
    <code class="self-start text-label-small text-n-slate-11 break-all">
      {{ titulo }}
    </code>
  </div>
  <span v-else class="text-body-main text-n-slate-12">
    {{ titulo }}
  </span>
</template>
