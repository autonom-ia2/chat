<script setup>
import { computed, provide, ref, useId, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CardHeroi from '../card/CardHeroi.vue';
import CardRodape from '../card/CardRodape.vue';
import CardMolduraLado from '../card/previas/CardMolduraLado.vue';
import PreviaRetorno from '../card/previas/PreviaRetorno.vue';
import TelaRetornoNovo from '../card/telas/TelaRetornoNovo.vue';
import { useCardRetorno } from '../card/useCardRetorno';
import { useFormato } from '../card/useFormato';
import { useFocoPreso } from '../card/useFocoPreso';
import CampoLigarA from './CampoLigarA.vue';
import LembreteSerie from './LembreteSerie.vue';
import LembreteUnico from './LembreteUnico.vue';
import { paredeDe } from './recorrencia';
import { avisoAoSalvar } from './avisoAoSalvar';

// #1460/#1461/#1462 — o lembrete fora do card, na mesma gaveta do card (topo
// escuro, formulário à esquerda, prévia à direita, rodapé com uma ação azul).
// Abre pelo calendário ("Novo lembrete", com a flag crm_lembretes_v2) e pela
// ficha do cliente (Relacionamento, com o cliente já escolhido).
// - "novo": é sobre quem (ninguém, um cliente ou um negócio), o quê, quando,
//   repetir e quem recebe;
// - "serie": a visão da repetição de um lembrete que repete;
// - "unico": um lembrete de uma vez só, sem card (Feito e Cancelar).
const props = defineProps({
  show: { type: Boolean, default: false },
  // 'novo' | 'serie' | 'unico'
  modo: { type: String, default: 'novo' },
  // O dia clicado no calendário.
  dia: { type: [Date, String, Number], default: () => new Date() },
  serieId: { type: [Number, String], default: null },
  followUpId: { type: [Number, String], default: null },
  // Pela ficha do cliente ou da empresa (Relacionamento): { id, name }.
  contato: { type: Object, default: null },
  empresa: { type: Object, default: null },
});
const emit = defineEmits(['close', 'salvou']);

const { t, locale } = useI18n();
const store = useStore();
const formato = useFormato({ t, locale });
const gavetaId = `lembrete-gaveta-${useId()}`;

const tela = ref(props.modo);
const ligadoA = ref({ tipo: 'nada' });
const card = ref({});
const salvando = ref(false);
const tituloDaSerie = ref('');

const salvou = () => {
  emit('salvou');
  emit('close');
};
const criarDeVerdade = async (_evento, payload) => {
  salvando.value = true;
  try {
    await store.dispatch('crmKanban/createFollowUp', payload);
    useAlert(t('CRM_LEMBRETE.SALVO'));
    salvou();
  } catch (erro) {
    useAlert(avisoAoSalvar(erro, t));
  } finally {
    salvando.value = false;
  }
};
const retorno = useCardRetorno({
  t,
  store,
  card,
  emit: criarDeVerdade,
  podeGerenciar: computed(() => true),
  formato,
  locale,
  lembretesV2: computed(() => true),
  aoSalvarEdicao: salvou,
  chamarDeLembrete: true,
});
provide('cardRetorno', retorno);

const escolherCard = async id => {
  card.value = {};
  retorno.form.quemRecebe = {
    tipo: id ? 'dono' : 'eu',
    pessoas: [],
    time: null,
  };
  if (!id) return;
  try {
    card.value = (await store.dispatch('crmKanban/fetchCard', id)) || {};
  } catch {
    card.value = {};
  }
};

function ligadoInicial() {
  if (props.contato)
    return {
      tipo: 'contato',
      contatoId: props.contato.id,
      nome: props.contato.name,
    };
  if (props.empresa)
    return {
      tipo: 'empresa',
      empresaId: props.empresa.id,
      nome: props.empresa.name,
    };
  return { tipo: 'nada' };
}

const dois = numero => String(numero).padStart(2, '0');
// O dia clicado às 09:00; hoje (no fuso da conta), depois das 09:00, a
// próxima hora cheia.
const inicioDoDia = valor => {
  const data = new Date(valor);
  const dia = `${data.getFullYear()}-${dois(data.getMonth() + 1)}-${dois(data.getDate())}`;
  const agora = paredeDe(new Date().toISOString(), retorno.contexto.fuso.value);
  const horaAgora = Number(agora.slice(11, 13));
  if (dia !== agora.slice(0, 10) || horaAgora < 9) return `${dia}T09:00`;
  if (horaAgora >= 23) return `${dia}T23:30`;
  return `${dia}T${dois(horaAgora + 1)}:00`;
};
watch(
  () => props.show,
  aberta => {
    if (!aberta) return;
    tela.value = props.modo;
    tituloDaSerie.value = '';
    ligadoA.value = ligadoInicial();
    card.value = {};
    retorno.reiniciar();
    retorno.form.dueAt = inicioDoDia(props.dia);
  },
  { immediate: true }
);

const telaSerie = ref(null);
const mudarSerie = escolha => {
  retorno.editarSerie(escolha);
  tela.value = 'novo';
};

const fechar = () => emit('close');
const heroi = computed(() => {
  if (tela.value === 'unico')
    return {
      rotulo: t('CRM_LEMBRETE.GAVETA.ROTULO'),
      icone: 'i-lucide-bell-ring',
      titulo: tituloDaSerie.value || t('CRM_LEMBRETE.GAVETA.TITULO'),
      texto: t('CRM_LEMBRETE.UNICO.TEXTO'),
    };
  if (tela.value === 'serie')
    return {
      rotulo: t('CRM_LEMBRETE.SERIE.TELA'),
      icone: 'i-lucide-repeat',
      titulo: tituloDaSerie.value || t('CRM_LEMBRETE.SERIE.TELA'),
      texto: t('CRM_LEMBRETE.SERIE.TEXTO'),
    };
  const mudando = retorno.edicao.value?.qual;
  if (mudando)
    return {
      rotulo: t('CRM_LEMBRETE.SERIE.TELA'),
      icone: 'i-lucide-pencil',
      titulo: t(`CRM_LEMBRETE.MUDAR.TITULO_${mudando.toUpperCase()}`),
      texto: t(`CRM_LEMBRETE.MUDAR.TEXTO_${mudando.toUpperCase()}`),
    };
  return {
    rotulo: t('CRM_LEMBRETE.GAVETA.ROTULO'),
    icone: 'i-lucide-bell-plus',
    titulo: t('CRM_LEMBRETE.GAVETA.TITULO'),
    texto: t('CRM_LEMBRETE.GAVETA.TEXTO'),
  };
});
const faltaLigar = computed(
  () =>
    !retorno.edicao.value &&
    ligadoA.value.tipo !== 'nada' &&
    !ligadoA.value.cardId &&
    !ligadoA.value.contatoId &&
    !ligadoA.value.empresaId
);
const ocupado = computed(() => salvando.value || retorno.salvandoEdicao.value);
const rodape = computed(() => {
  if (tela.value === 'unico')
    return {
      principal: { rotulo: t('CRM_CARD.PRONTO'), acao: fechar, neutro: true },
    };
  if (tela.value === 'serie')
    return {
      secundaria: { rotulo: t('CRM_CARD.VOLTAR'), acao: fechar },
      principal: telaSerie.value?.encerrada
        ? null
        : {
            rotulo: t('CRM_LEMBRETE.SERIE.MUDAR'),
            icone: 'i-lucide-pencil',
            acao: () => telaSerie.value?.abrirMudar(),
          },
    };
  return {
    falta: faltaLigar.value
      ? t('CRM_LEMBRETE.LIGAR.FALTA')
      : retorno.faltaFrase.value,
    secundaria: { rotulo: t('CRM_CARD.CANCELAR'), acao: fechar },
    principal: {
      rotulo: t('CRM_CARD.RETORNO.CRIAR'),
      icone: 'i-lucide-check',
      acao: () =>
        retorno.criar(ligadoA.value.tipo === 'card' ? null : ligadoA.value),
      carregando: ocupado.value,
      desabilitado: faltaLigar.value || !retorno.pronto.value || ocupado.value,
    },
  };
});
const cliente = computed(
  () => card.value?.contact?.name || ligadoA.value.nome || ''
);

const raiz = ref(null);
const { prender } = useFocoPreso({ raiz, mostrar: computed(() => props.show) });
</script>

<template>
  <transition
    enter-active-class="transition duration-200 ease-out"
    enter-from-class="ltr:translate-x-full rtl:-translate-x-full opacity-0"
    leave-active-class="transition duration-150 ease-in"
    leave-to-class="ltr:translate-x-[30%] rtl:-translate-x-[30%] opacity-0"
  >
    <div
      v-if="show"
      ref="raiz"
      data-lembrete-gaveta
      data-card-gaveta
      :data-tela="tela"
      role="dialog"
      aria-modal="true"
      :aria-labelledby="`${gavetaId}-titulo`"
      tabindex="-1"
      class="fixed inset-y-0 z-50 flex h-full w-[80rem] max-w-full flex-col overflow-hidden bg-n-solid-1 shadow-2xl outline-none ltr:right-0 rtl:left-0"
      @keydown="prender"
      @keydown.esc="fechar"
    >
      <CardHeroi
        v-bind="heroi"
        :titulo-id="`${gavetaId}-titulo`"
        :texto-id="`${gavetaId}-texto`"
        @fechar="fechar"
      />
      <div class="min-h-0 flex-1 overflow-y-auto">
        <div
          class="grid min-h-full grid-cols-[minmax(0,1fr)] lg:grid-cols-[minmax(0,1fr)_32rem]"
        >
          <main class="flex min-w-0 flex-col gap-6 px-5 py-6 sm:px-8">
            <LembreteSerie
              v-if="tela === 'serie' && serieId"
              ref="telaSerie"
              :serie-id="serieId"
              :formato="formato"
              @carregou="serie => (tituloDaSerie = serie.title)"
              @mudou="emit('salvou')"
              @mudar="mudarSerie"
            />
            <LembreteUnico
              v-else-if="tela === 'unico' && followUpId"
              :follow-up-id="followUpId"
              @carregou="item => (tituloDaSerie = item.title)"
              @mudou="emit('salvou')"
            />
            <template v-else>
              <CampoLigarA
                v-if="!retorno.edicao.value && !contato && !empresa"
                v-model="ligadoA"
                @card="escolherCard"
              />
              <TelaRetornoNovo
                :funil="card.pipeline?.name || ''"
                :so-lembrete="!card.id"
              />
            </template>
          </main>
          <aside
            data-card-lado
            class="min-w-0 border-t border-n-weak bg-n-alpha-1 px-5 py-7 sm:px-8 lg:border-s lg:border-t-0 lg:px-5"
          >
            <div class="flex flex-col gap-4 lg:sticky lg:top-7">
              <CardMolduraLado
                v-if="tela === 'novo'"
                selo="previa"
                :titulo="t('CRM_CARD.LADO.RETORNO_TITULO')"
                :texto="t('CRM_CARD.LADO.RETORNO_TEXTO')"
              >
                <PreviaRetorno
                  v-bind="retorno.previa.value"
                  :cliente="cliente"
                />
                <p
                  class="mb-0 flex items-start gap-2 text-sm text-n-slate-11"
                  data-previa-onde
                >
                  <span
                    class="i-lucide-map-pin mt-0.5 size-4 shrink-0"
                    aria-hidden="true"
                  />
                  {{
                    t(
                      `CRM_LEMBRETE.PREVIA.ONDE_${ligadoA.tipo.toUpperCase()}${cliente ? '' : '_SEM'}`,
                      { nome: cliente }
                    )
                  }}
                </p>
              </CardMolduraLado>
              <CardMolduraLado
                v-else-if="tela === 'serie'"
                selo="agora"
                :titulo="t('CRM_LEMBRETE.SERIE.LADO_TITULO')"
                :texto="t('CRM_LEMBRETE.SERIE.LADO_TEXTO')"
              >
                <ul
                  class="m-0 flex list-none flex-col gap-2 p-0 text-sm text-n-slate-12"
                >
                  <li
                    v-for="chave in ['FEITO', 'PAUSAR', 'ENCERRAR', 'MUDAR']"
                    :key="chave"
                    class="flex items-start gap-2 rounded-xl bg-n-solid-1 p-3 ring-1 ring-inset ring-n-weak"
                  >
                    <span
                      class="i-lucide-info mt-0.5 size-4 shrink-0 text-n-blue-11"
                      aria-hidden="true"
                    />
                    {{ t(`CRM_LEMBRETE.SERIE.AJUDA.${chave}`) }}
                  </li>
                </ul>
              </CardMolduraLado>
            </div>
          </aside>
        </div>
      </div>
      <CardRodape :rodape="rodape" :ocupado="ocupado" />
    </div>
  </transition>
</template>
