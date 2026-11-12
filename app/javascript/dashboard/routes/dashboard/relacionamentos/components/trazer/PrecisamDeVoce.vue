<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { SITUACAO_DO_PROBLEMA } from '../../trazer/contagem';
import ProblemaDaLinha from './ProblemaDaLinha.vue';

// #2894 — "Precisam de você (5)": as linhas da planilha que o sistema não
// conseguiu organizar sozinho, cada uma com o conserto ali mesmo.
// Ao resolver (ou reabrir) uma linha, o formulário some ou volta: o foco vai
// para o próximo problema aberto (ou para o título) e a mudança é anunciada
// numa região viva que fica sempre no DOM, fora dos formulários.
// #2896 — `semConserto`: a planilha já foi apagada do servidor. Uma frase diz
// isso no topo e as linhas ficam sem o conserto (só "Deixar de fora").
// Fatia 2 — `recusa` (`{ linha, motivo }`): o valor que o servidor não aceitou
// vai só para a linha dele. E o conserto que vale numa linha que ainda tem
// outro problema troca o cartão dela pelo do problema que sobrou (outro `tipo`,
// ainda aberto): o cartão nasce de novo, com o campo do problema novo, o foco
// vai para ele e a região viva diz que o valor foi salvo e que falta outra coisa.
// As linhas vêm do servidor aos poucos: `faltamCarregar` diz quantas ainda não
// vieram (contam no título, como abertas) e "Mostrar mais" pede as próximas.
// Quando elas chegam, o foco vai para a primeira nova.
// O foco espera a escrita acabar (`ocupado`): até lá os botões das linhas estão
// desligados, e a linha que só tem botões (a repetida, a sem conserto) não
// receberia o foco.
const props = defineProps({
  problemas: { type: Array, required: true },
  ocupado: { type: Boolean, default: false },
  semConserto: { type: Boolean, default: false },
  recusa: { type: Object, default: null },
  faltamCarregar: { type: Number, default: 0 },
  carregandoMais: { type: Boolean, default: false },
  erroDoMais: { type: Boolean, default: false },
});
const emit = defineEmits(['guardar', 'deixarDeFora', 'reabrir', 'mostrarMais']);

const { t } = useI18n();
const { ABERTO, GUARDADO, DEIXADO } = SITUACAO_DO_PROBLEMA;
const ANUNCIOS = {
  [GUARDADO]: 'RELACIONAMENTOS_TRAZER.PRECISAM.ANUNCIO.PRONTO',
  [DEIXADO]: 'RELACIONAMENTOS_TRAZER.PRECISAM.ANUNCIO.DEIXADA',
  [ABERTO]: 'RELACIONAMENTOS_TRAZER.PRECISAM.ANUNCIO.REABERTA',
};
const ANUNCIO_OUTRO_PROBLEMA =
  'RELACIONAMENTOS_TRAZER.PRECISAM.ANUNCIO.OUTRO_PROBLEMA';

const raiz = ref(null);
const titulo = ref(null);
const anuncio = ref('');

const abertas = computed(
  () =>
    props.problemas.filter(p => p.estado === ABERTO).length +
    props.faltamCarregar
);

// A pessoa pediu mais linhas e elas ainda não chegaram.
let pediuMais = false;
const pedirMais = () => {
  pediuMais = true;
  emit('mostrarMais');
};

const primeiraNova = (antes, depois) => {
  const tinha = new Set(antes.map(p => p.linha));
  return depois.find(p => !tinha.has(p.linha)) ?? null;
};

// A linha que mudou de estado ou de problema, com o estado que tinha.
const linhaMudada = (antes, depois) => {
  const anterior = new Map(antes.map(p => [p.linha, p]));
  const mudada = depois
    .filter(p => {
      const era = anterior.get(p.linha);
      return era && (era.estado !== p.estado || era.tipo !== p.tipo);
    })
    .at(-1);
  return mudada
    ? { mudada, estadoDeAntes: anterior.get(mudada.linha).estado }
    : null;
};

// Aberta antes e aberta agora: o valor foi salvo e sobrou outro problema.
const anuncioDa = ({ mudada, estadoDeAntes }) =>
  mudada.estado === ABERTO && estadoDeAntes === ABERTO
    ? ANUNCIO_OUTRO_PROBLEMA
    : ANUNCIOS[mudada.estado];

