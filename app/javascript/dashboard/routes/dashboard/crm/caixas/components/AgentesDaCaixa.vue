<script setup>
import { computed, ref } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { useI18n } from 'vue-i18n';
import AgenteIa from './AgenteIa.vue';
import { corDoFunil } from '../helpers/caixa';
import {
  alternarFunilDoAgente,
  donoDoFunil,
  entraNaCaixa,
  funisDoAgente,
  nomesDosFunis,
  tirarDaCaixa,
  voltarParaCaixa,
} from '../helpers/agentesIa';

// #1447 — os agentes de IA na etapa "Quem cuida do quê?". A porta atende
// primeiro e não tem funis para escolher. Os agentes de área da caixa aparecem
// como as pessoas membros dela, cada um com os funis de que cuida; um funil
// tem um agente só, e tocar num funil de outro agente passa o funil e avisa,
// com desfazer. Os outros agentes da conta ficam em "Mostrar outros agentes":
// marcar um funil num deles o põe na caixa ao salvar. Tirar um agente da caixa
// avisa quando ele vai parar (era a única caixa dele).
const props = defineProps({
  porta: { type: Object, default: null },
  podeMudar: { type: Boolean, default: false },
  // Só os funis marcados na etapa 1.
  funis: { type: Array, required: true },
  todosOsFunis: { type: Array, required: true },
});

const agentes = defineModel('agentes', { type: Array, required: true });

const { t, locale } = useI18n();
const idsDosFunis = computed(() => props.funis.map(funil => funil.id));

const textoDoAgente = agente => {
  const meus = funisDoAgente(agente, props.funis);
  return meus.length
    ? t('CRM_CAIXAS.PESSOAS.AGENTE_CUIDA', {
        funis: nomesDosFunis(meus, locale.value),
      })
    : t('CRM_CAIXAS.PESSOAS.AGENTE_NADA');
};

// Quem é da caixa fica sempre à vista. Os outros, só depois de "Mostrar
// outros agentes" ou de tocados agora (para não sumirem ao desmarcar).
const mostrarTodos = ref(false);
const tocados = ref([]);
const visivel = agente =>
  agente.na_caixa ||
  mostrarTodos.value ||
  tocados.value.includes(agente.id) ||
  agente.pipeline_ids.length > 0;
const aVista = computed(() => agentes.value.filter(visivel));
const recolhidos = computed(() =>
  props.podeMudar ? agentes.value.length - aVista.value.length : 0
);

// { agenteId, antes, funil, de } do último funil que trocou de agente.
const troca = ref(null);

const cuida = (agente, funil) => agente.pipeline_ids.includes(funil.id);
const outroDono = (agente, funil) => {
  const quem = donoDoFunil(agentes.value, funil.id);
  return quem && quem.id !== agente.id ? quem : null;
};
const podeMexer = agente => props.podeMudar && !agente.sai;

const alternar = (agente, funil) => {
  const antes = agentes.value;
  const { agentes: novos, tirouDe } = alternarFunilDoAgente(
    antes,
    agente.id,
    funil.id
  );
  agentes.value = novos;
  tocados.value = [
    ...tocados.value,
    agente.id,
    ...(tirouDe ? [tirouDe.id] : []),
  ];
  troca.value = tirouDe
    ? { agenteId: agente.id, antes, funil: funil.name, de: tirouDe.name }
    : null;
};

const desfazerTroca = () => {
  agentes.value = troca.value.antes;
  troca.value = null;
};

// O desfazer da troca devolve a lista de antes dela: tirar ou voltar um
// agente depois disso fecha o aviso, para não desfazer o que veio depois.
const tirar = agente => {
  agentes.value = tirarDaCaixa(agentes.value, agente.id);
  troca.value = null;
};

const voltar = agente => {
  agentes.value = voltarParaCaixa(agentes.value, agente.id);
  troca.value = null;
};

const avisoDeEntrada = agente =>
  agente.parado
    ? t('CRM_CAIXAS.PESSOAS.ENTRA_E_LIGA')
    : t('CRM_CAIXAS.PESSOAS.ENTRA');

const chipClasse = ativo =>
  ativo
    ? 'border-n-iris-9 bg-n-iris-3 text-n-iris-11'
    : 'border-n-weak bg-n-solid-1 text-n-slate-11 enabled:hover:border-n-slate-7';
</script>

