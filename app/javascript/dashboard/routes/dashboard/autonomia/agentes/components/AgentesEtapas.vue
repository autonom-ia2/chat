<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// #1181 (protótipo stepper) — as etapas da criação: Conte · Confira · Comece. `atual` vai de 1 a 3;
// 4 = tudo feito (T06). Mostra onde a pessoa está (aria-current="step"); não é navegação. Nome da
// etapa sempre em slate 12 (o check colorido só reforça), para não reprovar no contraste. No
// celular vira uma linha: bolinhas + "Etapa N de 3 · Nome".
const props = defineProps({
  atual: {
    type: Number,
    required: true,
    validator: v => v >= 1 && v <= 4,
  },
});

const { t } = useI18n();

const NOMES = ['CONTE', 'CONFIRA', 'COMECE'];
const NS = 'AGENTS.JORNADA.CRIAR.ETAPAS';

const passos = computed(() =>
  NOMES.map((chave, indice) => {
    const numero = indice + 1;
    let estado = '';
    if (numero < props.atual) estado = 'feito';
    else if (numero === props.atual) estado = 'agora';
    return { chave, numero, estado, nome: t(`${NS}.${chave}`) };
  })
);

const compacto = computed(() => {
  if (props.atual > NOMES.length) return t(`${NS}.PRONTO`);
  return t(`${NS}.COMPACTO`, {
    n: props.atual,
    nome: t(`${NS}.${NOMES[props.atual - 1]}`),
  });
});
</script>

<template>
  <div>
    <ol
      :aria-label="t(`${NS}.ROTULO`)"
      class="items-center hidden gap-2 p-0 m-0 list-none md:flex"
    >
      <template v-for="(passo, indice) in passos" :key="passo.chave">
        <li
          v-if="indice > 0"
          aria-hidden="true"
          class="w-8 h-0.5 rounded-full"
          :class="passo.numero <= atual ? 'bg-n-teal-9' : 'bg-n-slate-6'"
        />
        <li
          data-etapa
          :data-estado="passo.estado"
          :aria-current="passo.estado === 'agora' ? 'step' : undefined"
          class="flex items-center gap-2"
        >
          <span
            aria-hidden="true"
            class="grid text-xs font-bold rounded-full place-items-center size-6 shrink-0"
            :class="{
              'bg-n-teal-9 text-white dark:text-n-slate-1':
                passo.estado === 'feito',
              'bg-n-blue-11 text-white dark:text-n-slate-1':
                passo.estado === 'agora',
              'bg-n-slate-3 text-n-slate-12 ring-1 ring-inset ring-n-slate-7':
                !passo.estado,
            }"
          >
            <span
              v-if="passo.estado === 'feito'"
              class="i-lucide-check size-3.5"
            />
            <template v-else>{{ passo.numero }}</template>
          </span>
          <span
            data-nome
            class="text-sm text-n-slate-12"
            :class="passo.estado === 'agora' ? 'font-semibold' : 'font-medium'"
          >
            {{ passo.nome }}
          </span>
          <span v-if="passo.estado === 'feito'" class="sr-only">
            {{ t(`${NS}.FEITO`) }}
          </span>
        </li>
      </template>
    </ol>
    <p
      data-compacto
      class="flex items-center gap-2.5 m-0 text-sm font-medium md:hidden text-n-slate-12"
    >
      <span aria-hidden="true" class="flex gap-1.5">
        <span
          v-for="passo in passos"
          :key="passo.chave"
          class="rounded-full size-2.5"
          :class="{
            'bg-n-teal-9': passo.estado === 'feito',
            'bg-n-blue-11': passo.estado === 'agora',
            'bg-n-slate-6': !passo.estado,
          }"
        />
      </span>
      {{ compacto }}
    </p>
  </div>
</template>
