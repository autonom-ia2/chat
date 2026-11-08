<script setup>
import { computed } from 'vue';
import { useNumerosFormato } from '../useNumerosFormato';
import { GERENCIADOR_DA_META } from './destinosOrigens';

// Números › Origens (#2001, F6) — pergunta 4: "Quantos tocaram no anúncio e não mandaram mensagem?". Toque não é pessoa (a
// mesma pessoa toca duas vezes), então a frase compara toques com clientes novos e não promete nomes: a Meta
// só diz quem foi quando a pessoa escreve. Só com gasto conectado (os toques vêm da Meta).
// Ação única: mudar a mensagem de boas-vindas, que se muda na Meta (outra aba).
const props = defineProps({
  toques: { type: Number, required: true },
  clientes: { type: Number, required: true },
});

const O = 'CRM_NUMEROS_ORIGENS';
const { t } = useNumerosFormato();
const frase = computed(() =>
  t(
    `${O}.NAO_MANDARAM.FRASE`,
    { toques: props.toques, n: props.clientes },
    props.clientes
  )
);
</script>

<template>
  <section
    data-origens-bloco="nao-mandaram"
    aria-labelledby="origens-nao-mandaram"
    class="flex flex-col gap-3"
  >
    <h2
      id="origens-nao-mandaram"
      class="mb-0 text-base font-semibold text-n-slate-12"
    >
      {{ t(`${O}.NAO_MANDARAM.TITULO`) }}
    </h2>
    <div
      class="flex flex-col gap-2 rounded-xl bg-n-solid-1 p-4 ring-1 ring-inset ring-n-weak"
    >
      <p
        data-nao-mandaram
        :data-toques="toques"
        :data-clientes="clientes"
        class="mb-0 text-base font-medium text-n-slate-12"
      >
        {{ frase }}
      </p>
      <p class="mb-0 text-sm text-n-slate-11">
        {{ t(`${O}.NAO_MANDARAM.EXPLICA`) }}
      </p>
      <a
        :href="GERENCIADOR_DA_META"
        target="_blank"
        rel="noopener noreferrer"
        class="inline-flex min-h-11 w-fit items-center gap-1.5 text-sm font-medium text-n-blue-11 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      >
        {{ t(`${O}.NAO_MANDARAM.VER`) }}
        <span class="i-lucide-external-link size-4" aria-hidden="true" />
        <span class="sr-only">{{ t(`${O}.NOVA_ABA`) }}</span>
      </a>
    </div>
  </section>
</template>
