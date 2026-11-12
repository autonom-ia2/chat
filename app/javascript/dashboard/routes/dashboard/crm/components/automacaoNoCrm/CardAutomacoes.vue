<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n, I18nT } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import { usePodeMontarAutomacao } from 'dashboard/composables/usePodeMontarAutomacao';
import CardCartao from '../card/CardCartao.vue';
import { useFonteDasAutomacoes } from './useAutomacaoNoCrm';
import { diaCurto } from './datas';

// #2414 F6.3 — "Automações deste card": o que está agindo neste card, uma
// frase por automação ("Lembrete de proposta — espera até 15/11"), cada uma com
// "Parar para este card" e a confirmação numa frase, ali mesmo. Vazio: uma
// frase e "Criar uma automação" (o editor já abre com a etapa do card).
const props = defineProps({
  card: { type: Object, required: true },
  podeGerenciar: { type: Boolean, default: false },
});

const { t, locale } = useI18n();
const route = useRoute();
const router = useRouter();
const fonte = useFonteDasAutomacoes();
const podeMontar = usePodeMontarAutomacao();
const podeParar = computed(() => props.podeGerenciar && podeMontar.value);

const C = 'AUTOMACAO_NO_CRM.CARD';
const itens = ref([]);
const estado = ref('carregando');
const confirmando = ref(null);
const parando = ref(false);
const aviso = ref('');
const botaoSim = ref(null);
const avisoEl = ref(null);

const carregar = async () => {
  estado.value = 'carregando';
  confirmando.value = null;
  aviso.value = '';
  try {
    itens.value = await fonte.automacoesDoCard(props.card);
    estado.value = 'pronto';
  } catch {
    itens.value = [];
    estado.value = 'erro';
  }
};
watch(() => props.card?.id, carregar, { immediate: true });

const situacao = item => {
  if (item.estado === 'espera')
    return t(`${C}.ESPERA_ATE`, { dia: diaCurto(item.ate, locale.value) });
  if (item.estado === 'resposta') return t(`${C}.ESPERA_RESPOSTA`);
  return t(`${C}.AGINDO`);
};

const pedirParar = async item => {
  aviso.value = '';
  confirmando.value = item.id;
  await nextTick();
  botaoSim.value?.$el?.focus();
};

const parar = async item => {
  parando.value = true;
  try {
    await fonte.pararNoCard(props.card, item);
    itens.value = itens.value.filter(outro => outro.id !== item.id);
    confirmando.value = null;
    aviso.value = t(`${C}.PAROU`, { nome: item.nome });
    await nextTick();
    avisoEl.value?.focus();
  } catch {
    aviso.value = t(`${C}.ERRO_PARAR`);
  } finally {
    parando.value = false;
  }
};

const criar = () =>
  router.push({
    name: 'automacoes_livre_nova',
    params: { accountId: route.params.accountId },
    query: {
      gatilho: 'card.entrou_na_etapa',
      etapa: String(props.card.stage_id),
    },
  });
</script>

<template>
  <CardCartao
    parte="automacoes"
    icone="i-lucide-zap"
    tom="bg-n-iris-3 text-n-iris-11"
    :titulo="t(`${C}.TITULO`)"
    acao=""
  >
    <p v-if="estado === 'carregando'" class="mb-0 text-n-slate-11">
      {{ t(`${C}.CARREGANDO`) }}
    </p>
    <div
      v-else-if="estado === 'erro'"
      data-automacoes-erro
      class="flex flex-wrap items-center gap-2"
    >
      <p class="mb-0">{{ t(`${C}.ERRO_LISTA`) }}</p>
      <Button
        :label="t(`${C}.TENTAR`)"
        slate
        faded
        class="!min-h-11"
        @click="carregar"
      />
    </div>
    <div
      v-else-if="!itens.length"
      data-automacoes-vazio
      class="flex flex-col items-start gap-3"
    >
      <p class="mb-0">{{ t(`${C}.VAZIO`) }}</p>
      <Button
        v-if="podeMontar && card.stage_id"
        data-criar-automacao
        :label="t(`${C}.CRIAR`)"
        icon="i-lucide-plus"
        blue
        faded
        class="!min-h-11"
        @click="criar"
      />
    </div>
    <ul v-else class="m-0 flex list-none flex-col divide-y divide-n-weak p-0">
      <li
        v-for="item in itens"
        :key="item.id"
        :data-automacao-do-card="item.id"
        class="flex flex-col gap-2 py-2 first:pt-0 last:pb-0 sm:flex-row sm:items-center"
      >
        <template v-if="confirmando === item.id">
          <p class="mb-0 min-w-0 flex-1 font-medium" data-confirma>
            {{ t(`${C}.CONFIRMA`, { nome: item.nome }) }}
          </p>
          <div class="flex shrink-0 flex-wrap gap-2">
            <Button
              :ref="el => (botaoSim = el)"
              data-parar-sim
              :label="t(`${C}.SIM`)"
              ruby
              class="!min-h-11"
              :is-loading="parando"
              :disabled="parando"
              @click="parar(item)"
            />
            <Button
              data-parar-voltar
              :label="t(`${C}.VOLTAR`)"
              slate
              faded
              class="!min-h-11"
              :disabled="parando"
              @click="confirmando = null"
            />
          </div>
        </template>
        <template v-else>
          <I18nT
            :keypath="`${C}.ITEM`"
            tag="p"
            scope="global"
            class="mb-0 min-w-0 flex-1 break-words"
          >
            <template #nome>
              <strong class="font-semibold">{{ item.nome }}</strong>
            </template>
            <template #situacao>{{ situacao(item) }}</template>
          </I18nT>
          <Button
            v-if="podeParar"
            data-parar
            :label="t(`${C}.PARAR`)"
            :aria-label="t(`${C}.PARAR_ROTULO`, { nome: item.nome })"
            icon="i-lucide-circle-stop"
            slate
            faded
            class="!min-h-11 shrink-0 self-start sm:self-center"
            @click="pedirParar(item)"
          />
        </template>
      </li>
    </ul>
    <template #extra>
      <p
        ref="avisoEl"
        data-aviso-parar
        tabindex="-1"
        role="status"
        class="mb-0 text-sm text-n-slate-11 outline-none"
        :class="aviso ? '' : 'sr-only'"
      >
        {{ aviso }}
      </p>
    </template>
  </CardCartao>
</template>
