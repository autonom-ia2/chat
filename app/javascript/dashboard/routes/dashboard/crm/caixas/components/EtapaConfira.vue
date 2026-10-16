<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import AgenteIa from './AgenteIa.vue';
import { useAgenteIaPorCaixa } from 'dashboard/routes/dashboard/autonomia/agentes/composables/useAgenteIaPorCaixa';
import FunilSelo from './FunilSelo.vue';
import {
  assuntosDe,
  corDoFunil,
  funisDaCaixa,
  juntar,
  mudancas,
  portaOuRobo,
  primeiroNome,
  quemCuida,
  quemFazTriagem,
  roboExterno,
} from '../helpers/caixa';
import {
  agentesDoFormulario,
  donoDoFunil,
  ficaNaCaixa,
  funisDoAgente,
  funisSemAgente,
  mudancasDosAgentes,
  nomesDosFunis,
} from '../helpers/agentesIa';

// #1149 — etapa 4: a caixa inteira em frases antes do Salvar, com o que muda
// em relação ao que está salvo hoje.
const props = defineProps({
  form: { type: Object, required: true },
  original: { type: Object, required: true },
  funis: { type: Array, required: true },
  // #1140 — { triagem, funis } do servidor; null enquanto confere.
  quemRecebe: { type: Object, default: null },
  quemRecebeErro: { type: Boolean, default: false },
});

defineEmits(['conferirDeNovo']);

const { t, locale } = useI18n();
// #1648 — com a aba "Agente de IA" por caixa, o agente de outro sistema é um agente de IA como os nossos.
const porCaixa = useAgenteIaPorCaixa();

const funisMarcados = computed(() => funisDaCaixa(props.form, props.funis));
const varios = computed(() => funisMarcados.value.length > 1);
const nomes = pessoas => juntar(pessoas.map(primeiroNome), locale.value);

const pessoas = computed(() =>
  [...props.form.people]
    .sort(
      (a, b) =>
        Number(a.administrator) - Number(b.administrator) ||
        a.name.localeCompare(b.name)
    )
    .map(pessoa => {
      if (pessoa.administrator) {
        return { pessoa, texto: t('CRM_CAIXAS.CONFIRA.ADMIN') };
      }
      const assuntos = assuntosDe(
        pessoa,
        funisMarcados.value,
        t('CRM_CAIXAS.CONFIRA.SEM_ASSUNTO')
      );
      if (!assuntos.length) {
        return { pessoa, texto: t('CRM_CAIXAS.CONFIRA.NADA') };
      }
      const chave = pessoa.only_own ? 'SO_SUAS' : 'TODAS';
      return {
        pessoa,
        texto: t(`CRM_CAIXAS.CONFIRA.${chave}`, {
          assuntos: juntar(assuntos, locale.value),
        }),
      };
    })
);

// #1447 — com a Fase 2 dos Agentes: a porta, cada agente de área que fica na
// caixa e os funis que ficam com a porta. Sem ela, só a frase do robô.
const comAgentes = computed(() => Boolean(props.form.ai_agents));
const porta = computed(() =>
  comAgentes.value
    ? portaOuRobo(props.form.ai_agents.porta, props.form.agent_bot)
    : null
);
const areas = computed(() =>
  agentesDoFormulario(props.form).filter(agente =>
    ficaNaCaixa(agente, props.form.pipeline_ids)
  )
);
const textoDaArea = agente => {
  const meus = funisDoAgente(agente, funisMarcados.value);
  return meus.length
    ? t(
        'CRM_CAIXAS.CONFIRA.AGENTE_CUIDA',
        { funis: nomesDosFunis(meus, locale.value) },
        meus.length
      )
    : t('CRM_CAIXAS.PESSOAS.AGENTE_NADA');
};
const agentes = computed(() => [
  ...(porta.value
    ? [
        {
          id: `porta-${porta.value.id}`,
          nome: porta.value.name,
          texto: t('CRM_CAIXAS.PESSOAS.PORTA'),
        },
      ]
    : []),
  ...areas.value.map(agente => ({
    id: agente.id,
    nome: agente.name,
    texto: textoDaArea(agente),
  })),
]);
const comAPorta = computed(() => {
  if (!porta.value) return '';
  const sobra = funisSemAgente(areas.value, funisMarcados.value);
  return sobra.length
    ? t('CRM_CAIXAS.CONFIRA.FICA_COM_A_PORTA', {
        funis: nomesDosFunis(sobra, locale.value),
        porta: porta.value.name,
      })
    : '';
});

