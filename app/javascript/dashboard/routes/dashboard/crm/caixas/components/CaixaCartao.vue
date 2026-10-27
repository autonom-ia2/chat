<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { useFase2 } from 'dashboard/routes/dashboard/autonomia/agentes/composables/useFase2';
import { useAgenteIaPorCaixa } from 'dashboard/routes/dashboard/autonomia/agentes/composables/useAgenteIaPorCaixa';
import CaixaIcone from './CaixaIcone.vue';
import FunilSelo from './FunilSelo.vue';
import {
  corDoFunil,
  faltaTriagem,
  funisDaCaixa,
  juntar,
  legadoPendente,
  modoDaCaixa,
  portaOuRobo,
  primeiroNome,
  quemFazTriagem,
  roboExterno,
  umFunilSo,
} from '../helpers/caixa';
import {
  areasDa,
  funisDoAgente,
  portaDa,
  temAgentesIa,
} from '../helpers/agentesIa';
import { chaveDoModo, iaSalva } from '../helpers/modoDoAssunto';

// #1149 — uma caixa na lista: o que chega, quem cuida e o que o sistema faz
// sozinho, em frases. O botão abre a caixa nas etapas.
const props = defineProps({
  caixa: { type: Object, required: true },
  funis: { type: Array, required: true },
  salvaAgora: { type: Boolean, default: false },
});

defineEmits(['alterar']);

const { t, locale } = useI18n();

const ligada = computed(() => props.caixa.crm_enabled);
const funis = computed(() => funisDaCaixa(props.caixa, props.funis));
// Todo mundo da caixa, administrador incluído: numa conta em que só há
// administradores, "0 pessoas" diria que ninguém cuida, e todos veem tudo.
const pessoas = computed(() => props.caixa.people.length);
// #1447 — com a Fase 2 dos Agentes (da conta, #1570): a porta e os agentes de
// área que cuidam de algum funil da caixa. Sem ela, o robô que atende primeiro, como sempre.
const fase2 = useFase2();
// #1648 — com a aba "Agente de IA" por caixa, o agente de outro sistema é um agente de IA como os nossos.
const porCaixa = useAgenteIaPorCaixa();
const comAgentes = computed(() => temAgentesIa(props.caixa, fase2.value));
const porta = computed(() =>
  portaOuRobo(portaDa(props.caixa), props.caixa.agent_bot)
);
// #1570 — robô de outro sistema atende primeiro: "agente externo", com ou sem
// a Fase 2.
const externo = computed(
  () => !porta.value && roboExterno(props.caixa.agent_bot)
);
const fraseDoRobo = computed(() => {
  const nome = props.caixa.agent_bot?.name;
  return roboExterno(props.caixa.agent_bot) && !porCaixa.value
    ? t('CRM_CAIXAS.CARTAO.ROBO_EXTERNO', { nome })
    : t('CRM_CAIXAS.CARTAO.ROBO', { nome });
});
const areas = computed(() =>
  areasDa(props.caixa)
    .map(agente => ({
      id: agente.id,
      nome: agente.name,
      funis: juntar(
        funisDoAgente(agente, funis.value).map(funil => funil.name),
        locale.value
      ),
    }))
    .filter(agente => agente.funis)
);
const triagem = computed(() =>
  juntar(quemFazTriagem(props.caixa).map(primeiroNome), locale.value)
);
// #1676 — o que a caixa faz hoje: com a IA de assunto gravada na caixa de 1
// funil, o mesmo texto da etapa 3.
const sozinho = computed(() => {
  const chave = chaveDoModo(
    modoDaCaixa(props.caixa),
    umFunilSo(props.caixa, props.funis),
    iaSalva(props.caixa)
  );
  return t(`CRM_CAIXAS.MODO_RESUMO.${chave}`);
});

const aviso = computed(() => {
  if (!ligada.value) return '';
  if (faltaTriagem(props.caixa)) return t('CRM_CAIXAS.CARTAO.AVISO_TRIAGEM');
  if (legadoPendente(props.caixa)) return t('CRM_CAIXAS.CARTAO.AVISO_LEGADO');
  return '';
});
</script>

