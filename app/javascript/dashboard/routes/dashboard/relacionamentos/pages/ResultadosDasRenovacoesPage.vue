<script setup>
import { computed, nextTick, onMounted, ref, useId, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import {
  PERIODOS,
  PERIODO_PADRAO,
  RECORTES,
  grupoDosQueNaoRenovaram,
  periodoEscolhido,
} from '../carteira/resultados';
import { chaveDoTipo } from '../carteira/tiposDeSeguro';
import {
  ESTADOS_DA_FICHA as ESTADOS,
  useEstadoDaFicha,
} from '../ficha/useEstadoDaFicha';
import { pecaPedida } from '../fonte/modoCarteira';
import { usarDemo } from '../fonte/modoDemo';
import { renovacoesFonte } from '../fonte/renovacoesFonte';
import ErroComTentarDeNovo from '../components/comum/ErroComTentarDeNovo.vue';
import EsqueletoDeLista from '../components/comum/EsqueletoDeLista.vue';
import HeroiEscuro from '../components/comum/HeroiEscuro.vue';
import PilulasDeGrupo from '../components/comum/PilulasDeGrupo.vue';
import CartaoDaSecao from '../components/ficha/CartaoDaSecao.vue';
import LinkDeVolta from '../components/ficha/LinkDeVolta.vue';
import BarraDeResultado from '../components/carteira/renovacao/BarraDeResultado.vue';

// #2897 — "Resultados das renovações": quantos seguros a corretora renovou no
// período e por que perdeu os outros. Uma ação principal: ver quem não renovou
// (abre a aba Seguros já nesse grupo). O período muda tudo junto.
const { t } = useI18n();
const tr = (chave, valores, plural) =>
  t(`RELACIONAMENTOS_CARTEIRA.RESULTADOS.${chave}`, valores, plural);
const route = useRoute();
const router = useRouter();
const id = useId();
const fonte = renovacoesFonte({
  demo: usarDemo(route.query),
  peca: pecaPedida(route.query),
});

const { estado, carregar } = useEstadoDaFicha();
const resultados = ref(null);
const dias = ref(PERIODO_PADRAO);
const recorte = ref(RECORTES[0]);
const raiz = useTemplateRef('raiz');

const buscar = async aindaVale => {
  const achados = await fonte.resultados();
  if (!aindaVale()) return false;
  resultados.value = achados;
  return true;
};

const periodo = computed(() =>
  periodoEscolhido(resultados.value?.periodos, dias.value)
);
const opcoesDePeriodo = PERIODOS.map(quantos => ({
  value: quantos,
  label: tr(`PERIODO.${quantos}`),
}));
const motivos = computed(() =>
  periodo.value.motivos.map(({ motivo, quantos }) => ({
    id: motivo,
    nome: t(
      `RELACIONAMENTOS_CARTEIRA.RENOVACAO.MOTIVO.NOME.${motivo.toUpperCase()}`
    ),
    quantos,
  }))
);
const pilulasDoRecorte = RECORTES.map(nome => ({
  id: nome,
  nome: tr(`RECORTE.${nome.toUpperCase()}`),
}));
const linhasDoRecorte = computed(() =>
  periodo.value.recortes[recorte.value].map(linha => ({
    ...linha,
    nome: linha.tipo ? t(chaveDoTipo(linha.tipo)) : linha.nome,
  }))
);

const verGrupo = grupo =>
  router.push({
    name: 'relationships_home',
    query: { aba: 'seguros', grupo },
  });
const voltar = () =>
  router.push({ name: 'relationships_home', query: { aba: 'seguros' } });

onMounted(async () => {
  carregar(buscar);
  await nextTick();
  raiz.value?.querySelector('[data-titulo-da-tela]')?.focus();
});
</script>

<template>
  <section
    ref="raiz"
    data-carteira="resultados"
    class="flex flex-col w-full h-full bg-n-surface-1"
  >
    <main class="flex-1 overflow-y-auto">
      <div
        class="flex flex-col w-full max-w-4xl gap-6 px-5 pt-8 pb-24 mx-auto md:px-8 md:pt-10 md:pb-10"
      >
        <LinkDeVolta
          :texto="t('RELACIONAMENTOS_CARTEIRA.AJUSTES.VOLTAR')"
          :rotulo="tr('VOLTAR')"
          @voltar="voltar"
        />
        <h1
          data-titulo-da-tela
          tabindex="-1"
          class="m-0 text-2xl font-bold tracking-tight outline-none text-n-slate-12"
        >
          {{ tr('TITULO') }}
        </h1>

        <EsqueletoDeLista
          v-if="estado === ESTADOS.CARREGANDO"
          com-topo
          data-carteira="carregando"
        />
        <div v-else-if="estado !== ESTADOS.PRONTO" data-carteira="erro">
          <ErroComTentarDeNovo
            :mensagem="tr('ERRO')"
            @tentar="carregar(buscar)"
          />
        </div>
        <template v-else>
          <HeroiEscuro v-if="periodo.venceram" data-carteira="resultados-heroi">
            <template #frase>
              {{
                tr(
                  `HEROI.${dias}`,
                  { renovou: periodo.renovou, count: periodo.venceram },
                  periodo.venceram
                )
              }}
            </template>
            <template v-if="periodo.naoRenovou" #acao>
              <Button
                size="lg"
                class="!bg-white !text-n-heroi font-semibold hover:enabled:!bg-white/90 focus-visible:!bg-white/90 focus-visible:!outline-white dark:!bg-white dark:!text-n-heroi"
                data-carteira="ver-nao-renovaram"
                :label="
                  tr(
                    'VER_NAO_RENOVARAM',
                    { count: periodo.naoRenovou },
                    periodo.naoRenovou
                  )
                "
                @click="verGrupo(grupoDosQueNaoRenovaram(dias))"
              />
            </template>
          </HeroiEscuro>

          <div data-carteira="periodo" class="flex items-center gap-3">
            <label :for="`${id}-periodo`" class="text-base text-n-slate-12">
              {{ tr('PERIODO.ROTULO') }}
            </label>
            <ChoiceSelect
              v-model="dias"
              :trigger-id="`${id}-periodo`"
              :options="opcoesDePeriodo"
              :aria-label="tr('PERIODO.ROTULO')"
            />
          </div>

          <p
            v-if="!periodo.venceram"
            data-carteira="resultados-vazio"
            role="status"
            class="m-0 text-lg text-n-slate-12"
          >
            {{ tr('VAZIO') }}
          </p>
          <template v-else>
            <CartaoDaSecao
              v-if="periodo.naoRenovou"
              data-carteira="motivos"
              :titulo="tr('MOTIVOS')"
            >
              <ul class="p-0 m-0 list-none divide-y divide-n-weak">
                <BarraDeResultado
                  v-for="motivo in motivos"
                  :key="motivo.id"
                  :nome="motivo.nome"
                  :valor="String(motivo.quantos)"
                  :parte="motivo.quantos"
                  :total="periodo.naoRenovou"
                />
              </ul>
            </CartaoDaSecao>

            <CartaoDaSecao
              data-carteira="recorte"
              :titulo="tr('RECORTE.TITULO')"
            >
              <div class="flex flex-col gap-2">
                <PilulasDeGrupo
                  v-model="recorte"
                  :grupos="pilulasDoRecorte"
                  :rotulo="tr('RECORTE.ROTULO')"
                />
                <ul
                  aria-live="polite"
                  class="p-0 m-0 list-none divide-y divide-n-weak"
                >
                  <BarraDeResultado
                    v-for="linha in linhasDoRecorte"
                    :key="linha.nome"
                    :nome="linha.nome"
                    :valor="
                      tr(
                        'RENOVARAM',
                        { count: linha.renovou, total: linha.venceram },
                        linha.renovou
                      )
                    "
                    :parte="linha.renovou"
                    :total="linha.venceram"
                  />
                </ul>
              </div>
            </CartaoDaSecao>
          </template>

          <p
            v-if="resultados.vencem30"
            data-carteira="vencem-30"
            class="flex flex-wrap items-center m-0 text-base gap-x-3 text-n-slate-12"
          >
            {{ tr('VENCEM_30', { count: resultados.vencem30 }) }}
            <Button
              link
              size="lg"
              data-carteira="ver-quais"
              :label="tr('VER_QUAIS')"
              @click="verGrupo('vence_30_dias')"
            />
          </p>
        </template>
      </div>
    </main>
  </section>
</template>
