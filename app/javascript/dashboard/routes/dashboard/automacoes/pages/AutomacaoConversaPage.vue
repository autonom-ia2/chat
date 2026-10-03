<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useCanManage } from 'dashboard/composables/useCanManage';
import AutomationAPI from 'dashboard/api/automation';
import Button from 'dashboard/components-next/button/Button.vue';
import AutonomiaGuideContainer from 'dashboard/components/autonomia/guide/AutonomiaGuideContainer.vue';
import { descreverAutomacao } from 'dashboard/helper/automacaoEmPortugues';
import AutomacaoResumo from '../components/AutomacaoResumo.vue';
import AutomacaoEnsaio from '../components/AutomacaoEnsaio.vue';
import { MODELOS, modeloExiste } from '../modelos';
import { useNomesDaConta } from '../composables/useNomesDaConta';
import {
  passoCriouAutomacao,
  passoMexeuEmAutomacao,
} from '../composables/useCriadasPeloGuia';

// #859 — nova automação ou uma já existente, montada conversando com o Guia.
// A conversa fica em cima (é a mesma do painel lateral, embutida); ao lado, o
// resumo Quando → Se → Então, o teste com casos reais e o botão Ligar.
//
// Que a automação nasce desligada nesta tela é instrução do Guia (porques.md,
// bloco `criar_automacao_conversando`), não regra no código.
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const accountId = useMapGetter('getCurrentAccountId');
const currentAccount = useMapGetter('accounts/getAccount');
const podeMudar = useCanManage('automation_manage');
const { nomes, carregarNomes } = useNomesDaConta();

const regraId = computed(() => {
  const id = Number(route.params.id);
  return Number.isInteger(id) && id > 0 ? id : null;
});

// Com id na rota, a tela já nasce carregando: sem piscar o resumo vazio antes.
const estado = ref(regraId.value ? 'carregando' : 'pronto');
const regra = ref(null);
const ligando = ref(false);

const guiaLigado = computed(
  () =>
    currentAccount.value(accountId.value)?.autonomia_guide_available === true
);

const carregar = async () => {
  if (!regraId.value) {
    regra.value = null;
    estado.value = 'pronto';
    return;
  }
  // Recarregar depois de uma resposta do Guia não pisca: o resumo antigo fica
  // até o novo chegar.
  if (!regra.value || regra.value.id !== regraId.value) {
    estado.value = 'carregando';
  }
  try {
    const { data } = await AutomationAPI.show(regraId.value);
    regra.value = data?.payload || null;
    estado.value = regra.value ? 'pronto' : 'erro';
  } catch {
    regra.value = null;
    estado.value = 'erro';
  }
};

onMounted(() => {
  carregarNomes();
  carregar();
});
watch(regraId, carregar);

const descricao = computed(() =>
  regra.value
    ? descreverAutomacao(regra.value, { t, nomes: nomes.value })
    : null
);

const titulo = computed(() => {
  if (!regraId.value) return t('AUTOMACOES.CONVERSA.TITULO_NOVA');
  return regra.value?.name || t('AUTOMACOES.CONVERSA.TITULO_EDITAR');
});

const sugestoes = computed(() =>
  MODELOS.map(modelo => ({
    rotulo: t(`AUTOMACOES.MODELOS.${modelo.chave}.TITULO`),
    pergunta: t(`AUTOMACOES.MODELOS.${modelo.chave}.PEDIDO`),
  }))
);

// O modelo que a pessoa escolheu na lista vira a primeira pergunta ao Guia.
const pedidoInicial = computed(() => {
  const modelo = String(route.query.modelo || '');
  if (regraId.value || !modeloExiste(modelo)) return '';
  return t(`AUTOMACOES.MODELOS.${modelo}.PEDIDO`);
});

// Depois de cada resposta: o Guia criou a automação → a tela passa a ser a dela;
// mexeu numa automação → o resumo é lido de novo.
const aoExecutar = execucao => {
  const passos = execucao?.passos || [];
  const criada = passos.find(passoCriouAutomacao);
  if (criada && !regraId.value) {
    router.replace({
      name: 'automacoes_editar',
      params: { accountId: accountId.value, id: criada.registro },
    });
    return;
  }
  if (passos.some(passoMexeuEmAutomacao)) carregar();
};

const voltar = () =>
  router.push({
    name: 'automacoes_lista',
    params: { accountId: accountId.value },
  });

const modoManual = () =>
  router.push({
    name: 'automation_list',
    params: { accountId: accountId.value },
    query: regraId.value ? { editar: regraId.value } : {},
  });

