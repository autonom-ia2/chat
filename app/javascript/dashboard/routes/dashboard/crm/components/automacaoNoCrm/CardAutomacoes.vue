<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n, I18nT } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import { usePodeMontarAutomacao } from 'dashboard/composables/usePodeMontarAutomacao';
import { carregarCatalogo } from 'dashboard/routes/dashboard/automacoes/livre/catalogo';
import { fraseDoPasso } from 'dashboard/routes/dashboard/automacoes/livre/frases';
import CardCartao from '../card/CardCartao.vue';
import { useFormato } from '../card/useFormato';
import { semPermissao, useFonteDasAutomacoes } from './useAutomacaoNoCrm';

// #2414 F6.3 (protótipo só da demo) — "Automações deste card": o que está rodando neste card, uma frase por
// automação ("Lembrete de proposta — espera até 15 de novembro"), o passo em que ela está e o que já fez, cada uma
// com "Parar para este card" e a confirmação numa frase, ali mesmo. As frases dos passos saem do frases.js da
// Automação livre. Vazio: uma frase e o botão que cria uma automação para quem entrar na etapa do card.
const props = defineProps({
  card: { type: Object, required: true },
  // A marca do seed no funil (marcaDaDemo).
  marca: { type: Object, required: true },
  // O nome da etapa do card.
  etapa: { type: String, default: '' },
  podeGerenciar: { type: Boolean, default: false },
});

const { t, locale } = useI18n();
const route = useRoute();
const router = useRouter();
const fonte = useFonteDasAutomacoes(props.marca);
const formato = useFormato({ t, locale });
const podeMontar = usePodeMontarAutomacao();
const podeParar = computed(() => props.podeGerenciar && podeMontar.value);

const C = 'AUTOMACAO_NO_CRM.CARD';
const itens = ref([]);
const catalogo = ref(null);
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
    const lista = await fonte.automacoesDoCard(props.card);
    catalogo.value = lista.length ? await carregarCatalogo() : null;
    itens.value = lista;
    estado.value = 'pronto';
  } catch (erro) {
    itens.value = [];
    estado.value = semPermissao(erro) ? 'sem-acesso' : 'erro';
  }
};
// O card chega aos poucos (só o id pelo endereço, depois o do quadro, depois o completo): recarrega quando muda o
// que decide a lista, não só o id.
watch(
  () => [
    props.card?.id,
    props.card?.status,
    props.card?.stage_id,
    props.card?.entered_stage_at,
  ],
  carregar,
  { immediate: true }
);

const dia = valor => formato.diaCurto(new Date(valor));

const situacao = item => {
  if (item.situacao?.tipo === 'espera')
    return t(`${C}.ESPERA_ATE`, { dia: dia(item.situacao.ate) });
  if (item.situacao?.tipo === 'resposta') return t(`${C}.ESPERA_RESPOSTA`);
  return t(`${C}.AGINDO`);
};

const frase = (item, indice) =>
  fraseDoPasso(item.receita.passos[indice], catalogo.value, t);

const passoAtual = item =>
  t(`${C}.PASSO`, {
    n: item.passoAtual + 1,
    total: item.receita.passos.length,
    frase: frase(item, item.passoAtual),
  });

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

// Não há receita pronta de etapa no catálogo (§8.4 do F6-F8-gatilhos.md): o editor abre com o gatilho da etapa.
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
  <!-- `contents`: sem permissão, a parte some sem deixar espaço. -->
  <div class="contents">
    <CardCartao
      v-if="estado !== 'sem-acesso'"
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
          v-if="podeMontar && card.stage_id && etapa"
          data-criar-automacao
          icon="i-lucide-plus"
          blue
          faded
          class="!h-auto !min-h-11 max-w-full py-2"
          @click="criar"
        >
          <!-- O nome da etapa deixa o texto longo: no celular ele quebra a linha em vez de sair do card. -->
          <span class="min-w-0 whitespace-normal text-start">
            {{ t(`${C}.CRIAR`, { etapa }) }}
          </span>
        </Button>
      </div>
      <ul v-else class="m-0 flex list-none flex-col divide-y divide-n-weak p-0">
        <li
          v-for="item in itens"
          :key="item.id"
          :data-automacao-do-card="item.id"
          class="flex flex-col gap-2 py-3 first:pt-0 last:pb-0"
        >
          <template v-if="confirmando === item.id">
            <p class="mb-0 font-medium" data-confirma>
              {{ t(`${C}.CONFIRMA`, { nome: item.nome }) }}
            </p>
            <div class="flex flex-wrap gap-2">
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
            <div class="flex flex-col gap-2 sm:flex-row sm:items-start">
              <div class="flex min-w-0 flex-1 flex-col gap-1">
                <I18nT
                  :keypath="`${C}.ITEM`"
                  tag="p"
                  scope="global"
                  class="mb-0 break-words"
                >
                  <template #nome>
                    <strong class="font-semibold">{{ item.nome }}</strong>
                  </template>
                  <template #situacao>{{ situacao(item) }}</template>
                </I18nT>
                <p data-passo class="mb-0 break-words text-sm text-n-slate-11">
                  {{ passoAtual(item) }}
                </p>
              </div>
              <Button
                v-if="podeParar"
                data-parar
                :label="t(`${C}.PARAR`)"
                :aria-label="t(`${C}.PARAR_ROTULO`, { nome: item.nome })"
                icon="i-lucide-circle-stop"
                slate
                faded
                class="!min-h-11 shrink-0 self-start"
                @click="pedirParar(item)"
              />
            </div>
            <details data-historico class="group text-sm text-n-slate-11">
              <!-- O summary em flex perde o triângulo do navegador: a seta mostra que abre. -->
              <summary
                class="flex min-h-11 cursor-pointer list-none items-center gap-1.5 font-medium text-n-slate-12"
              >
                <span
                  class="i-lucide-chevron-right size-4 shrink-0 transition-transform group-open:rotate-90"
                  aria-hidden="true"
                />
                {{ t(`${C}.HISTORICO`) }}
              </summary>
              <ul class="m-0 flex list-none flex-col gap-1 p-0 ps-4">
                <li>{{ t(`${C}.COMECOU`, { dia: dia(item.comecou) }) }}</li>
                <li
                  v-for="feito in item.historico"
                  :key="`${item.id}-${feito.passo}`"
                  class="break-words"
                >
                  {{
                    t(`${C}.FEZ`, {
                      dia: dia(feito.em),
                      frase: frase(item, feito.passo),
                    })
                  }}
                </li>
              </ul>
            </details>
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
  </div>
</template>