// #1140 — quem recebe é a resposta do servidor (regra do motor de entrega). A
// tela só junta os nomes e diz quem marcou o assunto mas fica de fora por ver
// só as dele.
const recebem = chave => {
  const ids =
    (chave === 'triagem'
      ? props.quemRecebe?.triagem
      : props.quemRecebe?.funis?.[String(chave)]) || [];
  return ids
    .map(id => props.form.people.find(pessoa => pessoa.id === id))
    .filter(Boolean);
};
const linhaDoRodizio = (chave, marcadas) => {
  const daFila = recebem(chave);
  const foraDaFila = marcadas.filter(
    pessoa => pessoa.only_own && !daFila.some(item => item.id === pessoa.id)
  );
  return {
    chave,
    quem: nomes(daFila),
    ou: juntar(daFila.map(primeiroNome), locale.value, 'disjunction'),
    quantas: daFila.length,
    fora: foraDaFila.map(pessoa =>
      t('CRM_CAIXAS.CONFIRA.SO_AS_DELE', { nome: primeiroNome(pessoa) })
    ),
  };
};

const rodizio = computed(() => [
  ...(varios.value
    ? [
        {
          ...linhaDoRodizio('triagem', quemFazTriagem(props.form)),
          nome: t('CRM_CAIXAS.CONFIRA.SEM_ASSUNTO_TITULO'),
          cor: 'bg-n-slate-8',
        },
      ]
    : []),
  // #1447: com agente de área, ele atende primeiro e fica fora do rodízio; as
  // pessoas recebem quando o cliente pede uma pessoa.
  ...funisMarcados.value.map(funil => ({
    ...linhaDoRodizio(funil.id, quemCuida(props.form, funil.id)),
    nome: funil.name,
    cor: corDoFunil(props.funis, funil.id),
    agente: donoDoFunil(areas.value, funil.id)?.name || '',
  })),
]);

const ninguemRecebe = computed(() => {
  if (!props.quemRecebe) return '';
  // Assunto com agente de área: ele assume a conversa, e a linha dele já diz
  // quando não há pessoa para quem o cliente pedir.
  const vazios = rodizio.value.filter(item => !item.quantas && !item.agente);
  return vazios.length
    ? t('CRM_CAIXAS.CONFIRA.NINGUEM_RECEBE', {
        assuntos: juntar(
          vazios.map(item => item.nome),
          locale.value
        ),
      })
    : '';
});

const lista = computed(() =>
  [
    ...mudancas(props.original, props.form, props.funis, {
      semAssunto: t('CRM_CAIXAS.CONFIRA.SEM_ASSUNTO'),
      locale: locale.value,
    }),
    ...mudancasDosAgentes(
      props.original,
      props.form,
      props.funis,
      locale.value
    ),
  ].map(({ chave, valores }) =>
    t(`CRM_CAIXAS.MUDA.${chave}`, {
      ...valores,
      resumo: valores.modo
        ? t(`CRM_CAIXAS.MODO_RESUMO.${valores.modo.toUpperCase()}`)
        : '',
    })
  )
);
</script>

