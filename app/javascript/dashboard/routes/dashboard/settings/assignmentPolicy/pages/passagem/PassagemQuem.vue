<script setup>
import { computed, inject, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import AgenteIa from 'dashboard/routes/dashboard/crm/caixas/components/AgenteIa.vue';
import PassagemOpcao from './PassagemOpcao.vue';
import PassagemInterruptor from './PassagemInterruptor.vue';
import { ehAgente, faltaQuemRecebe } from './passagem';

// #1385 — quem recebe. A equipe é a das caixas de entrada do funil (Caixas no CRM decide quem está em cada uma): aqui
// só se escolhe entre "alguém da equipe" e "sempre a mesma pessoa".
// #1593 — com a Fase 2 dos Agentes, os agentes de IA das caixas aparecem junto, com o selo. Não entram na vez de
// "alguém da equipe" (só pessoas online); recebem quando escolhidos em "A mesma pessoa" ou pedidos pelo nome.
const props = defineProps({
  nome: { type: String, required: true },
  equipe: { type: Array, default: () => [] },
  todas: { type: Array, default: () => [] },
  mostrarErros: { type: Boolean, default: false },
});

const regra = defineModel({ type: Object, required: true });

const { t } = useI18n();
const Q = 'CRM_KANBAN.PASSAGEM.QUEM';
const { agentes, caixas } = inject('passagemIa', {
  agentes: ref([]),
  caixas: ref([]),
});
const comIa = computed(() => agentes.value.length > 0);

const mudar = campos => {
  regra.value = { ...regra.value, ...campos };
};
const destino = computed({
  get: () => regra.value.pool_type,
  set: valor => mudar({ pool_type: valor }),
});
const pessoa = computed({
  get: () => regra.value.pool_id || '',
  set: valor =>
    mudar({ pool_id: ehAgente(valor) ? valor : Number(valor) || null }),
});
const peloNome = computed({
  get: () => regra.value.mode === 'direct',
  set: ligado => mudar({ mode: ligado ? 'direct' : 'round_robin' }),
});

const naEquipe = id =>
  ehAgente(id)
    ? agentes.value.some(agente => `ia:${agente.id}` === id)
    : props.equipe.some(item => item.id === id);
const opcoesDePessoas = computed(() => {
  const lista = props.equipe.map(item => ({
    value: item.id,
    label: item.name,
  }));
  const atual = regra.value.pool_id;
  if (atual && !naEquipe(atual)) {
    // Agente salvo antes que não aparece mais (os agentes de IA foram desligados na conta): sem o "ia:<id>" na tela.
    const fora = props.todas.find(item => item.id === atual);
    lista.push({
      value: atual,
      label: ehAgente(atual)
        ? t(`${Q}.IA_INDISPONIVEL`)
        : t(`${Q}.FORA_DA_EQUIPE`, { nome: fora?.name || atual }),
    });
  }
  return lista;
});
const opcoesDeAgentes = computed(() =>
  agentes.value.map(agente => ({
    value: `ia:${agente.id}`,
    label: t(agente.parado ? `${Q}.IA_OPCAO_PARADO` : `${Q}.IA_OPCAO`, {
      nome: agente.name,
    }),
    disabled: agente.parado && regra.value.pool_id !== `ia:${agente.id}`,
  }))
);
const grupos = computed(() =>
  comIa.value
    ? [
        { label: t(`${Q}.GRUPO_PESSOAS`), options: opcoesDePessoas.value },
        { label: t(`${Q}.GRUPO_IA`), options: opcoesDeAgentes.value },
      ]
    : []
);

// O agente escolhido em "A mesma pessoa" e em quais caixas do funil ele atende.
const agenteEscolhido = computed(() => {
  if (!ehAgente(regra.value.pool_id)) return null;
  const agente = agentes.value.find(
    item => `ia:${item.id}` === regra.value.pool_id
  );
  if (!agente) return null;
  // As caixas vêm do servidor como { id, name }: as do funil em que o agente pode receber.
  const doFunil = caixas.value.map(caixa => caixa.id);
  const atende = agente.caixas
    .filter(caixa => doFunil.includes(caixa.id))
    .map(caixa => caixa.name);
  return { ...agente, atende, todas: atende.length === doFunil.length };
});
const avisoDoAgente = computed(() => {
  const agente = agenteEscolhido.value;
  if (!agente) return null;
  if (agente.parado) {
    return { tom: 'ambar', texto: t(`${Q}.IA_PARADO`, { nome: agente.name }) };
  }
  if (!agente.atende.length) {
    return {
      tom: 'ambar',
      texto: t(`${Q}.IA_SEM_CAIXA`, { nome: agente.name }),
    };
  }
  if (!agente.todas) {
    return {
      tom: 'azul',
      texto: t(`${Q}.IA_ALGUMAS_CAIXAS`, {
        nome: agente.name,
        caixas: agente.atende.join(', '),
      }),
    };
  }
  return { tom: 'azul', texto: t(`${Q}.IA_TODAS_AS_CAIXAS`) };
});

const falta = computed(
  () => props.mostrarErros && faltaQuemRecebe(regra.value)
);
const iniciais = nomeCompleto =>
  nomeCompleto
    .split(' ')
    .slice(0, 2)
    .map(parte => parte[0])
    .join('');
</script>

<template>
  <section class="flex flex-col gap-5" :aria-labelledby="`${nome}-quem`">
    <h2 :id="`${nome}-quem`" class="mb-0 text-lg font-semibold text-n-slate-12">
      {{ t(`${Q}.TITULO`) }}
    </h2>

    <div
      role="radiogroup"
      :aria-labelledby="`${nome}-quem`"
      class="grid gap-3 sm:grid-cols-2"
    >
      <PassagemOpcao
        v-model="destino"
        :name="`${nome}-destino`"
        value="inbox"
        icone="i-lucide-users"
        :titulo="t(`${Q}.EQUIPE`)"
        :descricao="t(comIa ? `${Q}.EQUIPE_DESC_IA` : `${Q}.EQUIPE_DESC`)"
      />
      <PassagemOpcao
        v-model="destino"
        :name="`${nome}-destino`"
        value="user"
        icone="i-lucide-user-round"
        :titulo="t(`${Q}.PESSOA`)"
        :descricao="t(comIa ? `${Q}.PESSOA_DESC_IA` : `${Q}.PESSOA_DESC`)"
      />
    </div>

    <div
      v-if="destino === 'inbox'"
      class="flex flex-col gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-4 sm:p-5"
    >
      <div class="flex flex-col gap-2">
        <span class="text-sm font-medium text-n-slate-11">
          {{ t(`${Q}.EQUIPE_HOJE`, { n: equipe.length }, equipe.length) }}
        </span>
        <ul v-if="equipe.length" class="m-0 flex list-none flex-wrap gap-2 p-0">
          <li
            v-for="item in equipe"
            :key="item.id"
            class="inline-flex items-center gap-2 rounded-full bg-n-alpha-2 py-1 pe-3 ps-1 text-sm text-n-slate-12"
          >
            <span
              class="grid size-7 place-items-center rounded-full bg-n-iris-3 text-xs font-semibold text-n-iris-11"
              aria-hidden="true"
            >
              {{ iniciais(item.name) }}
            </span>
            {{ item.name }}
          </li>
        </ul>
        <p v-else class="mb-0 text-[0.9375rem] text-n-amber-11">
          {{ t(`${Q}.EQUIPE_VAZIA`) }}
        </p>
      </div>
      <div
        v-if="comIa"
        data-ia-na-equipe
        class="flex flex-col gap-2 border-t border-n-weak pt-4"
      >
        <span class="text-sm font-medium text-n-slate-11">
          {{ t(`${Q}.IA_NAS_CAIXAS`, { n: agentes.length }, agentes.length) }}
        </span>
        <ul class="m-0 flex list-none flex-wrap gap-2 p-0">
          <li
            v-for="agente in agentes"
            :key="agente.id"
            data-chip-ia
            class="inline-flex items-center gap-2 rounded-full bg-n-alpha-2 py-1 pe-2 ps-1 text-sm text-n-slate-12"
            :class="{ 'opacity-70': agente.parado }"
          >
            <span
              class="grid size-7 place-items-center rounded-full bg-n-iris-3 text-n-iris-11"
              aria-hidden="true"
            >
              <span class="i-lucide-bot size-4" />
            </span>
            {{ agente.name }}
            <span
              class="rounded-md bg-n-iris-3 px-1.5 py-0.5 text-xs font-medium text-n-iris-11"
            >
              {{ t('CRM_CAIXAS.PESSOAS.SELO_IA') }}
            </span>
            <span
              v-if="agente.parado"
              class="rounded-md bg-n-slate-3 px-1.5 py-0.5 text-xs font-medium text-n-slate-11"
            >
              {{ t('CRM_CAIXAS.PESSOAS.PARADO') }}
            </span>
          </li>
        </ul>
        <p
          class="mb-0 flex items-start gap-2 rounded-xl bg-n-alpha-1 px-3 py-2 text-sm leading-5 text-n-slate-12"
        >
          <span
            class="i-lucide-info mt-0.5 size-4 shrink-0 text-n-slate-11"
            aria-hidden="true"
          />
          {{ t(`${Q}.IA_FORA_DA_VEZ`) }}
        </p>
      </div>
      <label
        class="flex cursor-pointer items-start gap-3 border-t border-n-weak pt-4"
      >
        <span class="flex min-w-0 flex-1 flex-col gap-0.5">
          <span
            class="text-[0.9375rem] font-semibold leading-6 text-n-slate-12"
          >
            {{ t(comIa ? `${Q}.PELO_NOME_IA` : `${Q}.PELO_NOME`) }}
          </span>
          <span class="text-sm leading-5 text-n-slate-11">{{
            t(comIa ? `${Q}.PELO_NOME_DESC_IA` : `${Q}.PELO_NOME_DESC`)
          }}</span>
        </span>
        <PassagemInterruptor v-model="peloNome" />
      </label>
      <router-link
        :to="{ name: 'crm_caixas' }"
        class="inline-flex min-h-11 w-fit items-center gap-1.5 text-[0.9375rem] font-medium text-n-blue-11 hover:underline"
      >
        {{ t(`${Q}.LINK_CAIXAS`) }}
        <span
          class="i-lucide-arrow-right size-4 rtl:rotate-180"
          aria-hidden="true"
        />
      </router-link>
    </div>

    <div
      v-else
      class="flex flex-col gap-2 rounded-2xl border border-n-weak bg-n-solid-1 p-4 sm:p-5"
    >
      <span :id="`${nome}-pessoa`" class="text-sm font-medium text-n-slate-12">
        {{ t(comIa ? `${Q}.PESSOA_CAMPO_IA` : `${Q}.PESSOA_CAMPO`) }}
      </span>
      <ChoiceSelect
        v-model="pessoa"
        :options="comIa ? [] : opcoesDePessoas"
        :groups="grupos"
        :aria-label="t(comIa ? `${Q}.PESSOA_CAMPO_IA` : `${Q}.PESSOA_CAMPO`)"
        :placeholder="t(comIa ? `${Q}.ESCOLHA_IA` : `${Q}.ESCOLHA`)"
        :invalid="falta"
        class="w-full sm:max-w-sm [&>button]:!h-11"
      />
      <div
        v-if="agenteEscolhido"
        data-agente-escolhido
        class="mt-2 flex flex-col gap-3 rounded-xl border border-n-weak p-3"
      >
        <AgenteIa
          :nome="agenteEscolhido.name"
          :parado="agenteEscolhido.parado"
          :texto="t(`${Q}.IA_ASSUME`)"
        />
        <p
          v-if="avisoDoAgente"
          class="mb-0 flex items-start gap-2 rounded-lg px-3 py-2 text-sm leading-5 text-n-slate-12"
          :class="
            avisoDoAgente.tom === 'ambar' ? 'bg-n-amber-2' : 'bg-n-blue-2'
          "
        >
          <span
            class="mt-0.5 size-4 shrink-0"
            :class="
              avisoDoAgente.tom === 'ambar'
                ? 'i-lucide-triangle-alert text-n-amber-11'
                : 'i-lucide-info text-n-blue-11'
            "
            aria-hidden="true"
          />
          {{ avisoDoAgente.texto }}
        </p>
      </div>
      <p
        v-if="regra.pool_id && !naEquipe(regra.pool_id)"
        class="mb-0 text-sm text-n-amber-11"
      >
        {{
          t(
            ehAgente(regra.pool_id)
              ? `${Q}.AVISO_IA_INDISPONIVEL`
              : `${Q}.AVISO_FORA_DA_EQUIPE`
          )
        }}
      </p>
      <p
        v-if="falta"
        role="alert"
        class="mb-0 flex items-center gap-2 text-sm font-medium text-n-ruby-11"
      >
        <span
          class="i-lucide-circle-alert size-4 shrink-0"
          aria-hidden="true"
        />
        {{ t('CRM_KANBAN.PASSAGEM.FALTA_PESSOA') }}
      </p>
    </div>
  </section>
</template>
