<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useGuiaPedido } from 'dashboard/composables/useGuiaPedido';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import MelhorResposta from './MelhorResposta.vue';
import { useBuscaDaCentral } from '../composables/useBuscaDaCentral';

defineProps({
  guiaDisponivel: { type: Boolean, default: false },
});
// Verdadeiro enquanto há texto na busca: a página esconde os assuntos para a pessoa olhar só os resultados.
const ativa = defineModel('ativa', { type: Boolean, default: false });

const { t } = useI18n();
const router = useRouter();
const { pedirAoGuia } = useGuiaPedido();
const {
  termo,
  temTermo,
  erro,
  melhor,
  buscando,
  aguardando,
  emDestaque,
  alternativa,
  alternativaEmDestaque,
  lista,
  total,
  adiantar,
} = useBuscaDaCentral();

const campo = ref(null);
const abrirAoChegar = ref(false);

watch(temTermo, valor => {
  ativa.value = valor;
});

const semNada = computed(
  () => !aguardando.value && !erro.value && total.value === 0
);
// Erro só quando não há nada para mostrar: com a escolha do Jev na tela, a mensagem a contradiria.
const mostrarErro = computed(
  () => !aguardando.value && erro.value && !melhor.value
);

// Uma frase só por busca: "Buscando…" até as duas terminarem, depois o resultado inteiro.
const anuncio = computed(() => {
  if (aguardando.value) return t('HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.BUSCANDO');
  const contagem = t(
    'HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.RESULTADOS',
    total.value
  );
  if (!emDestaque.value) return contagem;
  const destaque = t('HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.ANUNCIO_MELHOR', {
    titulo: melhor.value.titulo,
  });
  return `${destaque} ${contagem}`;
});

const abrir = artigo =>
  router.push({ name: 'central_de_ajuda_artigo', params: { ref: artigo.ref } });

// Só abre o que está na tela, e do termo atual.
const abrirMelhorOuPrimeiro = () => {
  if (emDestaque.value) abrir(melhor.value);
  else if (lista.value.length) abrir(lista.value[0]);
};

// Enter logo depois de digitar: busca já o termo atual e abre quando as respostas chegarem.
const abrirPrimeiro = () => {
  if (!aguardando.value) {
    abrirMelhorOuPrimeiro();
    return;
  }
  abrirAoChegar.value = true;
  adiantar();
};

watch(aguardando, valor => {
  if (valor || !abrirAoChegar.value) return;
  abrirAoChegar.value = false;
  abrirMelhorOuPrimeiro();
});
// Mudou o texto, o Enter pendente era de outra busca.
watch(termo, () => {
  abrirAoChegar.value = false;
});

// O que a pessoa digitou vira a pergunta ao Guia; sem texto, o painel só abre.
const perguntarAoGuia = () => pedirAoGuia(termo.value);

const limpar = () => {
  termo.value = '';
  campo.value?.focus();
};
</script>