<template>
  <div class="flex flex-col gap-4">
    <section
      v-if="!funisMarcados.length"
      class="rounded-2xl border border-n-amber-7 bg-n-amber-2 p-5 text-base text-n-slate-12"
    >
      {{ $t('CRM_CAIXAS.CONFIRA.SAI_DO_CRM') }}
    </section>

    <template v-else>
      <section
        class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-5"
      >
        <h3 class="mb-0 text-base font-semibold text-n-slate-12">
          {{ $t('CRM_CAIXAS.ETAPAS.CHEGA') }}
        </h3>
        <div class="flex flex-wrap gap-2">
          <FunilSelo
            v-for="funil in funisMarcados"
            :key="funil.id"
            :nome="funil.name"
            :cor="corDoFunil(funis, funil.id)"
          />
        </div>
        <p class="mb-0 text-[0.9375rem] text-n-slate-11">
          {{ $t(`CRM_CAIXAS.MODO_RESUMO.${form.modo.toUpperCase()}`) }}
        </p>
      </section>

      <section
        v-if="agentes.length"
        data-confira-agentes
        class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-5"
      >
        <h3 class="mb-0 text-base font-semibold text-n-slate-12">
          {{ $t('CRM_CAIXAS.PESSOAS.AGENTES_TITULO') }}
        </h3>
        <ul class="m-0 flex list-none flex-col gap-3 p-0">
          <li v-for="agente in agentes" :key="agente.id" class="flex">
            <AgenteIa :nome="agente.nome" :texto="agente.texto" />
          </li>
        </ul>
        <p
          v-if="comAPorta"
          class="mb-0 flex items-start gap-2 text-[0.9375rem] text-n-slate-11"
        >
          <span
            class="i-lucide-info mt-0.5 size-4 shrink-0"
            aria-hidden="true"
          />
          {{ comAPorta }}
        </p>
      </section>

      <section
        class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-5"
      >
        <h3 class="mb-0 text-base font-semibold text-n-slate-12">
          {{ $t('CRM_CAIXAS.CONFIRA.QUEM_VE') }}
        </h3>
        <ul class="m-0 flex list-none flex-col gap-3 p-0">
          <li
            v-for="linha in pessoas"
            :key="linha.pessoa.id"
            class="flex items-start gap-3"
          >
            <Avatar :name="linha.pessoa.name" :size="28" rounded-full />
            <p class="mb-0 pt-0.5 text-[0.9375rem] text-n-slate-12">
              <strong class="font-semibold">{{ linha.pessoa.name }}</strong>
              {{ linha.texto }}
            </p>
          </li>
        </ul>
      </section>

      <section
        class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-5"
      >
        <h3 class="mb-0 text-base font-semibold text-n-slate-12">
          {{ $t('CRM_CAIXAS.CONFIRA.RODIZIO') }}
        </h3>
        <p
          v-if="form.agent_bot && !porta"
          data-robo
          class="mb-0 flex items-center gap-2 text-[0.9375rem] text-n-slate-12"
        >
          <span class="i-lucide-bot size-4" aria-hidden="true" />
          {{
            roboExterno(form.agent_bot) && !porCaixa
              ? $t('CRM_CAIXAS.CONFIRA.ROBO_EXTERNO', {
                  nome: form.agent_bot.name,
                })
              : $t('CRM_CAIXAS.CONFIRA.ROBO', { nome: form.agent_bot.name })
          }}
        </p>
        <div
          v-if="quemRecebeErro"
          role="alert"
          class="flex flex-wrap items-center gap-3 text-[0.9375rem] text-n-ruby-11"
        >
          <span class="min-w-0 flex-1">
            {{ $t('CRM_CAIXAS.CONFIRA.ERRO_QUEM_RECEBE') }}
          </span>
          <Button
            :label="$t('CRM_CAIXAS.LISTA.TENTAR_DE_NOVO')"
            icon="i-lucide-refresh-cw"
            slate
            faded
            class="!min-h-11"
            @click="$emit('conferirDeNovo')"
          />
        </div>
        <p
          v-else-if="!quemRecebe"
          role="status"
          aria-busy="true"
          class="mb-0 text-[0.9375rem] text-n-slate-11"
        >
          {{ $t('CRM_CAIXAS.CONFIRA.CONFERINDO') }}
        </p>
        <p
          v-if="ninguemRecebe"
          data-ninguem-recebe
          class="mb-0 flex items-start gap-2 rounded-xl border border-n-amber-7 bg-n-amber-2 p-3 text-[0.9375rem] text-n-slate-12"
        >
          <span
            class="i-lucide-triangle-alert mt-0.5 size-4 shrink-0 text-n-amber-11"
            aria-hidden="true"
          />
          {{ ninguemRecebe }}
        </p>
        <ul v-if="quemRecebe" class="m-0 flex list-none flex-col gap-2 p-0">
          <li
            v-for="item in rodizio"
            :key="item.chave"
            class="flex flex-wrap items-center gap-x-2 text-[0.9375rem] text-n-slate-12"
          >
            <span
              class="size-2.5 rounded-full"
              :class="item.cor"
              aria-hidden="true"
            />
            <strong class="font-semibold">
              {{ $t('CRM_CAIXAS.CONFIRA.RODIZIO_NOME', { nome: item.nome }) }}
            </strong>
            <span
              v-if="!item.agente"
              :class="item.quem ? '' : 'text-n-ruby-11'"
            >
              {{ item.quem || $t('CRM_CAIXAS.CONFIRA.NINGUEM') }}
            </span>
            <span
              v-else
              data-rodizio-agente
              class="flex basis-full flex-col gap-1 ps-[1.125rem]"
            >
              <span class="flex items-start gap-2">
                <span
                  class="i-lucide-bot mt-0.5 size-4 shrink-0 text-n-iris-11"
                  aria-hidden="true"
                />
                {{
                  $t('CRM_CAIXAS.CONFIRA.RODIZIO_AGENTE', { nome: item.agente })
                }}
              </span>
              <span
                class="flex items-start gap-2"
                :class="item.quantas ? '' : 'text-n-ruby-11'"
              >
                <span
                  class="i-lucide-users mt-0.5 size-4 shrink-0 text-n-slate-11"
                  aria-hidden="true"
                />
                {{
                  item.quantas
                    ? $t(
                        'CRM_CAIXAS.CONFIRA.RODIZIO_PESSOAS',
                        { nomes: item.ou },
                        item.quantas
                      )
                    : $t('CRM_CAIXAS.CONFIRA.RODIZIO_SEM_PESSOA')
                }}
              </span>
            </span>
            <span
              v-for="frase in item.fora"
              :key="frase"
              data-rodizio-fora
              class="flex basis-full items-start gap-2 ps-[1.125rem] text-sm text-n-slate-11"
            >
              <span
                class="i-lucide-eye-off mt-0.5 size-4 shrink-0"
                aria-hidden="true"
              />
              {{ frase }}
            </span>
          </li>
        </ul>
      </section>
    </template>

    <section
      class="flex flex-col gap-3 rounded-2xl border border-n-blue-7 bg-n-blue-2 p-5"
    >
      <h3 class="mb-0 text-base font-semibold text-n-slate-12">
        {{ $t('CRM_CAIXAS.CONFIRA.MUDA') }}
      </h3>
      <ul v-if="lista.length" class="m-0 flex list-none flex-col gap-2 p-0">
        <li
          v-for="frase in lista"
          :key="frase"
          class="flex items-start gap-2 text-[0.9375rem] text-n-slate-12"
        >
          <span
            class="i-lucide-arrow-right mt-1 size-4 shrink-0 text-n-blue-11"
            aria-hidden="true"
          />
          {{ frase }}
        </li>
      </ul>
      <p v-else class="mb-0 text-[0.9375rem] text-n-slate-11">
        {{ $t('CRM_CAIXAS.CONFIRA.NADA_MUDOU') }}
      </p>
    </section>
  </div>
</template>