<template>
  <article
    data-caixa
    class="flex flex-col gap-5 rounded-2xl border bg-n-solid-1 p-5 md:p-6"
    :class="aviso ? 'border-n-amber-7' : 'border-n-weak'"
  >
    <header class="flex items-start gap-3">
      <CaixaIcone
        :canal="caixa.inbox.channel_type"
        :caixa-id="caixa.inbox.id"
      />
      <div class="min-w-0 flex-1">
        <h2 class="mb-1 truncate text-lg font-semibold text-n-slate-12">
          {{ caixa.inbox.name }}
        </h2>
        <span
          class="inline-flex items-center gap-1.5 text-sm"
          :class="ligada ? 'text-n-teal-11' : 'text-n-slate-11'"
        >
          <span
            class="size-2 rounded-full"
            :class="ligada ? 'bg-n-teal-9' : 'bg-n-slate-8'"
            aria-hidden="true"
          />
          {{
            ligada
              ? $t('CRM_CAIXAS.CARTAO.NO_CRM')
              : $t('CRM_CAIXAS.CARTAO.FORA')
          }}
        </span>
      </div>
      <span
        v-if="salvaAgora"
        class="inline-flex items-center gap-1.5 rounded-lg bg-n-teal-3 px-2.5 py-1 text-sm font-medium text-n-teal-11"
        role="status"
      >
        <span class="i-lucide-check size-4" aria-hidden="true" />
        {{ $t('CRM_CAIXAS.CARTAO.SALVA') }}
      </span>
    </header>

    <p
      v-if="aviso"
      class="mb-0 flex items-start gap-2 rounded-xl bg-n-amber-3 px-3 py-2.5 text-[0.9375rem] text-n-slate-12"
    >
      <span
        class="i-lucide-triangle-alert mt-0.5 size-4 shrink-0 text-n-amber-11"
        aria-hidden="true"
      />
      {{ aviso }}
    </p>

    <dl v-if="ligada" class="m-0 grid gap-4">
      <div class="grid gap-1.5">
        <dt class="text-sm text-n-slate-11">
          {{ $t('CRM_CAIXAS.CARTAO.CHEGA') }}
        </dt>
        <dd class="m-0 flex flex-wrap gap-2">
          <FunilSelo
            v-for="funil in funis"
            :key="funil.id"
            :nome="funil.name"
            :cor="corDoFunil(props.funis, funil.id)"
          />
        </dd>
      </div>
      <div class="grid gap-1">
        <dt class="text-sm text-n-slate-11">
          {{ $t('CRM_CAIXAS.CARTAO.CUIDAM') }}
        </dt>
        <dd v-if="!comAgentes" class="m-0 text-[0.9375rem] text-n-slate-12">
          <span v-if="caixa.agent_bot" class="block">
            {{ fraseDoRobo }}
          </span>
          {{ $t('CRM_CAIXAS.CARTAO.PESSOAS', { n: pessoas }, pessoas) }}
          <template v-if="funis.length > 1 && triagem">
            {{ $t('CRM_CAIXAS.CARTAO.SEM_ASSUNTO', { nomes: triagem }) }}
          </template>
        </dd>
        <dd
          v-else
          data-quem-cuida
          class="m-0 grid gap-1 text-[0.9375rem] text-n-slate-12"
        >
          <span v-if="porta" class="flex items-start gap-2">
            <span
              class="i-lucide-bot mt-0.5 size-4 shrink-0 text-n-iris-11"
              aria-hidden="true"
            />
            <span>
              {{ $t('CRM_CAIXAS.CARTAO.PORTA', { nome: porta.name }) }}
              <span class="sr-only">{{
                $t('CRM_CAIXAS.PESSOAS.SELO_IA')
              }}</span>
            </span>
          </span>
          <span v-else-if="externo" data-externo class="flex items-start gap-2">
            <span
              class="i-lucide-bot mt-0.5 size-4 shrink-0 text-n-slate-11"
              aria-hidden="true"
            />
            <span>{{ fraseDoRobo }}</span>
          </span>
          <span
            v-for="agente in areas"
            :key="agente.id"
            class="flex items-start gap-2"
          >
            <span
              class="i-lucide-bot mt-0.5 size-4 shrink-0 text-n-iris-11"
              aria-hidden="true"
            />
            <span>
              {{
                $t('CRM_CAIXAS.CARTAO.AREA', {
                  nome: agente.nome,
                  funis: agente.funis,
                })
              }}
              <span class="sr-only">{{
                $t('CRM_CAIXAS.PESSOAS.SELO_IA')
              }}</span>
            </span>
          </span>
          <span class="flex items-start gap-2">
            <span
              class="i-lucide-users mt-0.5 size-4 shrink-0 text-n-slate-11"
              aria-hidden="true"
            />
            <span>
              {{ $t('CRM_CAIXAS.CARTAO.PESSOAS', { n: pessoas }, pessoas) }}
              <template v-if="funis.length > 1 && triagem">
                {{ $t('CRM_CAIXAS.CARTAO.SEM_ASSUNTO', { nomes: triagem }) }}
              </template>
            </span>
          </span>
        </dd>
      </div>
      <div class="grid gap-1">
        <dt class="text-sm text-n-slate-11">
          {{ $t('CRM_CAIXAS.CARTAO.SOZINHO') }}
        </dt>
        <dd class="m-0 text-[0.9375rem] text-n-slate-12">{{ sozinho }}</dd>
      </div>
    </dl>
    <p v-else class="mb-0 text-[0.9375rem] text-n-slate-11">
      {{ $t('CRM_CAIXAS.CARTAO.FORA_TEXTO') }}
    </p>

    <footer class="mt-auto flex">
      <Button
        data-alterar
        :label="
          ligada
            ? $t('CRM_CAIXAS.CARTAO.ALTERAR')
            : $t('CRM_CAIXAS.CARTAO.LIGAR')
        "
        :icon="ligada ? 'i-lucide-pencil' : 'i-lucide-plus'"
        :slate="ligada"
        :faded="ligada"
        class="!min-h-11"
        @click="$emit('alterar', caixa)"
      />
    </footer>
  </article>
</template>
