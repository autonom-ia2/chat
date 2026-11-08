<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  ICONE_DA_REDE,
  agentesDasPortas,
  motivosDasPortas,
  estadoDoCuidado,
  redesDoCuidado,
  tituloDaLegenda,
  useAgenteDoPost,
} from '../composables/useAgentesDoPost';

// #2469 (PR 3a do #2436) — o cartão de um post ou anúncio com o cuidado dos comentários, na lista de Agentes. Não é
// outro agente: é o cuidado de um post por cima do agente da porta da caixa, e diz "Usa o que <agente> sabe". Um número
// só: quantos esperam o dono (a mesma conta da página e da gaveta, vinda do servidor). O título é o começo da legenda;
// a foto e o ícone da rede dizem de que post é. A faixa do número leva direto aos comentários, em "esperando você".
// A lista vem do banco; o resto, lido na Meta na hora, chega depois e não muda o tamanho do cartão. Cada cartão só lê
// quando aparece na tela, pela fila de leituras (no máximo 3 de cada vez). Sem acesso (403) ou sumido (404), o cartão
// diz isso no lugar do título; com a leitura dos comentários falhando, a faixa diz que não leu, nunca um zero.
const props = defineProps({
  // { id, kind ('post' | 'ad'), target_id, perfil, network, status }
  cuidado: { type: Object, required: true },
  href: { type: String, required: true },
  hrefEsperando: { type: String, required: true },
});

// abrir(cuidado, grupo): o grupo vem vazio no cartão e 'esperando' na faixa.
const emit = defineEmits(['abrir']);

const { t } = useI18n();
const KEY = 'AGENTS.AGENTE_DO_POST';
const ESTILO = {
  cuidando: { fundo: 'bg-n-teal-3', ponto: 'bg-n-teal-9' },
  pausado: { fundo: 'bg-n-amber-3', ponto: 'bg-n-amber-9' },
};

const raiz = ref(null);
const visivel = ref(false);
let observador = null;
onMounted(() => {
  if (typeof IntersectionObserver === 'undefined') {
    visivel.value = true;
    return;
  }
  observador = new IntersectionObserver(entradas => {
    if (!entradas.some(entrada => entrada.isIntersecting)) return;
    visivel.value = true;
    observador.disconnect();
  });
  observador.observe(raiz.value);
});
onBeforeUnmount(() => observador?.disconnect());

const { detalhe, erro } = useAgenteDoPost(
  () => (visivel.value ? props.cuidado.id : null),
  { emFila: true }
);
const ERRO = { acesso: 'SEM_ACESSO', sumiu: 'SUMIU', rede: 'ERRO' };

const estado = computed(() => estadoDoCuidado(props.cuidado.status));
const estilo = computed(() => ESTILO[estado.value]);
const redes = computed(() => redesDoCuidado(props.cuidado.network));
const legenda = computed(() => tituloDaLegenda(detalhe.value?.legenda || ''));
const titulo = computed(() => {
  if (legenda.value.titulo) return legenda.value.titulo;
  if (erro.value) return t(`${KEY}.CARTAO.${ERRO[erro.value]}`);
  return detalhe.value
    ? t(`${KEY}.CARTAO.SEM_LEGENDA`)
    : t(`${KEY}.CARTAO.LENDO`);
});
// null: ainda lendo; 'sem_leitura': a Meta não deixou ler os comentários (erro do cartão ou status da leitura).
const esperando = computed(() => {
  if (erro.value) return 'sem_leitura';
  const comentarios = detalhe.value?.comentarios;
  if (!comentarios) return null;
  return comentarios.status === 'ready'
    ? comentarios.esperando.length
    : 'sem_leitura';
});
const usa = computed(() => {
  if (!detalhe.value) return '';
  const [um, outro] = agentesDasPortas(detalhe.value.portas);
  if (outro) {
    return t(`${KEY}.CARTAO.USA_DOIS`, { um: um.name, outro: outro.name });
  }
  if (um) return t(`${KEY}.CARTAO.USA`, { nome: um.name });
  const motivos = motivosDasPortas(detalhe.value.portas, t);
  return motivos.length
    ? [...motivos, t(`${KEY}.MOTIVO_DA_PORTA.FRASES_FIXAS`)].join(' ')
    : t(`${KEY}.CARTAO.SEM_PORTA`);
});

