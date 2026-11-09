<script setup>
import { useI18n } from 'vue-i18n';
import AgenteBotao from '../../components/AgenteBotao.vue';
import { ferramentaPorId } from '../catalogo';

// #2776 J6 — no Confira do Construtor: as ferramentas da vitrine que o Construtor escolheu, pelo sentido do que a
// pessoa contou, para o agente já nascer com elas. Mostrar antes de fazer: cada uma com ícone e uma linha, e "Tirar".
// Só entra aqui ferramenta que não pede nada da pessoa (a chave é da plataforma); a que precisaria de chave dela fica
// como sugestão na página do agente. Lista vazia (o Construtor disse "nenhuma combina"): o bloco não aparece.
defineProps({
  nome: { type: String, required: true },
  ids: { type: Array, required: true },
});

const emit = defineEmits(['tirar', 'verMais']);

const NS = 'AGENTS.VITRINE';
const { t } = useI18n();
const texto = (id, campo) => t(`${NS}.FERRAMENTAS.${id}.${campo}`);
const icone = id => ferramentaPorId(id)?.icone || 'i-lucide-wrench';
</script>

<template>
  <section
    v-if="ids.length"
    data-ja-vem
    aria-labelledby="ja-vem-titulo"
    class="flex flex-col gap-3 p-4 rounded-2xl bg-n-solid-2 ring-1 ring-inset ring-n-weak"
  >
    <div class="flex flex-col gap-0.5">
      <h3
        id="ja-vem-titulo"
        class="flex items-center gap-2 m-0 text-base font-semibold text-n-slate-12"
      >
        <span
          class="i-lucide-package-check size-5 text-n-blue-11"
          aria-hidden="true"
        />
        {{ t(`${NS}.JA_VEM.TITULO`, { nome }) }}
      </h3>
      <p class="m-0 text-sm text-n-slate-11">
        {{ t(`${NS}.JA_VEM.TEXTO`) }}
      </p>
    </div>
    <ul class="flex flex-col gap-1 p-0 m-0 list-none">
      <li
        v-for="id in ids"
        :key="id"
        :data-ja-vem-item="id"
        class="flex items-center gap-3 py-1"
      >
        <span
          aria-hidden="true"
          class="grid rounded-lg place-items-center size-9 shrink-0 bg-n-blue-3 text-n-blue-11"
        >
          <span :class="icone(id)" class="size-5" />
        </span>
        <span class="flex flex-col flex-1 min-w-0">
          <span class="text-sm font-semibold text-n-slate-12">
            {{ texto(id, 'NOME') }}
          </span>
          <span class="text-sm text-n-slate-11 line-clamp-1">
            {{ texto(id, 'CONSEGUE') }}
          </span>
        </span>
        <button
          type="button"
          data-ja-vem-tirar
          :aria-label="
            t(`${NS}.JA_VEM.TIRAR_SR`, { ferramenta: texto(id, 'NOME') })
          "
          class="px-3 text-sm font-medium rounded-lg min-h-11 text-n-ruby-11 hover:bg-n-ruby-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
          @click="emit('tirar', id)"
        >
          {{ t(`${NS}.JA_VEM.TIRAR`) }}
        </button>
      </li>
    </ul>
    <AgenteBotao
      data-ja-vem-mais
      variante="fantasma"
      icone="i-lucide-package-open"
      class="self-start"
      @click="emit('verMais')"
    >
      {{ t(`${NS}.JA_VEM.VER_MAIS`) }}
    </AgenteBotao>
  </section>
</template>