const mudarLigada = async ligar => {
  if (!regra.value || ligando.value) return;
  ligando.value = true;
  try {
    await AutomationAPI.update(regra.value.id, { active: ligar });
    regra.value = { ...regra.value, active: ligar };
    useAlert(
      ligar ? t('AUTOMACOES.LISTA.LIGOU') : t('AUTOMACOES.LISTA.DESLIGOU')
    );
  } catch {
    useAlert(t('AUTOMACOES.LISTA.FALHA_TROCA'));
  } finally {
    ligando.value = false;
  }
};
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <header
      class="shrink-0 flex flex-col gap-2 px-6 pt-4 pb-4 border-b border-n-weak"
    >
      <Button
        :label="$t('AUTOMACOES.CONVERSA.VOLTAR')"
        icon="i-lucide-arrow-left"
        link
        slate
        class="self-start min-h-11"
        @click="voltar"
      />
      <h1 class="text-xl font-medium text-n-slate-12 break-words">
        {{ titulo }}
      </h1>
    </header>

    <main class="flex-1 overflow-y-auto px-6 py-6">
      <div
        class="grid w-full max-w-6xl gap-6 mx-auto lg:grid-cols-[minmax(0,1fr)_22rem]"
      >
        <div class="flex flex-col gap-3 min-w-0">
          <p class="text-sm text-n-slate-11">
            {{ $t('AUTOMACOES.CONVERSA.INTRO') }}
          </p>
          <div v-if="guiaLigado" data-conversa class="h-[32rem]">
            <AutonomiaGuideContainer
              embutido
              :sugestoes="sugestoes"
              :introducao="$t('AUTOMACOES.CONVERSA.INTRO_GUIA')"
              :pedido-inicial="pedidoInicial"
              @execucao="aoExecutar"
            />
          </div>
          <div
            v-else
            data-guia-fora
            class="flex flex-col items-start gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-4"
          >
            <p class="text-sm text-n-slate-12">
              {{ $t('AUTOMACOES.CONVERSA.GUIA_FORA') }}
            </p>
            <Button
              v-if="podeMudar"
              :label="$t('AUTOMACOES.CONVERSA.MONTAR_MANUAL')"
              icon="i-lucide-sliders-horizontal"
              slate
              faded
              class="min-h-11"
              @click="modoManual"
            />
          </div>
        </div>

        <aside class="flex flex-col gap-4 min-w-0">
          <div
            v-if="estado === 'carregando'"
            data-carregando
            aria-busy="true"
            class="flex flex-col gap-3"
          >
            <span class="sr-only">
              {{ $t('AUTOMACOES.CONVERSA.CARREGANDO') }}
            </span>
            <div class="h-40 rounded-xl bg-n-alpha-2 animate-pulse" />
            <div class="h-24 rounded-xl bg-n-alpha-2 animate-pulse" />
          </div>

          <div
            v-else-if="estado === 'erro'"
            data-erro
            role="alert"
            class="flex flex-col items-start gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-4"
          >
            <p class="text-sm text-n-slate-12">
              {{ $t('AUTOMACOES.CONVERSA.ERRO') }}
            </p>
            <Button
              :label="$t('AUTOMACOES.CONVERSA.VOLTAR')"
              slate
              faded
              class="min-h-11"
              @click="voltar"
            />
          </div>

          <template v-else>
            <AutomacaoResumo :descricao="descricao" />

            <template v-if="regra">
              <div
                class="flex flex-col gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-4"
              >
                <p
                  data-situacao
                  class="text-sm"
                  :class="regra.active ? 'text-n-teal-11' : 'text-n-slate-11'"
                >
                  {{
                    regra.active
                      ? $t('AUTOMACOES.CONVERSA.LIGADA_AVISO')
                      : $t('AUTOMACOES.CONVERSA.DESLIGADA_AVISO')
                  }}
                </p>
                <template v-if="podeMudar">
                  <Button
                    v-if="!regra.active"
                    data-ligar
                    :label="$t('AUTOMACOES.CONVERSA.LIGAR')"
                    icon="i-lucide-power"
                    class="min-h-11"
                    :is-loading="ligando"
                    :disabled="ligando"
                    @click="mudarLigada(true)"
                  />
                  <Button
                    v-else
                    data-desligar
                    :label="$t('AUTOMACOES.CONVERSA.DESLIGAR')"
                    icon="i-lucide-power-off"
                    slate
                    faded
                    class="min-h-11"
                    :is-loading="ligando"
                    :disabled="ligando"
                    @click="mudarLigada(false)"
                  />
                </template>
                <p v-else class="text-sm text-n-slate-11">
                  {{ $t('AUTOMACOES.CONVERSA.SO_LEITURA') }}
                </p>
              </div>

              <AutomacaoEnsaio :regra-id="regra.id" :account-id="accountId" />

              <Button
                data-modo-manual
                :label="$t('AUTOMACOES.CONVERSA.MODO_MANUAL')"
                icon="i-lucide-sliders-horizontal"
                link
                slate
                class="self-start min-h-11"
                @click="modoManual"
              />
            </template>
            <Button
              v-else-if="podeMudar"
              data-modo-manual
              :label="$t('AUTOMACOES.CONVERSA.MONTAR_MANUAL')"
              icon="i-lucide-sliders-horizontal"
              link
              slate
              class="self-start min-h-11"
              @click="modoManual"
            />
          </template>
        </aside>
      </div>
    </main>
  </section>
</template>
