<script setup>
import { computed, nextTick, onMounted, ref, useId, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import {
  PERIODOS,
  PERIODO_PADRAO,
  SEM_MOTIVO,
  grupoDosQueNaoRenovaram,
  linhasDoRecorte,
  motivosCitados,
  periodoEscolhido,
  recortesComLinhas,
  semMotivo,
} from '../carteira/resultados';
import { chaveDoTipo } from '../carteira/tiposDeSeguro';
import { useContaDeSeguros } from '../carteira/useContaDeSeguros';
import {
  ESTADOS_DA_FICHA as ESTADOS,
  useEstadoDaFicha,
} from '../ficha/useEstadoDaFicha';
import { ABA_SEGUROS } from '../fonte/gruposDeSeguros';
import { pecaPedida } from '../fonte/modoCarteira';
import { usarDemo } from '../fonte/modoDemo';
import { renovacoesFonte } from '../fonte/renovacoesFonte';
import ErroComTentarDeNovo from '../components/comum/ErroComTentarDeNovo.vue';
import EsqueletoDeLista from '../components/comum/EsqueletoDeLista.vue';
import HeroiEscuro from '../components/comum/HeroiEscuro.vue';
import VazioComUmBotao from '../components/comum/VazioComUmBotao.vue';
import PilulasDeGrupo from '../components/comum/PilulasDeGrupo.vue';
import CartaoDaSecao from '../components/ficha/CartaoDaSecao.vue';
import LinkDeVolta from '../components/ficha/LinkDeVolta.vue';
import BarraDeResultado from '../components/carteira/renovacao/BarraDeResultado.vue';

// #2898 — "Resultados das renovações": quantos seguros a corretora renovou no
// período e por que perdeu os outros. Uma ação principal: ver quem não renovou
// (abre a aba Seguros já nesse grupo). O período muda tudo junto. Só aparece o
// que tem número: motivo que ninguém escolheu não vira barra vazia, e o
// recorte sem linha nem vira pílula. Quem o servidor não deixa ler (401 ou
// 403) lê que não tem acesso e ganha o "Voltar", em vez de "tente de novo".
// Conta sem a carteira de seguros não chama rota nenhuma e volta para a lista.
const { t } = useI18n();
const tr = (chave, valores, plural) =>
  t(`RELACIONAMENTOS_CARTEIRA.RESULTADOS.${chave}`, valores, plural);
const route = useRoute();
const router = useRouter();
const id = useId();

const demo = usarDemo(route.query);
const temCarteira = useContaDeSeguros(demo);
const fonte = renovacoesFonte({ demo, peca: pecaPedida(route.query) });

const { estado, carregar } = useEstadoDaFicha();
const resultados = ref(null);
const dias = ref(PERIODO_PADRAO);
const recortePedido = ref('');
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
// Os rótulos são `computed`: o idioma de quem usa chega depois de a tela nascer.
const opcoesDePeriodo = computed(() =>
  PERIODOS.map(quantos => ({
    value: quantos,
    label: tr(`PERIODO.DIAS_${quantos}`),
  }))
);

// As barras de "Por que não renovou": os motivos que alguém escolheu e, no
// fim, quem ficou sem motivo (a renovação foi fechada sem ninguém dizer).
const motivos = computed(() => {
  const citados = motivosCitados(periodo.value.motivos).map(
    ({ motivo, quantos }) => ({
      id: motivo,
      nome: t(
        `RELACIONAMENTOS_CARTEIRA.RENOVACAO.MOTIVO.NOME.${motivo.toUpperCase()}`
      ),
      quantos,
    })
  );
  const sem = semMotivo(periodo.value);
  return sem
    ? [...citados, { id: SEM_MOTIVO, nome: tr('SEM_MOTIVO'), quantos: sem }]
    : citados;
});

const recortes = computed(() => recortesComLinhas(periodo.value.recortes));
// O recorte à vista: o que a pessoa escolheu, se ele tem linha neste período;
// senão, o primeiro que tem.
const recorte = computed(() =>
  recortes.value.includes(recortePedido.value)
    ? recortePedido.value
    : (recortes.value[0] ?? '')
);
const pilulasDoRecorte = computed(() =>
  recortes.value.map(nome => ({
    id: nome,
    nome: tr(`RECORTE.${nome.toUpperCase()}`),
  }))
);
const linhas = computed(() =>
  linhasDoRecorte(periodo.value.recortes, recorte.value).map(linha => ({
    ...linha,
    nome: linha.tipo
      ? t(chaveDoTipo(linha.tipo))
      : linha.nome || tr('RECORTE.NAO_INFORMADO'),
  }))
);

const verGrupo = grupo =>
  router.push({
    name: 'relationships_home',
    query: { aba: ABA_SEGUROS, grupo },
  });
const voltar = () =>
  router.push({ name: 'relationships_home', query: { aba: ABA_SEGUROS } });

onMounted(async () => {
  if (!temCarteira.value) {
    router.replace({ name: 'relationships_home' });
    return;
  }
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
    <main v-if="temCarteira" class="flex-1 overflow-y-auto">
      <div
        class="flex flex-col w-full max-w-4xl gap-6 px-5 pt-8 pb-24 mx-auto md:px-8 md:pt-10 md:pb-10"
      >
        <LinkDeVolta
          :texto="tr('VOLTAR')"
          :rotulo="tr('VOLTAR_ROTULO')"
          @voltar="voltar"
        />
        <h1
          data-titulo-da-tela
          tabindex="-1"
          class="m-0 text-3xl font-bold tracking-tight outline-none md:text-4xl text-n-slate-12"
        >
          {{ tr('TITULO') }}
        </h1>

        <EsqueletoDeLista
          v-if="estado === ESTADOS.CARREGANDO"
          com-topo
          data-carteira="carregando"
        />
        <div
          v-else-if="estado === ESTADOS.SEM_ACESSO"
          data-carteira="resultados-sem-acesso"
        >
          <VazioComUmBotao
            :frase="tr('SEM_ACESSO')"
            :botao="tr('VOLTAR_ROTULO')"
            @acao="voltar"
          />
        </div>
        <div v-else-if="estado !== ESTADOS.PRONTO" data-carteira="erro">
          <ErroComTentarDeNovo
            :mensagem="tr('ERRO')"
            @tentar="carregar(buscar)"
          />
        </div>
        <template v-else-if="periodo">
          <HeroiEscuro v-if="periodo.venceram" data-carteira="resultados-heroi">
            <template #frase>
              {{
                tr(
                  `HEROI.DIAS_${dias}`,
                  { renovou: periodo.renovou, count: periodo.venceram },
                  periodo.venceram
                )
              }}
            </template>
            <template v-if="periodo.naoRenovou" #acao>
              <Button
                size="lg"
                class="!bg-white !text-n-heroi font-semibold hover:enabled:!bg-white/90 focus-visible:!bg-white/90 focus-visible:!outline-white dark:!bg-white dark:!text-n-heroi basis-full sm:basis-auto whitespace-nowrap"
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
              v-if="motivos.length"
              data-carteira="motivos"
              :titulo="tr('MOTIVOS')"
            >
              <ul class="p-0 m-0 list-none divide-y divide-n-weak">
                <BarraDeResultado
                  v-for="motivo in motivos"
                  :key="motivo.id"
                  :data-motivo="motivo.id"
                  :nome="motivo.nome"
                  :valor="String(motivo.quantos)"
                  :parte="motivo.quantos"
                  :total="periodo.naoRenovou"
                />
              </ul>
            </CartaoDaSecao>

            <CartaoDaSecao
              v-if="recorte"
              data-carteira="recorte"
              :titulo="tr('RECORTE.TITULO')"
            >
              <div class="flex flex-col gap-2">
                <PilulasDeGrupo
                  v-if="pilulasDoRecorte.length > 1"
                  :model-value="recorte"
                  :grupos="pilulasDoRecorte"
                  :rotulo="tr('RECORTE.ROTULO')"
                  @update:model-value="recortePedido = $event"
                />
                <ul
                  aria-live="polite"
                  class="p-0 m-0 list-none divide-y divide-n-weak"
                >
                  <!-- Duas pessoas (ou seguradoras) podem ter o mesmo nome:
                       a chave é a posição da linha dentro do recorte. -->
                  <BarraDeResultado
                    v-for="(linha, posicao) in linhas"
                    :key="`${recorte}-${posicao}`"
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
            {{
              tr(
                'VENCEM_30',
                { count: resultados.vencem30 },
                resultados.vencem30
              )
            }}
            <Button
              link
              size="lg"
              class="min-h-11"
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