const primeiroCampo = linha => {
  const item = raiz.value?.querySelector(`[data-linha="${linha}"]`);
  return (
    item?.querySelector('input') ??
    item?.querySelector('form button:not([disabled])')
  );
};

// O próximo problema aberto depois da linha mudada; se não há, o primeiro.
const proximoAberto = (lista, mudada) => {
  const posicao = lista.findIndex(p => p.linha === mudada.linha);
  const todos = lista.filter(p => p.estado === ABERTO);
  return (
    lista.slice(posicao + 1).find(p => p.estado === ABERTO) ?? todos[0] ?? null
  );
};

const levarOFoco = (lista, mudada) => {
  const alvo =
    mudada.estado === ABERTO ? mudada : (proximoAberto(lista, mudada) ?? null);
  const campo = alvo ? primeiroCampo(alvo.linha) : titulo.value;
  campo?.focus();
};

// O foco que a tela deve: fica guardado enquanto a escrita não acaba.
let focoDevido = null;
const focarQuandoDer = async () => {
  if (!focoDevido || props.ocupado) return;
  const focar = focoDevido;
  focoDevido = null;
  await nextTick();
  focar();
};

watch(() => props.ocupado, focarQuandoDer);
watch(
  () => props.problemas,
  (depois, antes) => {
    const nova = pediuMais ? primeiraNova(antes, depois) : null;
    if (nova) pediuMais = false;
    const mudanca = linhaMudada(antes, depois);
    if (mudanca) {
      anuncio.value = t(anuncioDa(mudanca), { linha: mudanca.mudada.linha });
      focoDevido = () => levarOFoco(depois, mudanca.mudada);
    } else if (nova) {
      focoDevido = () => primeiroCampo(nova.linha)?.focus();
    }
    focarQuandoDer();
  }
);
</script>

<template>
  <section
    ref="raiz"
    data-relacionamentos="precisam-de-voce"
    class="flex flex-col gap-4"
  >
    <h2
      ref="titulo"
      data-relacionamentos="precisam-titulo"
      tabindex="-1"
      class="m-0 text-2xl font-semibold tracking-tight outline-none text-n-slate-12"
    >
      {{
        abertas
          ? t('RELACIONAMENTOS_TRAZER.PRECISAM.TITULO', { count: abertas })
          : t('RELACIONAMENTOS_TRAZER.PRECISAM.RESOLVIDO')
      }}
    </h2>
    <p class="m-0 -mt-2 text-base text-n-slate-11">
      {{ t('RELACIONAMENTOS_TRAZER.PRECISAM.APOIO') }}
    </p>
    <p
      v-if="semConserto"
      data-relacionamentos="planilha-apagada"
      class="flex items-start gap-2 p-4 m-0 text-base rounded-xl bg-n-alpha-2 text-n-slate-12"
    >
      <span
        class="mt-0.5 i-lucide-info size-5 shrink-0 text-n-slate-11"
        aria-hidden="true"
      />
      {{ t('RELACIONAMENTOS_TRAZER.PRECISAM.PLANILHA_APAGADA') }}
    </p>
    <p data-relacionamentos="anuncio-precisam" role="status" class="sr-only">
      {{ anuncio }}
    </p>
    <ul class="flex flex-col gap-3 p-0 m-0 list-none">
      <ProblemaDaLinha
        v-for="problema in problemas"
        :key="`${problema.linha}:${problema.tipo}`"
        :problema="problema"
        :ocupado="ocupado"
        :sem-conserto="semConserto"
        :recusa="recusa?.linha === problema.linha ? recusa : null"
        @guardar="(linha, valor) => emit('guardar', linha, valor)"
        @deixar-de-fora="linha => emit('deixarDeFora', linha)"
        @reabrir="linha => emit('reabrir', linha)"
      />
    </ul>
    <p
      v-if="erroDoMais"
      data-relacionamentos="erro-do-mais"
      role="alert"
      class="m-0 text-base font-medium text-n-ruby-11"
    >
      {{ t('RELACIONAMENTOS_TRAZER.PRECISAM.ERRO_MOSTRAR_MAIS') }}
    </p>
    <Button
      v-if="faltamCarregar > 0"
      faded
      slate
      data-relacionamentos="mostrar-mais"
      class="self-start min-h-11"
      :label="t('RELACIONAMENTOS_TRAZER.PRECISAM.MOSTRAR_MAIS')"
      :disabled="carregandoMais || ocupado"
      :is-loading="carregandoMais"
      @click="pedirMais"
    />
  </section>
</template>
