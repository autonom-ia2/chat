<script setup>
import { useCustos } from '../helpers/useCustos';

// O tipo previsto da mensagem e o custo por envio. Divulgação diz, com todas
// as letras, quanto custa a mais que o aviso de serviço.
defineProps({
  tipo: { type: String, required: true },
});

const { emReais } = useCustos();
</script>

<template>
  <div data-custo-do-tipo class="flex flex-col gap-1">
    <span class="flex flex-wrap items-center gap-2 text-sm">
      <span
        class="px-2 py-0.5 text-xs font-medium rounded-full"
        :class="
          tipo === 'divulgacao'
            ? 'bg-n-amber-3 text-n-amber-11'
            : 'bg-n-teal-3 text-n-teal-11'
        "
      >
        {{ $t(`MODELOS_WHATSAPP.TIPOS.${tipo}.ROTULO`) }}
      </span>
      <span v-if="emReais(tipo)" class="text-n-slate-12">
        {{ $t('MODELOS_WHATSAPP.IA.POR_ENVIO', { valor: emReais(tipo) }) }}
      </span>
    </span>
    <p
      v-if="tipo === 'divulgacao' && emReais('aviso')"
      data-divulgacao-custa-mais
      class="m-0 text-sm font-medium text-n-amber-11"
    >
      {{
        $t('MODELOS_WHATSAPP.IA.DIVULGACAO_CUSTA', {
          divulgacao: emReais('divulgacao'),
          aviso: emReais('aviso'),
        })
      }}
    </p>
  </div>
</template>
