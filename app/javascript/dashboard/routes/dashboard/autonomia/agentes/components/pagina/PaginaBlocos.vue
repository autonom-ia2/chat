<script setup>
import { computed, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import AgenteBotao from '../AgenteBotao.vue';
import { usePermissoesDaJornada } from '../../composables/usePermissoesDaJornada';

// #1181 PR3 (protótipo T07, blocksT07) — os blocos claros da página do agente:
// - Testar: a pergunta vai para a gaveta Testar;
// - resumo com "Alterar": O que sabe, Onde e quando responde, Nome e jeito de falar;
// - Quando passa para a equipe: a frase da Atribuição e "Escolher quem recebe" só para quem pode
//   (DECISOES.md item 8); quem recebe é definido lá, de propósito.
// Agente escrito à mão troca "Mudar conversando" por "Editar instruções". Cotação mostra só onde e
// quando e leva o resto ao módulo de cotação. Interno não tem onde e quando. Quem só vê lê e testa.
const props = defineProps({
  agente: { type: Object, required: true },
  nome: { type: String, required: true },
  podeGerenciar: { type: Boolean, default: false },
  manual: { type: Boolean, default: false },
  cotacao: { type: Boolean, default: false },
  interno: { type: Boolean, default: false },
  temCanal: { type: Boolean, default: false },
  textoOnde: { type: String, default: '' },
  quantasFontes: { type: Number, default: 0 },
  quantasPerguntas: { type: Number, default: 0 },
});

const emit = defineEmits([
  'perguntar',
  'abrir',
  'mudar',
  'escrever',
  'escolherCanal',
]);

const { t } = useI18n();
const router = useRouter();
const { podeEscolherQuemRecebe, crmLigado } = usePermissoesDaJornada();
const NS = 'AGENTS.JORNADA.PAGINA';
const base = `blocos-${useId()}`;
const pergunta = ref('');

const linkQuemRecebe = computed(
  () => router.resolve({ name: 'crm_handoff_settings_index' }).href
);
const linkCotacao = computed(
  () => router.resolve({ name: 'autonomia_insurance_agent' }).href
);

const perguntar = () => {
  const texto = pergunta.value.trim();
  if (!texto) return;
  pergunta.value = '';
  emit('perguntar', texto);
};

const textoSabe = computed(
  () =>
    props.agente.knowledge_summary ||
    t(`${NS}.BLOCO_SABE.TEXTO`, { nome: props.nome })
);
</script>

<template>
  <div class="flex flex-col gap-4">
    <section
      v-if="!cotacao"
      data-bloco="testar"
      :aria-labelledby="`${base}-testar`"
      class="flex flex-col gap-3 p-5 shadow-sm rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak dark:ring-n-slate-6"
    >
      <div class="flex items-start gap-3">
        <span
          class="grid rounded-lg place-items-center size-9 shrink-0 bg-n-alpha-2"
          aria-hidden="true"
        >
          <span class="i-lucide-flask-conical size-5 text-n-slate-11" />
        </span>
        <div class="flex flex-col flex-1 min-w-0 gap-1">
          <h2
            :id="`${base}-testar`"
            class="m-0 text-base font-semibold text-n-slate-12"
          >
            {{ t(`${NS}.BLOCO_TESTAR.TITULO`) }}
          </h2>
          <p class="m-0 text-sm text-n-slate-11">
            {{ t(`${NS}.BLOCO_TESTAR.TEXTO`) }}
          </p>
        </div>
      </div>
      <form class="flex flex-col gap-2 sm:flex-row" @submit.prevent="perguntar">
        <label :for="`${base}-pergunta`" class="sr-only">
          {{ t(`${NS}.BLOCO_TESTAR.PERGUNTE`, { nome }) }}
        </label>
        <input
          :id="`${base}-pergunta`"
          v-model="pergunta"
          data-pergunta
          autocomplete="off"
          :placeholder="t(`${NS}.BLOCO_TESTAR.PERGUNTE`, { nome })"
          class="flex-1 min-w-0 px-3 text-base rounded-xl min-h-12 bg-n-solid-1 ring-1 ring-inset ring-n-slate-7 border-0 !mb-0 text-n-slate-12 placeholder:text-n-slate-10"
        />
        <AgenteBotao
          type="submit"
          data-perguntar
          variante="contorno"
          tamanho="lg"
          class="w-full sm:w-auto"
        >
          {{ t(`${NS}.BLOCO_TESTAR.ENVIAR`) }}
        </AgenteBotao>
      </form>
    </section>

    <section
      data-bloco="resumo"
      :aria-label="t(`${NS}.RESUMO`, { nome })"
      class="flex flex-col shadow-sm divide-y rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak dark:ring-n-slate-6 divide-n-weak"
    >
      <div
        v-if="!cotacao"
        data-linha="sabe"
        role="group"
        :aria-labelledby="`${base}-sabe`"
        class="flex flex-col gap-3 p-5 sm:flex-row sm:items-start"
      >
        <div class="flex items-start flex-1 min-w-0 gap-3">
          <span
            class="grid rounded-lg place-items-center size-9 shrink-0 bg-n-alpha-2"
            aria-hidden="true"
          >
            <span class="i-lucide-book-open size-5 text-n-slate-11" />
          </span>
          <div class="flex flex-col flex-1 min-w-0 gap-1">
            <h3
              :id="`${base}-sabe`"
              class="m-0 text-sm font-semibold text-n-slate-11"
            >
              {{ t(`${NS}.BLOCO_SABE.TITULO`) }}
            </h3>
            <p class="m-0 text-sm text-n-slate-12">{{ textoSabe }}</p>
            <p class="flex items-center gap-1 m-0 text-sm text-n-slate-11">
              <span
                :class="
                  quantasFontes
                    ? 'i-lucide-file-text'
                    : 'i-lucide-message-circle'
                "
                class="size-4 shrink-0"
                aria-hidden="true"
              />
              {{
                quantasFontes
                  ? t(
                      `${NS}.BLOCO_SABE.N_FONTES`,
                      { n: quantasFontes },
                      quantasFontes
                    )
                  : t(`${NS}.BLOCO_SABE.SO_CONVERSA`)
              }}
            </p>
            <p
              v-if="podeGerenciar && quantasPerguntas"
              data-perguntas-para-conferir
              class="flex items-center gap-1.5 px-2.5 py-1 m-0 text-sm font-medium rounded-lg w-fit bg-n-amber-2 ring-1 ring-inset ring-n-amber-6 text-n-slate-12"
            >
              <span
                class="i-lucide-info size-4 shrink-0 text-n-amber-11"
                aria-hidden="true"
              />
              {{
                t(
                  `${NS}.BLOCO_SABE.N_PERGUNTAS`,
                  { n: quantasPerguntas },
                  quantasPerguntas
                )
              }}
            </p>
          </div>
        </div>
        <AgenteBotao
          data-alterar="sabe"
          class="max-sm:w-full max-sm:ring-1 max-sm:ring-inset max-sm:ring-n-blue-9 shrink-0"
          variante="fantasma"
          :aria-label="
            podeGerenciar
              ? t(`${NS}.BLOCO_SABE.ALTERAR_ARIA`)
              : t(`${NS}.BLOCO_SABE.VER_ARIA`)
          "
          @click="emit('abrir', 'sabe')"
        >
          {{ podeGerenciar ? t(`${NS}.ALTERAR`) : t(`${NS}.VER`) }}
        </AgenteBotao>
      </div>

      <div
        v-if="!interno"
        data-linha="onde"
        role="group"
        :aria-labelledby="`${base}-onde`"
        class="flex flex-col gap-3 p-5 sm:flex-row sm:items-start"
      >
        <div class="flex items-start flex-1 min-w-0 gap-3">
          <span
            class="grid rounded-lg place-items-center size-9 shrink-0 bg-n-alpha-2"
            aria-hidden="true"
          >
            <span class="i-lucide-map-pin size-5 text-n-slate-11" />
          </span>
          <div class="flex flex-col flex-1 min-w-0 gap-1">
            <h3
              :id="`${base}-onde`"
              class="m-0 text-sm font-semibold text-n-slate-11"
            >
              {{ t(`${NS}.BLOCO_ONDE.TITULO`) }}
            </h3>
            <p class="m-0 text-sm text-n-slate-12">
              {{ temCanal ? textoOnde : t(`${NS}.NENHUM_CANAL`) }}
            </p>
          </div>
        </div>
        <template v-if="podeGerenciar">
          <AgenteBotao
            v-if="temCanal"
            data-alterar="onde"
            class="max-sm:w-full max-sm:ring-1 max-sm:ring-inset max-sm:ring-n-blue-9 shrink-0"
            variante="fantasma"
            :aria-label="t(`${NS}.BLOCO_ONDE.ALTERAR_ARIA`)"
            @click="emit('abrir', 'onde')"
          >
            {{ t(`${NS}.ALTERAR`) }}
          </AgenteBotao>
          <AgenteBotao
            v-else
            data-escolher-canal
            class="max-sm:w-full max-sm:ring-1 max-sm:ring-inset max-sm:ring-n-blue-9 shrink-0"
            variante="contorno"
            @click="emit('escolherCanal')"
          >
            {{ t(`${NS}.BLOCO_ONDE.ESCOLHER_CANAL`) }}
          </AgenteBotao>
        </template>
      </div>

      <div
        v-if="!cotacao"
        data-linha="jeito"
        role="group"
        :aria-labelledby="`${base}-jeito`"
        class="flex flex-col gap-3 p-5 sm:flex-row sm:items-start"
      >
        <div class="flex items-start flex-1 min-w-0 gap-3">
          <span
            class="grid rounded-lg place-items-center size-9 shrink-0 bg-n-alpha-2"
            aria-hidden="true"
          >
            <span class="i-lucide-smile size-5 text-n-slate-11" />
          </span>
          <div class="flex flex-col flex-1 min-w-0 gap-1">
            <h3
              :id="`${base}-jeito`"
              class="m-0 text-sm font-semibold text-n-slate-11"
            >
              {{ t(`${NS}.BLOCO_JEITO.TITULO`) }}
            </h3>
            <p class="m-0 text-sm text-n-slate-12">
              {{ t(`${NS}.BLOCO_JEITO.TEXTO`, { nome }) }}
            </p>
            <p
              v-if="manual"
              class="flex items-center gap-1 m-0 text-sm text-n-slate-11"
            >
              <span
                class="i-lucide-pencil size-4 shrink-0"
                aria-hidden="true"
              />
              {{ t(`${NS}.BLOCO_JEITO.MANUAL`) }}
            </p>
          </div>
        </div>
        <template v-if="podeGerenciar">
          <AgenteBotao
            v-if="manual"
            data-alterar="instrucoes"
            class="max-sm:w-full max-sm:ring-1 max-sm:ring-inset max-sm:ring-n-blue-9 shrink-0"
            variante="fantasma"
            @click="emit('escrever')"
          >
            {{ t(`${NS}.EDITAR_INSTRUCOES`) }}
          </AgenteBotao>
          <AgenteBotao
            v-else
            data-alterar="jeito"
            class="max-sm:w-full max-sm:ring-1 max-sm:ring-inset max-sm:ring-n-blue-9 shrink-0"
            variante="fantasma"
            :aria-label="t(`${NS}.BLOCO_JEITO.ALTERAR_ARIA`)"
            @click="emit('mudar', 'jeito')"
          >
            {{ t(`${NS}.ALTERAR`) }}
          </AgenteBotao>
        </template>
      </div>
    </section>

    <section
      v-if="cotacao"
      data-bloco="cotacao"
      :aria-labelledby="`${base}-cotacao`"
      class="flex flex-col items-start gap-3 p-5 shadow-sm rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak dark:ring-n-slate-6"
    >
      <h2
        :id="`${base}-cotacao`"
        class="m-0 text-base font-semibold text-n-slate-12"
      >
        {{ t(`${NS}.BLOCO_COTACAO.TITULO`) }}
      </h2>
      <p class="m-0 text-sm text-n-slate-11">
        {{ t(`${NS}.BLOCO_COTACAO.TEXTO`, { nome }) }}
      </p>
      <a
        data-abrir-cotacao
        :href="linkCotacao"
        class="inline-flex items-center gap-1 text-sm font-semibold underline min-h-11 text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
      >
        {{ t(`${NS}.BLOCO_COTACAO.ABRIR`) }}
        <span
          class="i-lucide-arrow-right size-4 rtl:rotate-180"
          aria-hidden="true"
        />
      </a>
    </section>

    <section
      v-else
      data-bloco="passa"
      :aria-labelledby="`${base}-passa`"
      class="flex flex-col gap-3 p-5 shadow-sm rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak dark:ring-n-slate-6"
    >
      <div class="flex items-start gap-3">
        <span
          class="grid rounded-lg place-items-center size-9 shrink-0 bg-n-alpha-2"
          aria-hidden="true"
        >
          <span class="i-lucide-users size-5 text-n-slate-11" />
        </span>
        <div class="flex flex-col flex-1 min-w-0 gap-1">
          <h2
            :id="`${base}-passa`"
            class="m-0 text-base font-semibold text-n-slate-12"
          >
            {{ t(`${NS}.BLOCO_PASSA.TITULO`) }}
          </h2>
          <p class="m-0 text-sm text-n-slate-11">
            {{ t(`${NS}.BLOCO_PASSA.TEXTO`, { nome }) }}
          </p>
        </div>
      </div>
      <a
        v-if="podeEscolherQuemRecebe"
        data-quem-recebe
        :href="linkQuemRecebe"
        target="_blank"
        rel="noopener noreferrer"
        class="inline-flex items-center gap-1 text-sm font-semibold underline min-h-11 w-fit text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
      >
        {{ t('AGENTS.JORNADA.ONDE_QUANDO.ESCOLHER_QUEM_RECEBE') }}
        <span class="i-lucide-external-link size-4" aria-hidden="true" />
        <span class="sr-only">{{ t('AGENTS.JORNADA.COMUM.NOVA_ABA') }}</span>
      </a>
      <p
        v-else-if="crmLigado"
        data-sem-permissao
        class="m-0 text-sm text-n-slate-11"
      >
        {{ t('AGENTS.JORNADA.ONDE_QUANDO.QUEM_RECEBE_SEM_PERMISSAO') }}
      </p>
      <p v-if="podeGerenciar" class="m-0 text-sm text-n-slate-11">
        {{
          manual
            ? t(`${NS}.BLOCO_PASSA.MANUAL`, { nome })
            : t(`${NS}.BLOCO_PASSA.MUDAR`, { nome })
        }}
      </p>
    </section>
  </div>
</template>