<template>
  <div role="search" class="flex flex-col gap-3">
    <label for="busca-central" class="sr-only">
      {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.ROTULO') }}
    </label>
    <div class="flex flex-col gap-3 sm:flex-row">
      <div class="relative flex-1 min-w-0">
        <span
          class="i-lucide-search absolute top-1/2 -translate-y-1/2 ltr:left-4 rtl:right-4 size-6 text-n-slate-10 pointer-events-none"
          aria-hidden="true"
        />
        <input
          id="busca-central"
          ref="campo"
          v-model="termo"
          type="text"
          inputmode="search"
          enterkeyhint="search"
          autocomplete="off"
          class="reset-base w-full h-16 ltr:pl-14 rtl:pr-14 ltr:pr-14 rtl:pl-14 text-lg rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm text-n-slate-12 placeholder:text-n-slate-10 outline-none focus:border-n-brand focus:outline focus:outline-2 focus:outline-n-brand"
          :placeholder="t('HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.PLACEHOLDER')"
          aria-describedby="busca-central-dica"
          @keydown.enter.prevent="abrirPrimeiro"
        />
        <button
          v-if="temTermo"
          type="button"
          class="absolute top-1/2 -translate-y-1/2 ltr:right-2 rtl:left-2 size-11 grid place-items-center rounded-xl text-n-slate-11 hover:bg-n-alpha-2"
          :aria-label="t('HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.LIMPAR')"
          @click="limpar"
        >
          <span class="i-lucide-x size-5" aria-hidden="true" />
        </button>
      </div>
      <Button
        v-if="guiaDisponivel"
        size="lg"
        color="blue"
        icon="i-lucide-sparkles"
        class="min-h-11 sm:h-16 shrink-0"
        :label="t('HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.PERGUNTAR_GUIA')"
        @click="perguntarAoGuia"
      />
    </div>

    <!-- Os atalhos de "Mais procurados" já mostram exemplos na tela; a dica fica para o leitor de tela. -->
    <p id="busca-central-dica" class="sr-only">
      {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.DICA') }}
    </p>

    <p class="sr-only" aria-live="polite">
      <template v-if="temTermo">{{ anuncio }}</template>
    </p>

    <p v-if="temTermo && mostrarErro" class="mb-0 text-base text-n-ruby-11">
      {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.ERRO') }}
    </p>

    <!-- O cartão e a lista entram juntos, quando as duas buscas terminam: nada empurra o que já está na tela. -->
    <Transition
      enter-active-class="transition-opacity duration-200"
      enter-from-class="opacity-0"
    >
      <MelhorResposta
        v-if="temTermo && !aguardando && emDestaque"
        :artigo="melhor"
      />
    </Transition>

    <!-- A alternativa chega meio segundo depois (#985) e entra logo abaixo da resposta, com fade. -->
    <Transition
      enter-active-class="transition-opacity duration-200"
      enter-from-class="opacity-0"
    >
      <MelhorResposta
        v-if="temTermo && !aguardando && alternativaEmDestaque"
        :artigo="alternativa"
        secundaria
      />
    </Transition>

    <!-- Sem nenhum resultado ainda, o que falta é a Melhor resposta: a tela diz isso, não fica em branco. -->
    <div
      v-if="temTermo && aguardando"
      class="flex items-center gap-3 px-1 py-4 text-base text-n-slate-11"
    >
      <Spinner />
      {{
        buscando
          ? t('HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.BUSCANDO')
          : t('HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.PROCURANDO_MELHOR')
      }}
    </div>

    <section
      v-else-if="temTermo && lista.length"
      class="flex flex-col gap-2"
      :aria-label="
        emDestaque ? t('HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.OUTROS') : undefined
      "
    >
      <!-- Com a Melhor resposta na tela, a busca por palavras é só complemento (#985). -->
      <h3
        v-if="emDestaque"
        class="mb-0 mt-2 px-1 text-sm font-semibold text-n-slate-11"
      >
        {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.OUTROS') }}
      </h3>
      <ul class="m-0 p-0 list-none flex flex-col gap-2">
        <li v-for="artigo in lista" :key="artigo.ref">
          <router-link
            :to="{
              name: 'central_de_ajuda_artigo',
              params: { ref: artigo.ref },
            }"
            class="flex flex-col gap-1 rounded-xl border border-n-weak bg-n-solid-1 px-5 py-4 hover:border-n-brand focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          >
            <span class="text-lg font-medium text-n-slate-12">
              {{ artigo.titulo }}
            </span>
            <span class="text-base text-n-slate-11">{{
              artigo.descricao
            }}</span>
            <span class="text-sm text-n-slate-10">{{ artigo.capitulo }}</span>
          </router-link>
        </li>
      </ul>
    </section>

    <!-- "Nada" só depois que as duas buscas terminaram vazias. -->
    <div
      v-else-if="temTermo && semNada"
      class="flex flex-wrap items-center gap-3 rounded-xl bg-n-alpha-1 px-5 py-4"
    >
      <p class="mb-0 text-base text-n-slate-11">
        {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.NADA') }}
      </p>
      <Button
        v-if="guiaDisponivel"
        size="lg"
        color="blue"
        variant="faded"
        icon="i-lucide-life-buoy"
        class="min-h-11"
        :label="t('HELP_CENTER.CENTRAL_DE_AJUDA.ARTIGO.PERGUNTE')"
        @click="perguntarAoGuia"
      />
    </div>
  </div>
</template>
