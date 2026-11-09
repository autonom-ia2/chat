<script setup>
import { computed, nextTick, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteBotao from '../../components/AgenteBotao.vue';
import AgenteGaveta from '../../components/AgenteGaveta.vue';
import EscolhaRadio from '../../components/EscolhaRadio.vue';
import VitrineConversa from './VitrineConversa.vue';
import VitrineExperimente from './VitrineExperimente.vue';
import { dataDaBase } from '../../utils/baseDoAgente';
import { useVitrine } from '../useVitrine';

// #2776 — o detalhe de uma ferramenta pronta. Mostra antes de fazer (a conversa de exemplo e o "Experimente"), pede
// só o agente e a frase "Quando usar" já pronta, e tem UMA ação: ensinar ao agente. Quem decide quando usar é o
// agente, pelo sentido da conversa (decisão 2 do Rodrigo): a frase vai para ele como orientação, sem regra fixa.
// Depois de incluir, a própria gaveta vira a confirmação, com o caminho para ver as ferramentas do agente.
const props = defineProps({
  ferramenta: { type: Object, required: true },
  agentes: { type: Array, required: true },
  agenteInicial: { type: [Number, String], default: null },
});

const emit = defineEmits(['fechar', 'verAgente']);

const NS = 'AGENTS.VITRINE';
const { t, te, locale } = useI18n();
const vitrine = useVitrine();
const quandoId = `quando-${useId()}`;

const base = computed(() => `${NS}.FERRAMENTAS.${props.ferramenta.id}`);
// APOIO e CONSULTAS são opcionais: sem a chave, vazio.
const texto = campo =>
  te(`${base.value}.${campo}`) ? t(`${base.value}.${campo}`) : '';

const primeiroLivre = () =>
  props.agentes.find(agente => !vitrine.tem(agente.id, props.ferramenta.id))
    ?.id ?? null;

const agenteId = ref(
  props.agenteInicial &&
    props.agentes.some(a => a.id === Number(props.agenteInicial))
    ? Number(props.agenteInicial)
    : primeiroLivre()
);
// A frase pronta acompanha o idioma e o pacote da conta, que podem chegar depois de a gaveta abrir; depois que a
// pessoa mexe, vale o que ela escreveu.
const quandoEditado = ref(null);
const quando = computed({
  get: () => quandoEditado.value ?? texto('USE_QUANDO'),
  set: valor => {
    quandoEditado.value = valor;
  },
});
const erroQuando = ref('');
const incluido = ref(null);
const sucesso = ref(null);

const agenteEscolhido = computed(() =>
  props.agentes.find(agente => agente.id === agenteId.value)
);

const opcoes = computed(() =>
  props.agentes.map(agente => {
    const jaTem = vitrine.tem(agente.id, props.ferramenta.id);
    return {
      valor: agente.id,
      titulo: agente.name,
      texto: jaTem ? t(`${NS}.DETALHE.JA_TEM`) : '',
      desabilitada: jaTem,
    };
  })
);

const consultas = computed(() => texto('CONSULTAS'));
const atualizado = computed(() =>
  props.ferramenta.arquivo
    ? dataDaBase(props.ferramenta.atualizadoEm, locale.value)
    : ''
);

const ensinar = async () => {
  if (!agenteEscolhido.value) return;
  if (!quando.value.trim()) {
    erroQuando.value = t(`${NS}.DETALHE.QUANDO_VAZIO`);
    document.getElementById(quandoId)?.focus();
    return;
  }
  vitrine.incluir(agenteId.value, props.ferramenta.id, quando.value.trim());
  incluido.value = agenteEscolhido.value;
  await nextTick();
  sucesso.value?.focus();
};
</script>

<template>
  <AgenteGaveta :titulo="texto('NOME')" @fechar="emit('fechar')">
    <div
      v-if="incluido"
      ref="sucesso"
      data-vitrine-sucesso
      tabindex="-1"
      class="flex flex-col items-center gap-4 px-2 py-10 text-center outline-none"
    >
      <span
        aria-hidden="true"
        class="grid rounded-full place-items-center size-16 bg-n-teal-3 text-n-teal-11"
      >
        <span class="i-lucide-check size-8" />
      </span>
      <h3 class="m-0 text-2xl font-bold text-n-slate-12">
        {{ t(`${NS}.DETALHE.SUCESSO_TITULO`) }}
      </h3>
      <p class="max-w-sm m-0 text-base text-n-slate-12">
        {{
          t(`${NS}.DETALHE.SUCESSO_TEXTO`, {
            agente: incluido.name,
            consegue: texto('CONSEGUE'),
          })
        }}
      </p>
      <p class="max-w-sm m-0 text-sm text-n-slate-11">
        {{ t(`${NS}.DETALHE.SUCESSO_LIGADA`) }}
      </p>
    </div>

    <template v-else>
      <div class="flex items-start gap-3">
        <span
          aria-hidden="true"
          class="grid rounded-xl place-items-center size-12 shrink-0 bg-n-blue-3 text-n-blue-11"
        >
          <span :class="ferramenta.icone" class="size-6" />
        </span>
        <div class="flex flex-col gap-1">
          <p class="m-0 text-base text-n-slate-12">{{ texto('FAZ') }}</p>
          <p v-if="texto('APOIO')" class="m-0 text-sm text-n-slate-11">
            {{ texto('APOIO') }}
          </p>
        </div>
      </div>

      <section class="flex flex-col gap-3">
        <h3 class="m-0 text-base font-semibold text-n-slate-12">
          {{ t(`${NS}.DETALHE.CONSEGUE`) }}
        </h3>
        <VitrineConversa
          :cliente="texto('CLIENTE')"
          :resposta="texto('AGENTE')"
          :agente="agenteEscolhido?.name || ''"
        />
        <p v-if="consultas" class="m-0 text-sm text-n-slate-11">
          {{ t(`${NS}.DETALHE.CONSULTAS`, { lista: consultas }) }}
        </p>
        <p
          v-if="atualizado"
          data-vitrine-arquivo
          class="flex items-start gap-2 m-0 text-sm text-n-slate-11"
        >
          <span
            class="i-lucide-refresh-cw size-4 mt-0.5 shrink-0"
            aria-hidden="true"
          />
          {{ t(`${NS}.DETALHE.ARQUIVO`, { data: atualizado }) }}
        </p>
      </section>

      <VitrineExperimente
        :ferramenta-id="ferramenta.id"
        :rotulo="texto('ROTULO')"
        :exemplo="texto('EXEMPLO')"
      />

      <section class="flex flex-col gap-3">
        <h3 class="m-0 text-base font-semibold text-n-slate-12">
          {{ t(`${NS}.DETALHE.QUAL_AGENTE`) }}
        </h3>
        <EscolhaRadio
          v-model="agenteId"
          data-vitrine-agentes
          :rotulo="t(`${NS}.DETALHE.QUAL_AGENTE`)"
          :opcoes="opcoes"
        />
      </section>

      <section class="flex flex-col gap-2">
        <label :for="quandoId" class="text-base font-semibold text-n-slate-12">
          {{ t(`${NS}.DETALHE.QUANDO`) }}
        </label>
        <p :id="`${quandoId}-ajuda`" class="m-0 text-sm text-n-slate-11">
          {{ t(`${NS}.DETALHE.QUANDO_AJUDA`) }}
        </p>
        <textarea
          :id="quandoId"
          v-model="quando"
          data-vitrine-quando
          rows="3"
          :aria-describedby="`${quandoId}-ajuda`"
          :aria-invalid="erroQuando ? 'true' : undefined"
          class="w-full px-3 py-2.5 !mb-0 text-base border-0 resize-y rounded-xl bg-n-solid-1 text-n-slate-12 ring-1 ring-inset ring-n-slate-7 focus:ring-2 focus:ring-n-blue-11"
          @input="erroQuando = ''"
        />
        <p v-if="erroQuando" role="alert" class="m-0 text-sm text-n-ruby-11">
          {{ erroQuando }}
        </p>
      </section>
    </template>

    <template #rodape>
      <template v-if="incluido">
        <AgenteBotao
          data-vitrine-ver-agente
          tamanho="lg"
          bloco
          icone-direita="i-lucide-arrow-right"
          @click="emit('verAgente', incluido)"
        >
          {{ t(`${NS}.DETALHE.VER_FERRAMENTAS`, { nome: incluido.name }) }}
        </AgenteBotao>
        <AgenteBotao
          data-vitrine-outra
          variante="fantasma"
          bloco
          @click="emit('fechar')"
        >
          {{ t(`${NS}.DETALHE.OUTRA`) }}
        </AgenteBotao>
      </template>
      <template v-else>
        <AgenteBotao
          data-vitrine-ensinar
          tamanho="lg"
          bloco
          icone="i-lucide-sparkles"
          :inativo="!agenteEscolhido"
          @click="ensinar"
        >
          {{
            agenteEscolhido
              ? t(`${NS}.DETALHE.ENSINAR`, { nome: agenteEscolhido.name })
              : t(`${NS}.DETALHE.ESCOLHA_AGENTE`)
          }}
        </AgenteBotao>
      </template>
    </template>
  </AgenteGaveta>
</template>
