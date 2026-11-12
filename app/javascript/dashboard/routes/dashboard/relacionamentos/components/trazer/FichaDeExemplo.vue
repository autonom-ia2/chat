<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { partesDoEmail } from '../../trazer/emailEmPartes';
import SeloDeEstado from '../comum/SeloDeEstado.vue';

// #2894 — uma das três fichas de exemplo da conferência: como a pessoa vai
// ficar. Mostra só o que a planilha trouxe; o selo "Cliente" vem das respostas.
const props = defineProps({
  pessoa: { type: Object, required: true },
});

const { t } = useI18n();

const INICIAIS_MAXIMAS = 2;
const iniciais = computed(() =>
  props.pessoa.nome
    .split(' ')
    .filter(Boolean)
    .slice(0, INICIAIS_MAXIMAS)
    .map(parte => parte[0].toUpperCase())
    .join('')
);

const linhas = computed(() =>
  [
    ['i-lucide-phone', props.pessoa.telefone],
    ['i-lucide-mail', props.pessoa.email],
    ['i-lucide-building-2', props.pessoa.empresa],
  ]
    .filter(([, texto]) => texto)
    .map(([icone, texto]) => ({
      icone,
      texto,
      partes: icone === 'i-lucide-mail' ? partesDoEmail(texto) : [texto],
    }))
);
</script>

<template>
  <article
    data-ficha-de-exemplo
    class="flex flex-col gap-4 p-5 border rounded-2xl border-n-weak bg-n-solid-1"
  >
    <header class="flex items-center gap-3 min-w-0">
      <span
        class="flex items-center justify-center text-sm font-semibold rounded-full size-10 shrink-0 bg-n-iris-3 text-n-iris-11"
        aria-hidden="true"
      >
        {{ iniciais }}
      </span>
      <div class="flex flex-col items-start min-w-0 gap-1">
        <h3
          :title="pessoa.nome"
          class="m-0 text-base font-semibold break-words line-clamp-2 md:min-h-12 text-n-slate-12"
        >
          {{ pessoa.nome }}
        </h3>
        <SeloDeEstado v-if="pessoa.cliente" tom="cliente">
          {{ t('RELACIONAMENTOS.COMUM.SELO_CLIENTE') }}
        </SeloDeEstado>
      </div>
    </header>
    <ul class="flex flex-col gap-2 p-0 m-0 text-sm list-none text-n-slate-11">
      <li
        v-for="{ icone, texto, partes } in linhas"
        :key="icone"
        class="flex items-center gap-2 min-w-0"
      >
        <span class="size-4 shrink-0" :class="icone" aria-hidden="true" />
        <span class="tabular-nums break-words line-clamp-2" :title="texto">
          <template v-for="(parte, posicao) in partes" :key="posicao">
            <wbr v-if="posicao" />{{ parte }}
          </template>
        </span>
      </li>
    </ul>
  </article>
</template>
