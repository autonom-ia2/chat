<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteBotao from '../AgenteBotao.vue';
import AgenteErro from '../AgenteErro.vue';
import AjudantePassos from './AjudantePassos.vue';
import ResumoAjuda from './ResumoAjuda.vue';

// Tema 14 (#1434) — as partes do ajudante na página "Criar agente" (AgenteCriarPage), fora dela para a página
// não crescer. `ajuda` é o useAjudanteNaCriacao da página (estado e ações); `parte` diz o trecho:
// - passos: a página inteira antes da conversa ("Quem {nome} vai ajudar?" e "Quando chamar {nome}?");
// - topo: "Quem {nome} ajuda" acima da conversa, com "Alterar", o erro de gravar e o bloqueio sem a Fase 2;
// - pronto: "Quem {nome} ajuda" no Pronto (`principais`: quem ficou gravado).
const props = defineProps({
  parte: {
    type: String,
    required: true,
    validator: v => ['passos', 'topo', 'pronto'].includes(v),
  },
  ajuda: { type: Object, required: true },
  nome: { type: String, required: true },
  semNome: { type: Boolean, default: false },
  agenteId: { type: Number, default: null },
  principais: { type: Array, default: () => [] },
});

const { t } = useI18n();
const NS = 'AGENTS.JORNADA.AJUDANTE';

const titulo = computed(() =>
  props.semNome
    ? t(`${NS}.QUEM_AJUDA_SEM_NOME`)
    : t(`${NS}.QUEM_AJUDA`, { nome: props.nome })
);
const ocupado = computed(
  () => props.ajuda.salvando.value || props.ajuda.comecando.value
);
const erro = computed(() => props.ajuda.erro.value);
</script>

<template>
  <div
    v-if="parte === 'passos'"
    data-criar-ajuda
    class="flex flex-col w-full max-w-3xl gap-6 px-4 py-6 mx-auto md:px-6"
  >
    <button
      type="button"
      data-voltar-lista
      class="inline-flex items-center gap-1 text-sm font-semibold min-h-11 w-fit text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
      @click="ajuda.sair()"
    >
      <span
        class="i-lucide-arrow-left size-4 rtl:rotate-180"
        aria-hidden="true"
      />
      {{ t('AGENTS.JORNADA.CRIAR.VOLTAR') }}
    </button>
    <p class="m-0 text-sm font-semibold text-n-slate-11">
      {{ t('AGENTS.JORNADA.CRIAR.TITULO') }}
    </p>
    <AjudantePassos
      :nome="semNome ? '' : nome"
      :sem-nome="semNome"
      :agente-id="agenteId"
      :agentes="ajuda.agentes.value"
      :leitura="ajuda.leitura.value"
      :inicial="ajuda.inicial.value"
      :texto-final="t('AGENTS.JORNADA.EQUIPE.CONTINUAR')"
      @voltar="ajuda.voltar()"
      @reler="ajuda.carregarAgentes()"
      @pronto="ajuda.escolher"
    />
  </div>

  <section
    v-else-if="parte === 'pronto'"
    data-ajuda-pronto
    aria-labelledby="ajuda-pronto-titulo"
    class="flex flex-col gap-4 p-5 shadow-sm rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak"
  >
    <h2
      id="ajuda-pronto-titulo"
      class="m-0 text-base font-semibold text-n-slate-12"
    >
      {{ t(`${NS}.QUEM_AJUDA`, { nome }) }}
    </h2>
    <ResumoAjuda :principais="principais" :quando="ajuda.quando.value" />
  </section>

  <template v-else>
    <section
      data-ajuda-criacao
      :aria-label="titulo"
      class="flex items-start gap-3 p-4 shadow-sm rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak"
    >
      <div class="flex flex-col flex-1 min-w-0 gap-2">
        <h2 class="m-0 text-sm font-semibold text-n-slate-11">
          {{ titulo }}
        </h2>
        <ResumoAjuda
          :principais="ajuda.principais.value"
          :quando="ajuda.quando.value"
        />
      </div>
      <AgenteBotao
        v-if="!ocupado && !ajuda.bloqueado.value"
        data-alterar-ajuda
        variante="fantasma"
        class="shrink-0"
        :aria-label="t(`${NS}.MUDAR_ARIA`, { nome })"
        @click="ajuda.alterar()"
      >
        {{ t('AGENTS.JORNADA.PAGINA.ALTERAR') }}
      </AgenteBotao>
    </section>
    <AgenteErro
      v-if="ajuda.bloqueado.value"
      data-ajuda-bloqueado
      tom="ambar"
      :titulo="t(`${NS}.SEM_FASE2`, { nome })"
      :garantia="t(`${NS}.SEM_FASE2_GARANTIA`)"
    />
    <AgenteErro
      v-else-if="erro"
      data-erro-ajuda
      :titulo="erro.titulo"
      :garantia="erro.garantia"
      :acao="t(`${NS}.ESCOLHER_DE_NOVO`)"
      icone-acao="i-lucide-list"
      @acao="ajuda.alterar()"
    />
  </template>
</template>
