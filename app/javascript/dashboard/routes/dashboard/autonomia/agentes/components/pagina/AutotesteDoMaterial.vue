<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteBotao from '../AgenteBotao.vue';

// #1426 (tema 4b) — o autoteste: até 10 perguntas, 8 tiradas do material e 2 de fora dele (nessas,
// o certo é dizer que não sabe e passar para a equipe). Roda sozinho quando a base muda e quando a
// pessoa pede ("Testar de novo"). Em palavras: quantas acertou, sem nota nem percentual. A lista das
// perguntas fica recolhida; quem quer, abre.
const props = defineProps({
  autoteste: { type: Object, required: true },
  nome: { type: String, required: true },
  podeGerenciar: { type: Boolean, default: false },
});

const emit = defineEmits(['testarDeNovo']);

const { t } = useI18n();
const NS = 'AGENTS.JORNADA.PAGINA.MATERIAL.AUTOTESTE';

const rodando = computed(() => props.autoteste.estado === 'rodando');
const foraOk = computed(
  () => props.autoteste.certasDeFora === props.autoteste.deFora
);
</script>

<template>
  <section
    data-autoteste
    :data-estado="autoteste.estado"
    class="flex flex-col gap-2 p-4 rounded-2xl bg-n-slate-2 ring-1 ring-inset ring-n-weak"
  >
    <h3 class="m-0 text-sm font-semibold text-n-slate-12">
      {{ t(`${NS}.TITULO`) }}
    </h3>
    <p
      role="status"
      aria-live="polite"
      class="flex items-start gap-2 m-0 text-sm text-n-slate-12"
    >
      <span
        v-if="rodando"
        aria-hidden="true"
        class="mt-0.5 border-2 rounded-full size-4 shrink-0 border-n-slate-7 border-t-n-blue-11 motion-safe:animate-spin"
      />
      <span v-if="rodando">
        {{
          t(`${NS}.RODANDO`, {
            nome,
            feitas: autoteste.feitas,
            total: autoteste.total,
          })
        }}
      </span>
      <span v-else data-resultado>
        {{
          t(`${NS}.ACERTOU`, {
            nome,
            certas: autoteste.certasDoMaterial,
            total: autoteste.doMaterial,
          })
        }}
      </span>
    </p>
    <p
      v-if="rodando && autoteste.quando === 'base_mudou'"
      class="m-0 text-xs text-n-slate-11"
    >
      {{ t(`${NS}.BASE_MUDOU`) }}
    </p>
    <p
      v-if="!rodando"
      data-fora
      class="m-0 text-sm"
      :class="foraOk ? 'text-n-slate-11' : 'text-n-amber-11'"
    >
      {{
        foraOk
          ? t(`${NS}.FORA_OK`, { nome, n: autoteste.deFora })
          : t(`${NS}.FORA_ERRO`, { nome })
      }}
    </p>
    <details v-if="!rodando && autoteste.resultados.length" data-perguntas>
      <summary
        class="text-sm font-semibold cursor-pointer min-h-11 flex items-center text-n-blue-11"
      >
        {{ t(`${NS}.VER`, { n: autoteste.total }) }}
      </summary>
      <ul class="flex flex-col gap-1 p-0 m-0 list-none">
        <li
          v-for="item in autoteste.resultados"
          :key="item.pergunta"
          class="flex items-start gap-2 text-sm text-n-slate-12"
        >
          <span
            aria-hidden="true"
            class="mt-0.5 size-4 shrink-0"
            :class="
              item.ok
                ? 'i-lucide-check text-n-teal-11'
                : 'i-lucide-x text-n-ruby-11'
            "
          />
          <span class="grow">
            {{ item.pergunta }}
            <span
              class="inline-block px-1.5 ms-1 text-xs rounded-md whitespace-nowrap bg-n-slate-3 text-n-slate-11"
            >
              {{
                item.origem === 'fora'
                  ? t(`${NS}.DE_FORA`)
                  : t(`${NS}.DO_MATERIAL`)
              }}
            </span>
            <span class="sr-only">
              {{ item.ok ? t(`${NS}.CERTA`) : t(`${NS}.ERRADA`) }}
            </span>
          </span>
        </li>
      </ul>
    </details>
    <AgenteBotao
      v-if="podeGerenciar && !rodando"
      data-testar-de-novo
      class="self-start -ms-4"
      variante="fantasma"
      icone="i-lucide-refresh-cw"
      @click="emit('testarDeNovo')"
    >
      {{ t(`${NS}.DE_NOVO`) }}
    </AgenteBotao>
  </section>
</template>
