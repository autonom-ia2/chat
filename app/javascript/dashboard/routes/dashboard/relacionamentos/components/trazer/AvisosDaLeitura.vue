<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// #2896, Fatia 2 — o que a pessoa precisa saber sobre a leitura antes de seguir,
// dito como alerta no topo da tela (do conferir e da pergunta a que ela voltou):
//   - `aviso`: o servidor desfez a última mudança, porque com ela não sobraria
//     ninguém. Vem na leitura até a próxima escrita que dê certo;
//   - `mudou`: a lista mudou por fora (outra aba, outra pessoa da conta) e a
//     tela já mostra como ela está agora.
// Aviso que a tela não conhece não vira frase.
const props = defineProps({
  aviso: { type: String, default: '' },
  mudou: { type: Boolean, default: false },
});

const { t } = useI18n();
const MUDANCA_DESFEITA = 'mudanca_desfeita';

const frases = computed(() =>
  [
    {
      nome: 'mudanca-desfeita',
      vale: props.aviso === MUDANCA_DESFEITA,
      chave: 'RELACIONAMENTOS_TRAZER.CONFERIR.MUDANCA_DESFEITA',
    },
    {
      nome: 'lista-mudou',
      vale: props.mudou,
      chave: 'RELACIONAMENTOS_TRAZER.CONFERIR.MUDOU',
    },
  ].filter(frase => frase.vale)
);
</script>

<template>
  <p
    v-for="frase in frases"
    :key="frase.nome"
    :data-relacionamentos="frase.nome"
    role="alert"
    class="flex items-start gap-2 p-4 m-0 text-base rounded-xl bg-n-alpha-2 text-n-slate-12"
  >
    <span
      class="mt-0.5 i-lucide-info size-5 shrink-0 text-n-slate-11"
      aria-hidden="true"
    />
    {{ t(frase.chave) }}
  </p>
</template>
