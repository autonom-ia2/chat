<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// #1385 — quem recebe, com três clientes de exemplo: o rodízio pela equipe, ou uma frase só quando é sempre a mesma
// pessoa (ou falta escolher, que o erro já mostra à esquerda).
const props = defineProps({
  regra: { type: Object, required: true },
  fila: { type: Array, default: () => [] },
  pessoa: { type: String, default: '' },
});

const { t } = useI18n();
const P = 'CRM_KANBAN.PASSAGEM.PREVIA';
const CLIENTES = ['CLIENTE', 'CLIENTE_2', 'CLIENTE_3'];

const sempreAMesma = computed(() => props.regra.pool_type === 'user');
const linhas = computed(() =>
  CLIENTES.map((chave, indice) => ({
    chave,
    cliente: t(`${P}.${chave}`),
    recebe:
      props.fila[indice % Math.max(props.fila.length, 1)] || t(`${P}.ALGUEM`),
  }))
);
</script>

<template>
  <section
    class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4"
  >
    <h3 class="mb-0 text-sm font-semibold text-n-slate-12">
      {{ t(`${P}.FILA_TITULO`) }}
    </h3>
    <p
      v-if="sempreAMesma"
      class="mb-0 flex items-center gap-2 rounded-xl bg-n-alpha-1 px-3 py-3 text-[0.9375rem] text-n-slate-12"
    >
      <span
        class="i-lucide-user-round size-4 shrink-0 text-n-slate-11"
        aria-hidden="true"
      />
      {{
        pessoa ? t(`${P}.FILA_PESSOA`, { nome: pessoa }) : t(`${P}.FILA_FALTA`)
      }}
    </p>
    <template v-else>
      <ol class="m-0 flex list-none flex-col gap-2 p-0">
        <li
          v-for="linha in linhas"
          :key="linha.chave"
          class="flex items-center gap-3 rounded-xl bg-n-alpha-1 px-3 py-2 text-[0.9375rem] text-n-slate-12"
        >
          <span class="min-w-0 flex-1 truncate">{{ linha.cliente }}</span>
          <span
            class="i-lucide-arrow-right size-4 shrink-0 text-n-slate-10 rtl:rotate-180"
            aria-hidden="true"
          />
          <span class="min-w-0 flex-1 truncate font-semibold">{{
            linha.recebe
          }}</span>
        </li>
      </ol>
      <p class="mb-0 text-sm text-n-slate-11">
        {{
          t(
            regra.mode === 'direct'
              ? `${P}.FILA_EQUIPE_NOME`
              : `${P}.FILA_EQUIPE`
          )
        }}
      </p>
    </template>
  </section>
</template>
