<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import DialogoDaSenhaNoAgger from './DialogoDaSenhaNoAgger.vue';

// #2897 — a busca no Agger, seguradora por seguradora: quantos seguros
// chegaram de cada uma, qual ainda está sendo buscada e qual ficou sem vir
// (com o "Como resolver"). A busca não segue sozinha para a conferência: quando
// termina, a pessoa lê o que faltou e toca em Continuar.
const props = defineProps({
  // { seguradoras: [{ nome, seguros, situacao }], leitura }
  busca: { type: Object, required: true },
  terminou: { type: Boolean, default: false },
  naoRespondeu: { type: Boolean, default: false },
  buscandoDeNovo: { type: Boolean, default: false },
});
const emit = defineEmits(['continuar', 'buscarDeNovo', 'tentarAgora']);

const { t } = useI18n();
const ta = (chave, ...resto) =>
  t(`RELACIONAMENTOS_CARTEIRA.TRAZER.AGGER.${chave}`, ...resto);

const dialogo = ref(null);
const semSenha = ref('');

const ICONES = {
  pronta: 'i-lucide-circle-check text-n-teal-11',
  buscando: 'i-lucide-loader-circle animate-spin text-n-blue-11',
  falta_senha: 'i-lucide-key-round text-n-amber-11',
};

const linhas = computed(() =>
  props.busca.seguradoras.map(({ nome, seguros, situacao }) => ({
    nome,
    situacao,
    icone: ICONES[situacao],
    texto: {
      pronta: `${ta('SEGUROS', { count: seguros }, seguros)} · ${ta('CHEGOU')}`,
      buscando: ta('BUSCANDO_ESTA'),
      falta_senha: ta('FALTA_A_SENHA'),
    }[situacao],
  }))
);

const comoResolver = nome => {
  semSenha.value = nome;
  dialogo.value?.abrir();
};

const buscarDeNovo = () => {
  dialogo.value?.fechar();
  emit('buscarDeNovo');
};
</script>

<template>
  <section data-carteira="agger-buscando" class="flex flex-col gap-6">
    <div class="flex flex-col gap-2">
      <h1
        data-titulo-da-tela
        tabindex="-1"
        class="m-0 text-3xl font-bold tracking-tight outline-none md:text-4xl text-n-slate-12"
      >
        {{ ta(terminou ? 'TERMINOU' : 'BUSCANDO') }}
      </h1>
      <p class="m-0 text-base text-n-slate-11">
        {{ ta(terminou ? 'TERMINOU_APOIO' : 'BUSCANDO_APOIO') }}
      </p>
    </div>

    <div
      v-if="!linhas.length"
      data-carteira="carregando"
      role="status"
      aria-busy="true"
      :aria-label="t('RELACIONAMENTOS.COMUM.CARREGANDO')"
      class="flex flex-col gap-3"
    >
      <div
        v-for="linha in 3"
        :key="linha"
        aria-hidden="true"
        class="h-16 rounded-2xl bg-n-slate-3 dark:bg-n-slate-5 animate-pulse"
      />
    </div>
    <ul
      v-else
      aria-live="polite"
      :aria-label="ta('SEGURADORAS')"
      class="flex flex-col gap-3 p-0 m-0 list-none"
    >
      <li
        v-for="linha in linhas"
        :key="linha.nome"
        data-carteira="agger-seguradora"
        :data-situacao="linha.situacao"
        class="flex flex-col gap-3 p-5 border rounded-2xl border-n-weak bg-n-solid-1 sm:flex-row sm:items-center sm:justify-between"
      >
        <div class="flex items-start min-w-0 gap-3">
          <span
            class="size-5 shrink-0 mt-0.5"
            :class="linha.icone"
            aria-hidden="true"
          />
          <div class="flex flex-col min-w-0 gap-1">
            <p class="m-0 text-base font-medium break-words text-n-slate-12">
              {{ linha.nome }}
            </p>
            <p class="m-0 text-sm tabular-nums text-n-slate-11">
              {{ linha.texto }}
            </p>
          </div>
        </div>
        <Button
          v-if="linha.situacao === 'falta_senha'"
          slate
          faded
          size="lg"
          data-carteira="agger-como-resolver"
          :label="ta('COMO_RESOLVER')"
          :aria-label="ta('COMO_RESOLVER_DE', { seguradora: linha.nome })"
          @click="comoResolver(linha.nome)"
        />
      </li>
    </ul>

    <div
      v-if="naoRespondeu"
      data-carteira="agger-nao-respondeu"
      role="alert"
      class="flex flex-col items-start gap-3 p-5 border rounded-2xl border-n-amber-6 bg-n-amber-2"
    >
      <p class="m-0 text-base text-n-slate-12">{{ ta('NAO_RESPONDEU') }}</p>
      <Button
        slate
        faded
        size="lg"
        data-carteira="agger-tentar-agora"
        :label="ta('TENTAR_AGORA')"
        @click="emit('tentarAgora')"
      />
    </div>

    <div v-if="terminou" class="flex flex-wrap items-center gap-3">
      <Button
        data-carteira="agger-continuar"
        size="lg"
        :label="t('RELACIONAMENTOS.COMUM.CONTINUAR')"
        @click="emit('continuar')"
      />
    </div>

    <DialogoDaSenhaNoAgger
      ref="dialogo"
      :seguradora="semSenha"
      :texto="ta('COMO_RESOLVER_TEXTO', { seguradora: semSenha })"
      :rotulo-da-acao="ta('BUSCAR_DE_NOVO')"
      :ocupado="buscandoDeNovo"
      @resolver="buscarDeNovo"
    />
  </section>
</template>