const aoClicar = (evento, grupo = '') => {
  if (evento.metaKey || evento.ctrlKey || evento.shiftKey || evento.button) {
    return;
  }
  evento.preventDefault();
  emit('abrir', props.cuidado, grupo);
};
</script>

<template>
  <li
    ref="raiz"
    data-cartao
    data-post-comentarios
    :data-kind="cuidado.kind"
    class="flex flex-col h-full list-none transition shadow-sm rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak dark:ring-n-slate-6 hover:ring-n-slate-7 hover:shadow-md"
  >
    <a
      :href="href"
      class="flex flex-col w-full gap-3 p-5 pb-3 text-start rounded-t-2xl focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-blue-11"
      @click="aoClicar"
    >
      <span class="flex items-start w-full gap-3">
        <span class="relative shrink-0">
          <img
            v-if="detalhe?.capa"
            :src="detalhe.capa"
            alt=""
            class="object-cover size-12 rounded-xl"
          />
          <span
            v-else
            class="block size-12 rounded-xl bg-n-alpha-2"
            aria-hidden="true"
          />
          <span class="absolute flex -bottom-1 -end-1">
            <span
              v-for="rede in redes"
              :key="rede"
              data-rede
              role="img"
              :aria-label="t(`${KEY}.REDE.${rede.toUpperCase()}`)"
              class="grid rounded-full size-6 place-items-center bg-n-solid-1 ring-2 ring-n-solid-1"
            >
              <span class="size-4" :class="ICONE_DA_REDE[rede]" />
            </span>
          </span>
        </span>
        <span class="flex flex-col min-w-0 gap-1 grow">
          <span
            data-cartao-titulo
            class="text-base font-semibold line-clamp-2 text-n-slate-12"
          >
            {{ titulo }}
          </span>
          <span class="flex flex-wrap items-center gap-1.5">
            <span
              data-estado
              class="inline-flex items-center gap-1.5 px-2.5 py-0.5 text-xs font-medium rounded-full w-fit text-n-slate-12"
              :class="estilo.fundo"
            >
              <span
                aria-hidden="true"
                class="rounded-full size-2"
                :class="estilo.ponto"
              />
              {{ t(`${KEY}.ESTADO.${estado.toUpperCase()}`) }}
            </span>
            <span
              data-tipo
              class="px-2.5 py-0.5 text-xs font-medium rounded-full bg-n-alpha-2 text-n-slate-11"
            >
              {{ t(`${KEY}.TIPO.${cuidado.kind.toUpperCase()}`) }}
            </span>
          </span>
        </span>
        <span
          class="mt-3 i-lucide-chevron-right size-5 text-n-slate-10 rtl:rotate-180"
          aria-hidden="true"
        />
      </span>
      <span
        class="text-sm line-clamp-2 text-n-slate-12 min-h-[2.5rem]"
        :class="{ invisible: !legenda.resto }"
      >
        {{ legenda.resto }}
      </span>
    </a>
    <a
      :href="hrefEsperando"
      data-esperando
      class="flex items-center gap-1.5 px-3 mx-2 text-sm font-semibold rounded-xl min-h-11 hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
      :class="
        esperando && esperando !== 'sem_leitura'
          ? 'text-n-amber-11'
          : 'text-n-slate-11'
      "
      @click="aoClicar($event, 'esperando')"
    >
      <span class="i-lucide-hand size-4 shrink-0" aria-hidden="true" />
      <span v-if="esperando === 'sem_leitura'" data-sem-leitura>
        {{ t(`${KEY}.CARTAO.SEM_LEITURA`) }}
      </span>
      <span v-else-if="esperando !== null">
        {{ t(`${KEY}.CARTAO.ESPERANDO`, { n: esperando }, esperando) }}
      </span>
      <span
        v-else
        class="w-32 h-4 rounded bg-n-alpha-2 animate-pulse"
        aria-hidden="true"
      />
      <span
        class="i-lucide-chevron-right ms-auto size-4 shrink-0 text-n-slate-10 rtl:rotate-180"
        aria-hidden="true"
      />
    </a>
    <span
      data-usa
      class="flex items-center gap-1.5 px-5 pt-1 pb-5 text-sm text-n-slate-11 min-h-[1.5rem]"
    >
      <span class="i-lucide-book-open size-4 shrink-0" aria-hidden="true" />
      {{ usa }}
    </span>
  </li>
</template>
