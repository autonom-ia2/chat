<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import api from '../api/modelosWhatsapp';
import { SITUACOES } from '../constants';
import { diaEMes, hora, haQuantoTempo, numero } from '../helpers/datas';
import { usePodeCriarModelo } from '../helpers/usePodeCriarModelo';
import ModeloApagar from '../components/ModeloApagar.vue';
import ModeloCelular from '../components/ModeloCelular.vue';
import ModeloSelo from '../components/ModeloSelo.vue';
import ModeloUsos from '../components/ModeloUsos.vue';
import CampanhasParadas from '../components/CampanhasParadas.vue';

// Um modelo (jornadas 1, 3, 4 e 5): a mensagem no celular, a situação
// explicada com a próxima ação, onde ele está em uso e o que dá para fazer.
const { t, locale } = useI18n();
const route = useRoute();
const router = useRouter();
const podeCriar = usePodeCriarModelo();

const estado = ref('carregando');
const modelo = ref(null);
const numeros = ref([]);
const usos = ref([]);
const campanhasParadas = ref([]);
const apagar = ref(null);
const apagando = ref(false);

// Pedido de revisão de uma recusa só existe no Gerenciador do WhatsApp.
const GERENCIADOR_DO_WHATSAPP =
  'https://business.facebook.com/wa/manage/message-templates/';

const carregar = async () => {
  estado.value = 'carregando';
  try {
    const [dados, listaDeNumeros, listaDeUsos, paradas] = await Promise.all([
      api.obterModelo(route.params.id),
      api.listarNumeros(),
      api.ondeEstaEmUso(route.params.id),
      api.listarCampanhasParadas(),
    ]);
    campanhasParadas.value = paradas.filter(
      campanha => campanha.modeloId === dados.id
    );
    modelo.value = dados;
    numeros.value = listaDeNumeros;
    usos.value = listaDeUsos;
    estado.value = 'pronto';
  } catch {
    estado.value = 'erro';
  }
};

onMounted(carregar);

const nomesDosNumeros = computed(() =>
  numeros.value
    .filter(item => modelo.value.numeros.includes(item.id))
    .map(item => item.nome)
);

const contaDoModelo = computed(
  () =>
    numeros.value.find(item => modelo.value.numeros.includes(item.id))?.conta
      ?.nome || ''
);

const situacao = computed(() => modelo.value.situacao);
const caixa = computed(() => SITUACOES[situacao.value].caixa);

const explicacao = computed(() => {
  const base = `MODELOS_WHATSAPP.SITUACOES.${situacao.value}`;
  if (situacao.value === 'em_analise') {
    return t(`${base}.EXPLICACAO`, {
      quando: haQuantoTempo(modelo.value.enviadoEm, locale.value),
    });
  }
  if (situacao.value === 'pausado') {
    return t(`${base}.EXPLICACAO`, {
      quando: haQuantoTempo(modelo.value.pausa.desde, locale.value),
    });
  }
  if (situacao.value === 'recusado') {
    return t(
      `MODELOS_WHATSAPP.RECUSAS.${modelo.value.recusa?.codigo || 'outro'}.EXPLICACAO`
    );
  }
  return t(`${base}.EXPLICACAO`, {
    n: numero(modelo.value.enviosNoMes, locale.value),
  });
});

const dica = computed(() => {
  if (situacao.value === 'recusado') {
    return t(
      `MODELOS_WHATSAPP.RECUSAS.${modelo.value.recusa?.codigo || 'outro'}.COMO_RESOLVER`
    );
  }
  if (situacao.value === 'pausado') {
    return t('MODELOS_WHATSAPP.SITUACOES.pausado.DICA');
  }
  return '';
});

