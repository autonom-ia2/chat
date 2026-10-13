<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import PassagemOpcao from './PassagemOpcao.vue';
import PassagemInterruptor from './PassagemInterruptor.vue';
import { faltaQuemRecebe } from './passagem';

// #1385 — quem recebe. A equipe é a das caixas de entrada do funil (Caixas no CRM decide quem está em cada uma): aqui
// só se escolhe entre "alguém da equipe" e "sempre a mesma pessoa".
const props = defineProps({
  nome: { type: String, required: true },
  equipe: { type: Array, default: () => [] },
  todas: { type: Array, default: () => [] },
  mostrarErros: { type: Boolean, default: false },
});

const regra = defineModel({ type: Object, required: true });

const { t } = useI18n();
const Q = 'CRM_KANBAN.PASSAGEM.QUEM';

const mudar = campos => {
  regra.value = { ...regra.value, ...campos };
};
const destino = computed({
  get: () => regra.value.pool_type,
  set: valor => mudar({ pool_type: valor }),
});
const pessoa = computed({
  get: () => regra.value.pool_id || '',
  set: valor => mudar({ pool_id: Number(valor) || null }),
});
const peloNome = computed({
  get: () => regra.value.mode === 'direct',
  set: ligado => mudar({ mode: ligado ? 'direct' : 'round_robin' }),
});

const naEquipe = id => props.equipe.some(item => item.id === id);
const opcoes = computed(() => {
  const lista = props.equipe.map(item => ({
    value: item.id,
    label: item.name,
  }));
  const atual = regra.value.pool_id;
  if (atual && !naEquipe(atual)) {
    const fora = props.todas.find(item => item.id === atual);
    lista.push({
      value: atual,
      label: t(`${Q}.FORA_DA_EQUIPE`, { nome: fora?.name || atual }),
    });
  }
  return lista;
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
        :descricao="t(`${Q}.EQUIPE_DESC`)"
      />
      <PassagemOpcao
        v-model="destino"
        :name="`${nome}-destino`"
        value="user"
        icone="i-lucide-user-round"
        :titulo="t(`${Q}.PESSOA`)"
        :descricao="t(`${Q}.PESSOA_DESC`)"
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
      <label
        class="flex cursor-pointer items-start gap-3 border-t border-n-weak pt-4"
      >
        <span class="flex min-w-0 flex-1 flex-col gap-0.5">
          <span
            class="text-[0.9375rem] font-semibold leading-6 text-n-slate-12"
          >
            {{ t(`${Q}.PELO_NOME`) }}
          </span>
          <span class="text-sm leading-5 text-n-slate-11">{{
            t(`${Q}.PELO_NOME_DESC`)
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
        {{ t(`${Q}.PESSOA_CAMPO`) }}
      </span>
      <ChoiceSelect
        v-model="pessoa"
        :options="opcoes"
        :aria-label="t(`${Q}.PESSOA_CAMPO`)"
        :placeholder="t(`${Q}.ESCOLHA`)"
        :invalid="falta"
        class="w-full sm:max-w-sm [&>button]:!h-11"
      />
      <p
        v-if="regra.pool_id && !naEquipe(regra.pool_id)"
        class="mb-0 text-sm text-n-amber-11"
      >
        {{ t(`${Q}.AVISO_FORA_DA_EQUIPE`) }}
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