<template>
  <div class="flex flex-col gap-3">
    <ul data-agentes class="m-0 flex list-none flex-col gap-3 p-0">
      <li
        v-if="porta"
        data-porta
        class="flex items-center gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4"
      >
        <AgenteIa :nome="porta.name" :texto="$t('CRM_CAIXAS.PESSOAS.PORTA')" />
      </li>

      <li
        v-for="agente in aVista"
        :key="agente.id"
        :data-agente-area="agente.name"
        class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4"
      >
        <div
          class="flex flex-col items-start gap-2 sm:flex-row sm:items-center"
        >
          <AgenteIa
            :nome="agente.name"
            :texto="agente.sai ? '' : textoDoAgente(agente)"
            :parado="agente.parado"
            :class="agente.sai ? 'opacity-60' : ''"
          />
          <Button
            v-if="podeMudar && agente.na_caixa && !agente.sai"
            data-tirar
            :label="$t('CRM_CAIXAS.PESSOAS.TIRAR')"
            icon="i-lucide-log-out"
            slate
            ghost
            sm
            class="!min-h-11"
            @click="tirar(agente)"
          />
        </div>

        <div
          v-if="!agente.sai"
          class="flex flex-wrap gap-2"
          role="group"
          :aria-label="$t('CRM_CAIXAS.PESSOAS.CUIDA_DE', { nome: agente.name })"
        >
          <button
            v-for="funil in funis"
            :key="funil.id"
            type="button"
            :data-agente-funil="funil.name"
            :aria-pressed="cuida(agente, funil)"
            :disabled="!podeMexer(agente)"
            class="inline-flex min-h-11 items-center gap-2 rounded-xl border border-solid px-3 text-[0.9375rem] font-medium disabled:cursor-default"
            :class="chipClasse(cuida(agente, funil))"
            @click="alternar(agente, funil)"
          >
            <span
              :class="cuida(agente, funil) ? 'i-lucide-check' : 'i-lucide-plus'"
              class="size-4"
              aria-hidden="true"
            />
            <span
              class="size-2.5 rounded-full"
              :class="corDoFunil(todosOsFunis, funil.id)"
              aria-hidden="true"
            />
            {{ funil.name }}
            <span
              v-if="outroDono(agente, funil)"
              class="text-sm font-normal text-n-slate-10"
            >
              {{
                $t('CRM_CAIXAS.PESSOAS.FUNIL_COM', {
                  nome: outroDono(agente, funil).name,
                })
              }}
            </span>
          </button>
        </div>

        <p
          v-if="entraNaCaixa(agente, idsDosFunis)"
          data-entra
          role="status"
          class="mb-0 flex items-start gap-2 text-[0.9375rem] text-n-slate-11"
        >
          <span
            class="i-lucide-log-in mt-0.5 size-4 shrink-0"
            aria-hidden="true"
          />
          {{ avisoDeEntrada(agente) }}
        </p>

        <div
          v-if="agente.sai"
          data-sai
          role="status"
          class="flex flex-wrap items-center gap-x-3 gap-y-1 rounded-xl bg-n-amber-2 px-3 py-2 text-[0.9375rem] text-n-slate-12"
        >
          <span
            class="i-lucide-triangle-alert size-4 shrink-0 text-n-amber-11"
            aria-hidden="true"
          />
          <span class="min-w-0 flex-1">
            {{
              agente.ultima_caixa
                ? $t('CRM_CAIXAS.PESSOAS.VAI_PARAR', { nome: agente.name })
                : $t('CRM_CAIXAS.PESSOAS.SAI')
            }}
          </span>
          <button
            type="button"
            data-voltar
            class="-me-1 inline-flex min-h-11 items-center rounded-lg px-2 font-medium text-n-blue-11 hover:bg-n-alpha-2"
            @click="voltar(agente)"
          >
            {{ $t('CRM_CAIXAS.PESSOAS.DESFAZER') }}
          </button>
        </div>

        <div
          v-if="troca && troca.agenteId === agente.id"
          role="status"
          data-troca
          class="flex flex-wrap items-center gap-x-3 gap-y-1 rounded-xl bg-n-amber-2 px-3 py-2 text-[0.9375rem] text-n-slate-12"
        >
          <span
            class="i-lucide-arrow-right-left size-4 shrink-0 text-n-amber-11"
            aria-hidden="true"
          />
          <span class="min-w-0 flex-1">
            {{
              $t('CRM_CAIXAS.PESSOAS.TROCOU', {
                funil: troca.funil,
                antes: troca.de,
                agora: agente.name,
              })
            }}
          </span>
          <button
            type="button"
            data-desfazer
            class="-me-1 inline-flex min-h-11 items-center rounded-lg px-2 font-medium text-n-blue-11 hover:bg-n-alpha-2"
            @click="desfazerTroca"
          >
            {{ $t('CRM_CAIXAS.PESSOAS.DESFAZER') }}
          </button>
        </div>
      </li>
    </ul>
    <p
      v-if="!podeMudar && aVista.length"
      data-so-leitura
      class="mb-0 flex items-start gap-2 text-[0.9375rem] text-n-slate-11"
    >
      <span class="i-lucide-lock mt-0.5 size-4 shrink-0" aria-hidden="true" />
      {{ $t('CRM_CAIXAS.PESSOAS.SO_QUEM_GERENCIA') }}
    </p>
    <Button
      v-if="recolhidos"
      data-mostrar-agentes
      :label="$t('CRM_CAIXAS.PESSOAS.MOSTRAR_AGENTES', { n: recolhidos })"
      icon="i-lucide-chevron-down"
      slate
      ghost
      class="!min-h-11 -ms-3 self-start"
      @click="mostrarTodos = true"
    />
  </div>
</template>