// Alteração de modelo aprovado: 1 a cada 24 h e até 10 em 30 dias (regra do
// WhatsApp). Fora disso, o botão diz quando volta a poder.
const alteracaoTravada = computed(() => {
  const { restantesNoMes, liberadaEm } = modelo.value.edicoes;
  if (restantesNoMes <= 0) return t('MODELOS_WHATSAPP.MODELO.SEM_ALTERACOES');
  if (liberadaEm && new Date(liberadaEm) > new Date()) {
    return t('MODELOS_WHATSAPP.MODELO.ALTERAR_DEPOIS', {
      dia: diaEMes(liberadaEm, locale.value),
      hora: hora(liberadaEm, locale.value),
    });
  }
  return '';
});

// Apagar fica bloqueado enquanto houver uso que ainda vai sair.
const usoAgendado = computed(() => usos.value.some(uso => uso.agendado));

const ir = name =>
  router.push({ name, params: { id: modelo.value.id } });

const duplicar = () =>
  router.push({
    name: 'modelos_whatsapp_novo',
    query: { de: modelo.value.id, etapa: 'texto' },
  });

const confirmarApagar = async () => {
  apagando.value = true;
  try {
    const { nomeBloqueadoAte } = await api.apagarModelo(modelo.value.id);
    apagar.value?.close();
    useAlert(
      t('MODELOS_WHATSAPP.APAGAR.FEITO', {
        dia: diaEMes(nomeBloqueadoAte, locale.value),
      })
    );
    router.push({ name: 'modelos_whatsapp_lista' });
  } catch {
    useAlert(t('MODELOS_WHATSAPP.APAGAR.FALHOU'));
  } finally {
    apagando.value = false;
  }
};
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <main class="flex-1 overflow-y-auto">
      <div
        class="flex flex-col w-full gap-6 px-5 pt-8 pb-24 mx-auto max-w-6xl md:px-8 md:py-10"
      >
        <router-link
          :to="{ name: 'modelos_whatsapp_lista' }"
          class="inline-flex items-center self-start gap-2 text-[0.9375rem] font-medium rounded-lg min-h-11 text-n-blue-11 hover:underline"
        >
          <span class="i-lucide-arrow-left size-4 rtl:rotate-180" aria-hidden="true" />
          {{ $t('MODELOS_WHATSAPP.MODELO.VOLTAR') }}
        </router-link>

        <div
          v-if="estado === 'carregando'"
          aria-busy="true"
          class="h-96 rounded-3xl bg-n-alpha-2 animate-pulse"
        >
          <span class="sr-only">{{ $t('MODELOS_WHATSAPP.CARREGANDO') }}</span>
        </div>

        <p
          v-else-if="estado === 'erro'"
          role="alert"
          class="p-8 mb-0 text-base border rounded-2xl border-n-weak bg-n-solid-1 text-n-slate-12"
        >
          {{ $t('MODELOS_WHATSAPP.MODELO.NAO_ACHOU') }}
        </p>

        <template v-else>
          <header class="flex flex-col gap-2">
            <div class="flex flex-wrap items-center gap-3">
              <h1
                class="m-0 text-3xl font-bold tracking-tight break-words md:text-4xl text-n-slate-12"
              >
                {{ modelo.nome }}
              </h1>
              <ModeloSelo :situacao="situacao" />
            </div>
            <p class="mb-0 text-base text-n-slate-11">
              {{
                $t('MODELOS_WHATSAPP.MODELO.VALE_PARA', {
                  numeros: nomesDosNumeros.join(', '),
                })
              }}
            </p>
          </header>

          <div
            class="grid items-start gap-8 lg:grid-cols-[minmax(0,1fr)_20rem]"
          >
            <div class="flex flex-col min-w-0 gap-5">
              <section
                data-situacao
                class="flex flex-col items-start gap-3 p-6 rounded-2xl ring-1 ring-inset"
                :class="caixa"
              >
                <h2 class="m-0 text-lg font-semibold text-n-slate-12">
                  {{ $t(`MODELOS_WHATSAPP.SITUACOES.${situacao}.TITULO`) }}
                </h2>
                <p class="mb-0 text-base leading-relaxed text-n-slate-12">
                  {{ explicacao }}
                </p>
                <p
                  v-if="dica"
                  class="mb-0 text-base leading-relaxed text-n-slate-11"
                >
                  <strong class="font-semibold text-n-slate-12">
                    {{ $t('MODELOS_WHATSAPP.MODELO.COMO_RESOLVER') }}
                  </strong>
                  {{ dica }}
                </p>
                <div class="flex flex-wrap items-center gap-3 mt-1">
                  <Button
                    v-if="situacao === 'pronto'"
                    data-usar
                    :label="$t('MODELOS_WHATSAPP.ACOES.USAR')"
                    icon="i-lucide-send"
                    size="lg"
                    class="!min-h-12 !rounded-xl"
                    @click="ir('modelos_whatsapp_usar')"
                  />
                  <Button
                    v-else-if="situacao === 'recusado' && podeCriar && !modelo.sistema"
                    data-corrigir
                    :label="$t('MODELOS_WHATSAPP.ACOES.CORRIGIR')"
                    icon="i-lucide-wrench"
                    size="lg"
                    color="ruby"
                    class="!min-h-12 !rounded-xl"
                    @click="ir('modelos_whatsapp_alterar')"
                  />
                  <Button
                    v-else-if="situacao === 'pausado' && podeCriar && !modelo.sistema"
                    data-alterar-texto
                    :label="$t('MODELOS_WHATSAPP.ACOES.ALTERAR_TEXTO')"
                    icon="i-lucide-pencil"
                    size="lg"
                    class="!min-h-12 !rounded-xl"
                    @click="ir('modelos_whatsapp_alterar')"
                  />
                  <a
                    v-if="situacao === 'recusado'"
                    data-pedir-revisao
                    :href="GERENCIADOR_DO_WHATSAPP"
                    target="_blank"
                    rel="noopener noreferrer"
                    class="inline-flex items-center gap-1.5 px-2 text-[0.9375rem] font-medium rounded-lg min-h-11 text-n-blue-11 hover:underline"
                  >
                    {{ $t('MODELOS_WHATSAPP.MODELO.PEDIR_REVISAO') }}
                    <span class="i-lucide-external-link size-4" aria-hidden="true" />
                  </a>
                </div>
              </section>

              <section
                v-if="modelo.sistema"
                data-sistema
                class="flex gap-3 p-5 rounded-2xl bg-n-iris-2 ring-1 ring-inset ring-n-iris-6"
              >
                <span class="i-lucide-cog size-5 mt-0.5 shrink-0 text-n-iris-11" aria-hidden="true" />
                <p class="mb-0 text-[0.9375rem] leading-relaxed text-n-slate-12">
                  {{ $t('MODELOS_WHATSAPP.SISTEMA.EXPLICA') }}
                </p>
              </section>

              <CampanhasParadas
                v-if="campanhasParadas.length"
                :campanhas="campanhasParadas"
                no-modelo
              />

              <section
                v-if="modelo.tipoMudouPeloWhatsapp"
                data-tipo-mudou
                class="flex gap-3 p-5 rounded-2xl bg-n-amber-2 ring-1 ring-inset ring-n-amber-6"
              >
                <span class="i-lucide-info size-5 mt-0.5 shrink-0 text-n-amber-11" aria-hidden="true" />
                <p class="mb-0 text-[0.9375rem] leading-relaxed text-n-slate-12">
                  {{
                    $t('MODELOS_WHATSAPP.MODELO.TIPO_MUDOU', {
                      tipo: $t(`MODELOS_WHATSAPP.TIPOS.${modelo.tipo}.ROTULO`),
                    })
                  }}
                </p>
              </section>

              <dl
                class="grid gap-4 p-6 m-0 sm:grid-cols-2 rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1"
              >
                <div class="flex flex-col gap-1">
                  <dt class="text-sm text-n-slate-10">
                    {{ $t('MODELOS_WHATSAPP.MODELO.TIPO') }}
                  </dt>
                  <dd class="m-0 text-base font-medium text-n-slate-12">
                    {{ $t(`MODELOS_WHATSAPP.TIPOS.${modelo.tipo}.ROTULO`) }}
                    <span class="block text-sm font-normal text-n-slate-11">
                      {{ $t(`MODELOS_WHATSAPP.TIPOS.${modelo.tipo}.CUSTO`) }}
                    </span>
                  </dd>
                </div>
                <div class="flex flex-col gap-1">
                  <dt class="text-sm text-n-slate-10">
                    {{ $t('MODELOS_WHATSAPP.MODELO.CONTA') }}
                  </dt>
                  <dd class="m-0 text-base font-medium text-n-slate-12">
                    {{ contaDoModelo }}
                    <span class="block text-sm font-normal text-n-slate-11">
                      {{ $t('MODELOS_WHATSAPP.MODELO.CONTA_EXPLICA') }}
                    </span>
                  </dd>
                </div>
              </dl>

              <ModeloUsos :usos="usos" />

              <details class="px-6 py-4 rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1 group">
                <summary class="text-[0.9375rem] font-medium cursor-pointer min-h-11 flex items-center text-n-slate-11">
                  {{ $t('MODELOS_WHATSAPP.MODELO.DETALHES') }}
                </summary>
                <p class="mt-2 mb-0 text-sm text-n-slate-11">
                  {{
                    $t('MODELOS_WHATSAPP.MODELO.NOME_NO_WHATSAPP', {
                      nome: modelo.nomeNoWhatsapp,
                    })
                  }}
                </p>
              </details>

              <div
                v-if="podeCriar"
                data-acoes
                class="flex flex-col gap-2"
              >
                <div class="flex flex-wrap items-center gap-2">
                  <Button
                    v-if="situacao === 'pronto' && !modelo.sistema"
                    data-alterar
                    :label="$t('MODELOS_WHATSAPP.ACOES.ALTERAR')"
                    icon="i-lucide-pencil"
                    color="slate"
                    variant="faded"
                    class="min-h-11"
                    :disabled="Boolean(alteracaoTravada)"
                    @click="ir('modelos_whatsapp_alterar')"
                  />
                  <Button
                    data-duplicar
                    :label="$t('MODELOS_WHATSAPP.ACOES.DUPLICAR')"
                    icon="i-lucide-copy"
                    color="slate"
                    variant="faded"
                    class="min-h-11"
                    @click="duplicar"
                  />
                  <Button
                    v-if="!modelo.sistema"
                    data-apagar
                    :label="$t('MODELOS_WHATSAPP.ACOES.APAGAR')"
                    icon="i-lucide-trash-2"
                    color="ruby"
                    variant="ghost"
                    class="min-h-11"
                    @click="apagar?.open()"
                  />
                </div>
                <p
                  v-if="situacao === 'pronto' && !modelo.sistema"
                  class="mb-0 text-sm text-n-slate-10"
                >
                  {{
                    alteracaoTravada ||
                    $t(
                      'MODELOS_WHATSAPP.MODELO.ALTERACOES_RESTANTES',
                      { n: modelo.edicoes.restantesNoMes },
                      modelo.edicoes.restantesNoMes
                    )
                  }}
                </p>
              </div>
            </div>

            <ModeloCelular
              :conteudo="modelo.conteudo"
              :remetente="contaDoModelo"
              class="lg:sticky lg:top-6"
            />
          </div>

          <ModeloApagar
            ref="apagar"
            :nome="modelo.nome"
            :usos="usos"
            :numeros="nomesDosNumeros"
            :apagando="apagando"
            :bloqueado="usoAgendado"
            @confirmar="confirmarApagar"
          />
        </template>
      </div>
    </main>
  </section>
</template>
