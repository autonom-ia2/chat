<script setup>
import {
  computed,
  nextTick,
  onBeforeUnmount,
  useTemplateRef,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import { usePermissionGranted } from 'dashboard/composables/useCanManage';
import { trazerAggerFonte } from '../../../../fonte/trazerAggerFonte';
import {
  ETAPAS_DO_AGGER,
  PEDE_LOGIN,
  PEDIR_LOGIN,
  useBuscaNoAgger,
} from '../../../../carteira/useBuscaNoAgger';
import BuscaDeTodoDia from './BuscaDeTodoDia.vue';
import DialogoDoLoginNoAgger from './DialogoDoLoginNoAgger.vue';
import HistoricoDasBuscas from './HistoricoDasBuscas.vue';
import PorQueNaoDeu from './PorQueNaoDeu.vue';
import ProntoDoAgger from './ProntoDoAgger.vue';
import SeguradorasDaBusca from './SeguradorasDaBusca.vue';
import EtapasDoTrazer from '../EtapasDoTrazer.vue';
import VoltarDoTrazer from '../VoltarDoTrazer.vue';

// #2900 (E7.3) — "Trazer do Agger": um botão grande busca os seguros da
// corretora no Agger. Se a conta ainda não conectou o Agger, uma janela pede
// só o login e a senha. A busca roda no servidor (a pessoa pode sair e
// voltar) e traz na hora o que o Agger já tem, sem esperar o robô do Agger
// buscar nas seguradoras (#2900, E7.5). O Conferir começa pelo que importa —
// quantos seguros entram, de quantas pessoas, e o "Trazer" — e as seguradoras
// com o login faltando ou recusado no Agger (só com evidência) viram uma linha
// calma, com o detalhe atrás de "Ver quais seguradoras"; o que não deu para
// trazer tem "Ver por quê" (#2900, E7.6). O fim diz o que entrou e, do que não
// entrou, por quê (ProntoDoAgger). Depois, a busca de todo dia traz os seguros
// novos sozinha (o interruptor liga e desliga) e as buscas já feitas ficam
// embaixo, com Desfazer.
//
// Sem botão desligado: sem seguro pronto, o "Trazer" não aparece e a frase do
// que fazer fica no lugar. Toda espera que pode falhar tem "Tentar de novo". A
// cada etapa nova, o foco vai ao título.
//
// Escrever o login do Agger é de quem pode mexer na Cotação
// (`insurance_manage`, como o servidor). Sem essa permissão, a tela não
// oferece a janela do login: diz para pedir a quem administra a conta.
//
// #3057 — no topo, a volta a "Como trazer" (VoltarDoTrazer) e as etapas da
// jornada (Buscar → Conferir → Pronto). O começo explica em 3 passos curtos o
// que acontece, mostra o selo de confiança (a senha fica guardada em segredo e
// serve só para buscar os seguros) e o botão principal, grande.
const props = defineProps({
  fonte: { type: Object, default: () => trazerAggerFonte() },
  // O login do Agger da conta já foi aceito (o resumo da carteira).
  ligado: { type: Boolean, default: false },
  // O Agger recusou o login guardado (o resumo da carteira, `aggerPedeLogin`).
  pedeLogin: { type: Boolean, default: false },
});

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const titulo = useTemplateRef('titulo');
const login = useTemplateRef('login');
const historico = useTemplateRef('historico');
const podeLigar = usePermissionGranted('insurance_manage');

const busca = useBuscaNoAgger(props.fonte, {
  ligado: props.ligado && !props.pedeLogin,
  aoMudarBusca: id =>
    router.replace({ query: { ...route.query, busca: id ?? undefined } }),
});
const {
  etapa,
  busca: atual,
  andamento,
  erro,
  ocupado,
  semAcompanhar,
  parado,
  conectado,
} = busca;

const parou = computed(() => atual.value?.estado === 'parou');
// A busca parou porque o Agger recusou o login (a prop `pedeLogin` é o mesmo,
// mas da conta, vindo do resumo).
const parouPeloLogin = computed(
  () => parou.value && atual.value?.motivo === PEDE_LOGIN
);
const fraseDaParada = computed(() =>
  parouPeloLogin.value
    ? t('RELACIONAMENTOS_CARTEIRA.AGGER.PAROU.PEDE_LOGIN')
    : t('RELACIONAMENTOS_CARTEIRA.AGGER.PAROU.FALHOU')
);
const podeTentarDeNovo = computed(
  () =>
    semAcompanhar.value ||
    parado.value ||
    (parou.value && !parouPeloLogin.value)
);
// O leitor de tela ouve "ocupado" só enquanto o servidor trabalha de fato: não
// na busca que parou, nem quando a espera emperrou e pede "Tentar de novo".
const trabalhando = computed(() => !semAcompanhar.value && !parado.value);
// O que fazer quando a busca parou. Sem poder escrever o login, pedir.
const fazerDaParada = computed(() => {
  if (parouPeloLogin.value && !podeLigar.value) {
    return t('RELACIONAMENTOS_CARTEIRA.AGGER.PECA_AO_ADMIN');
  }
  return parouPeloLogin.value
    ? t('RELACIONAMENTOS_CARTEIRA.AGGER.PAROU.PEDE_LOGIN_FAZER')
    : t('RELACIONAMENTOS_CARTEIRA.AGGER.PAROU.FALHOU_FAZER');
});
// Sem o login aceito e sem poder escrevê-lo, não há janela para abrir.
const pedirAoAdmin = computed(() => !conectado.value && !podeLigar.value);
const loginRecusadoNaConta = computed(
  () => props.pedeLogin && !conectado.value
);
const rotuloDeTrazer = seguros =>
  t(
    'RELACIONAMENTOS_CARTEIRA.AGGER.CONFERIR.TRAZER',
    { count: seguros },
    seguros
  );
const fraseDosNumeros = computed(() =>
  [
    t(
      'RELACIONAMENTOS_CARTEIRA.AGGER.CONFERIR.ENTRAM',
      { count: atual.value.seguros },
      atual.value.seguros
    ),
    t(
      'RELACIONAMENTOS_CARTEIRA.AGGER.CONFERIR.DE_PESSOAS',
      { count: atual.value.pessoas },
      atual.value.pessoas
    ),
  ].join(' ')
);
const fraseDoTrazendo = computed(() =>
  t('RELACIONAMENTOS_CARTEIRA.AGGER.TRAZENDO', {
    porcentagem: andamento.value?.porcentagem ?? 0,
  })
);
const seguradoras = computed(() => atual.value?.porSeguradora ?? []);
const temDetalhes = computed(() =>
  ['jaNaCarteira', 'pessoasNovas', 'semTelefone'].some(
    numero => atual.value?.[numero]
  )
);

const ETAPAS_DA_JORNADA = ['BUSCAR', 'CONFERIR', 'PRONTO'];
const NA_JORNADA = {
  [ETAPAS_DO_AGGER.INICIO]: 0,
  [ETAPAS_DO_AGGER.BUSCANDO]: 0,
  [ETAPAS_DO_AGGER.CONFERIR]: 1,
  [ETAPAS_DO_AGGER.TRAZENDO]: 1,
  [ETAPAS_DO_AGGER.PRONTO]: 2,
};
const naJornada = computed(() => NA_JORNADA[etapa.value] ?? 0);
const PASSOS = ['UM', 'DOIS', 'TRES'];

watch(etapa, async () => {
  await nextTick();
  titulo.value?.focus();
});

// Sem o login aceito, a janela do login abre antes da primeira busca.
const comecar = async () => {
  if ((await busca.comecar()) === PEDIR_LOGIN) login.value?.abrir();
};

const continuar = id => {
  router.replace({ query: { ...route.query, busca: id } });
  busca.abrir(id);
};

const voltarAoInicio = () => {
  busca.recomecar();
  historico.value?.carregar();
};

const verOsSeguros = () =>
  router.push({ name: 'relationships_home', query: { aba: 'seguros' } });

if (route.query.busca) busca.abrir(Number(route.query.busca));
onBeforeUnmount(busca.parar);
</script>

<template>
  <section
    data-relacionamentos="trazer-agger"
    class="flex flex-col w-full h-full overflow-y-auto bg-n-surface-1"
  >
    <div
      class="flex flex-col w-full max-w-3xl gap-6 px-5 py-8 mx-auto md:px-8 md:py-10"
    >
      <VoltarDoTrazer para="como" />
      <EtapasDoTrazer :etapas="ETAPAS_DA_JORNADA" :atual="naJornada" />
      <h1
        ref="titulo"
        data-titulo-da-tela
        tabindex="-1"
        class="m-0 text-3xl font-bold tracking-tight outline-none md:text-4xl text-n-slate-12 text-balance"
      >
        {{ t('RELACIONAMENTOS_CARTEIRA.AGGER.TITULO') }}
      </h1>
      <p v-if="erro" role="alert" class="m-0 text-base text-n-ruby-11">
        {{ t(erro) }}
      </p>

      <template v-if="etapa === ETAPAS_DO_AGGER.INICIO">
        <div
          data-carteira="inicio-do-agger"
          class="flex flex-col gap-6 p-5 shadow-sm sm:p-8 rounded-3xl bg-n-solid-1 ring-1 ring-n-weak"
        >
          <p class="m-0 text-lg text-n-slate-12 text-pretty">
            {{ t('RELACIONAMENTOS_CARTEIRA.AGGER.APOIO') }}
          </p>
          <ol
            data-carteira="passos-do-agger"
            class="flex flex-col gap-4 p-0 m-0 list-none"
          >
            <li
              v-for="(passo, indice) in PASSOS"
              :key="passo"
              class="flex items-start gap-3"
            >
              <span
                aria-hidden="true"
                class="flex items-center justify-center text-sm font-semibold rounded-full size-8 shrink-0 bg-n-blue-3 text-n-blue-11 tabular-nums"
              >
                {{ indice + 1 }}
              </span>
              <span class="pt-1 text-base text-n-slate-12 text-pretty">
                {{ t(`RELACIONAMENTOS_CARTEIRA.AGGER.PASSOS.${passo}`) }}
              </span>
            </li>
          </ol>
          <p
            data-carteira="selo-do-agger"
            class="flex items-start gap-3 p-4 m-0 text-sm font-medium rounded-2xl bg-n-teal-2 text-n-teal-11 ring-1 ring-inset ring-n-teal-5"
          >
            <span
              class="i-lucide-lock-keyhole size-5 shrink-0"
              aria-hidden="true"
            />
            <span>{{ t('RELACIONAMENTOS_CARTEIRA.AGGER.SELO') }}</span>
          </p>
          <p
            v-if="pedirAoAdmin"
            data-carteira="peca-ao-admin"
            class="m-0 text-base font-medium text-n-slate-12"
          >
            {{ t('RELACIONAMENTOS_CARTEIRA.AGGER.PECA_AO_ADMIN') }}
          </p>
          <Button
            v-else
            size="lg"
            type="button"
            icon="i-lucide-cloud-download"
            data-carteira="buscar-no-agger"
            class="w-full sm:w-auto sm:self-start !h-14 !px-4 !text-base sm:!px-8 sm:!text-lg"
            :is-loading="ocupado"
            :label="t('RELACIONAMENTOS_CARTEIRA.AGGER.BUSCAR')"
            @click="comecar"
          />
        </div>
        <BuscaDeTodoDia
          :fonte="fonte"
          :pede-login="loginRecusadoNaConta"
          :pode-ligar="podeLigar"
          @entrar="login?.abrir()"
        />
        <HistoricoDasBuscas
          ref="historico"
          :fonte="fonte"
          @continuar="continuar"
        />
      </template>

      <template v-else-if="etapa === ETAPAS_DO_AGGER.BUSCANDO">
        <p
          v-if="!parou"
          role="status"
          data-carteira="buscando-no-agger"
          :aria-busy="trabalhando ? 'true' : 'false'"
          class="p-8 m-0 text-lg text-center border rounded-3xl border-n-weak bg-n-solid-1 text-n-slate-12 text-balance"
        >
          {{ t('RELACIONAMENTOS_CARTEIRA.AGGER.BUSCANDO') }}
        </p>
        <div
          v-else
          role="status"
          data-carteira="busca-parou"
          class="flex flex-col gap-2 p-6 border rounded-3xl border-n-amber-6 bg-n-amber-2"
        >
          <span class="text-lg font-medium text-n-slate-12">
            {{ fraseDaParada }}
          </span>
          <span class="text-base text-n-slate-11">
            {{ fazerDaParada }}
          </span>
        </div>
        <p
          v-if="parado && !parou && !semAcompanhar"
          data-carteira="busca-parada"
          class="m-0 text-base text-n-slate-11"
        >
          {{ t('RELACIONAMENTOS_CARTEIRA.AGGER.PARADO') }}
        </p>
        <Button
          v-if="parouPeloLogin && podeLigar"
          size="lg"
          type="button"
          class="self-start"
          data-carteira="entrar-no-agger"
          :label="t('RELACIONAMENTOS_CARTEIRA.AGGER.ENTRAR')"
          @click="login?.abrir()"
        />
        <Button
          v-if="podeTentarDeNovo"
          size="lg"
          type="button"
          class="self-start"
          data-carteira="tentar-de-novo"
          :is-loading="ocupado"
          :label="t('RELACIONAMENTOS_CARTEIRA.AGGER.TENTAR_DE_NOVO')"
          @click="busca.tentarDeNovo"
        />
      </template>

      <template v-else-if="etapa === ETAPAS_DO_AGGER.CONFERIR">
        <div
          data-carteira="conferir-do-agger"
          class="flex flex-col gap-4 p-6 border rounded-3xl border-n-weak bg-n-solid-1"
        >
          <p
            v-if="atual.seguros"
            data-carteira="numeros-do-agger"
            class="m-0 text-xl font-semibold tabular-nums text-n-slate-12 text-balance"
          >
            {{ fraseDosNumeros }}
          </p>
          <p
            v-else
            data-carteira="nada-para-trazer"
            class="m-0 text-lg text-n-slate-12 text-pretty"
          >
            {{ t('RELACIONAMENTOS_CARTEIRA.AGGER.CONFERIR.NADA') }}
          </p>
          <Button
            v-if="atual.seguros"
            size="lg"
            type="button"
            class="self-start"
            data-carteira="trazer-do-agger"
            :is-loading="ocupado"
            :label="rotuloDeTrazer(atual.seguros)"
            @click="busca.trazer"
          />
          <p
            v-if="atual.seguros"
            data-carteira="depois-do-agger"
            class="m-0 text-sm text-n-slate-11 text-pretty"
          >
            {{ t('RELACIONAMENTOS_CARTEIRA.AGGER.CONFERIR.DEPOIS') }}
          </p>
          <ul
            v-if="temDetalhes"
            class="flex flex-wrap p-0 m-0 text-sm list-none gap-x-4 gap-y-2 text-n-slate-11"
          >
            <li v-if="atual.jaNaCarteira" data-carteira="ja-na-carteira">
              {{
                t(
                  'RELACIONAMENTOS_CARTEIRA.AGGER.CONFERIR.JA_NA_CARTEIRA',
                  { count: atual.jaNaCarteira },
                  atual.jaNaCarteira
                )
              }}
            </li>
            <li v-if="atual.pessoasNovas" data-carteira="pessoas-novas">
              {{
                t(
                  'RELACIONAMENTOS_CARTEIRA.AGGER.CONFERIR.PESSOAS_NOVAS',
                  { count: atual.pessoasNovas },
                  atual.pessoasNovas
                )
              }}
            </li>
            <li v-if="atual.semTelefone" data-carteira="sem-telefone">
              {{
                t(
                  'RELACIONAMENTOS_CARTEIRA.AGGER.CONFERIR.SEM_TELEFONE',
                  { count: atual.semTelefone },
                  atual.semTelefone
                )
              }}
            </li>
          </ul>
        </div>
        <PorQueNaoDeu
          :total="atual.naoDeuParaTrazer ?? 0"
          :porque="atual.naoDeuPorque ?? null"
        />
        <SeguradorasDaBusca :seguradoras="seguradoras" />
        <Button
          slate
          faded
          size="lg"
          type="button"
          class="self-start"
          data-carteira="buscar-de-novo"
          :label="t('RELACIONAMENTOS_CARTEIRA.AGGER.CONFERIR.DE_NOVO')"
          @click="busca.deNovo"
        />
      </template>

      <template v-else-if="etapa === ETAPAS_DO_AGGER.TRAZENDO">
        <p
          role="status"
          :aria-busy="trabalhando ? 'true' : 'false'"
          class="p-8 m-0 text-lg text-center border rounded-3xl border-n-weak bg-n-solid-1 text-n-slate-12"
        >
          {{ fraseDoTrazendo }}
        </p>
        <p
          v-if="parado && !semAcompanhar"
          data-carteira="trazendo-parado"
          class="m-0 text-base text-n-slate-11"
        >
          {{ t('RELACIONAMENTOS_CARTEIRA.AGGER.PARADO') }}
        </p>
        <Button
          v-if="semAcompanhar || parado"
          size="lg"
          type="button"
          class="self-start"
          data-carteira="tentar-de-novo"
          :label="t('RELACIONAMENTOS_CARTEIRA.AGGER.TENTAR_DE_NOVO')"
          @click="busca.tentarDeNovo"
        />
      </template>

      <template v-else>
        <ProntoDoAgger
          :andamento="andamento ?? {}"
          :ocupado="ocupado"
          @buscar="comecar"
          @ver="verOsSeguros"
          @voltar="voltarAoInicio"
        />
        <BuscaDeTodoDia
          :fonte="fonte"
          :pede-login="loginRecusadoNaConta"
          :pode-ligar="podeLigar"
          @entrar="login?.abrir()"
        />
      </template>
    </div>
    <DialogoDoLoginNoAgger ref="login" :conectar="busca.conectar" />
  </section>
</template>
