<script setup>
import { computed } from 'vue';
import { P } from './numerosTextos';
import { useNumerosFormato } from './useNumerosFormato';

// "A IA te ajudou" (#1871): o único lugar em que quem vende ou atende vê o
// valor da IA, porque essa pessoa não abre o módulo Agentes.
const props = defineProps({
  ajuda: { type: Object, required: true },
  destino: { type: Object, default: null },
});

const { t } = useNumerosFormato();

// Sem o nome (mais de uma IA passou), "A IA". Quem atende vê só o que a IA passou: "resolveu sozinha" é
// a conta única da IA, na F5.
const texto = computed(() => {
  const { tipo, passou, viraram } = props.ajuda;
  const params = { ia: props.ajuda.ia || t(`${P}.IA_AJUDOU.IA`), passou };
  if (tipo !== 'venda') return t(`${P}.IA_AJUDOU.ATENDE`, params, passou);
  const viraramTexto = t(`${P}.IA_AJUDOU.VIRARAM`, { n: viraram }, viraram);
  return `${t(`${P}.IA_AJUDOU.VENDA`, params, passou)} ${viraramTexto}`;
});
</script>

<template>
  <section
    data-numeros-ia-ajudou
    class="flex flex-col gap-1 rounded-xl bg-n-solid-1 px-4 py-3 ring-1 ring-inset ring-n-weak"
  >
    <h3
      class="mb-0 flex items-center gap-2 text-sm font-semibold text-n-slate-12"
    >
      <span
        class="i-lucide-sparkles size-4 text-n-iris-10"
        aria-hidden="true"
      />
      {{ t(`${P}.IA_AJUDOU.TITULO`) }}
    </h3>
    <p class="mb-0 text-sm text-n-slate-11">{{ texto }}</p>
    <RouterLink
      v-if="destino"
      :to="destino.to"
      class="inline-flex min-h-11 w-fit items-center gap-1 text-sm font-semibold text-n-blue-11 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
    >
      {{ t(`${P}.IA_AJUDOU.VER`) }}
      <span
        class="i-lucide-arrow-right size-3.5 rtl:rotate-180"
        aria-hidden="true"
      />
    </RouterLink>
  </section>
</template>
