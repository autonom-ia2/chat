<script setup>
import { computed, toRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { usePremium } from '../usePremium';

// #2858 F7 — o resumo do preço no cartão Premium: uma barrinha com uma marca por grátis do mês e uma linha com quantas
// restam e quanto custa depois. Fica dentro do botão do cartão, por isso só `span`. O detalhe completo é o
// `VitrineQuantoCusta`.
const props = defineProps({
  premium: { type: Object, required: true },
});

const NS = 'AGENTS.VITRINE.PREMIUM';
const { t } = useI18n();
const { gratis, restantes, estado, tom, marcas, preco } = usePremium(
  toRef(props, 'premium')
);

const situacao = computed(() =>
  t(`${NS}.${estado.value}`, { n: restantes.value, gratis: gratis.value })
);
const depois = computed(() =>
  t(estado.value === 'ACABARAM' ? `${NS}.AGORA` : `${NS}.DEPOIS`, {
    preco: preco.value,
  })
);
</script>

<template>
  <span
    class="flex flex-col gap-2 pt-3 border-t border-n-weak"
    data-vitrine-premium
    :data-vitrine-estado="estado"
  >
    <span class="flex gap-0.5" aria-hidden="true">
      <span
        v-for="(sobra, indice) in marcas"
        :key="indice"
        class="flex-1 h-1.5 rounded-full"
        :class="sobra ? tom.marca : 'bg-n-slate-6'"
      />
    </span>
    <!-- Sempre em duas linhas, como o rodapé dos grátis (VitrineRodapeGratis): rodapés da mesma altura na linha. -->
    <span class="flex flex-col gap-0.5">
      <span
        class="text-sm font-semibold"
        :class="tom.texto"
        data-vitrine-restantes
      >
        {{ situacao }}
      </span>
      <span class="text-sm text-n-slate-11" data-vitrine-preco>
        {{ depois }}
      </span>
    </span>
  </span>
</template>
