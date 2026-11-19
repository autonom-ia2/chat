<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import HeroiEscuro from '../../../comum/HeroiEscuro.vue';
import LinhaDeConfianca from '../LinhaDeConfianca.vue';
import VoltarDoTrazer from '../VoltarDoTrazer.vue';

// #2899 (E6.4) — a primeira pergunta de "Trazer" na conta que lê PDF: trazer
// por planilha (o caminho de sempre) ou por PDFs das apólices. São links
// grandes; o caminho escolhido fica no endereço (`?como=`), e voltar do
// navegador traz a pergunta de novo.
//
// #2900 (E7.3) — na conta que pode trazer do Agger, o caminho "Do Agger"
// (`?como=agger`). A porta passa os caminhos que a conta tem.
//
// #3057 — redesenho: no topo, a volta à aba de origem (VoltarDoTrazer) e o
// herói escuro com "Escolha o que você tem em mãos". Os caminhos vêm em fila,
// um por linha, do mais fácil para o mais trabalhoso: Agger (só o login), PDFs
// (só escolher os arquivos), planilha (montar a lista). O primeiro da conta
// leva o selo "O jeito mais fácil" e o destaque azul; os outros continuam à
// vista, iguais entre si. Cada linha inteira é o link (alvo grande, no celular
// também), com ícone, frase de leigo e a seta.
const props = defineProps({
  // { planilha, pdfs, agger }: as rotas de cada caminho.
  rotas: { type: Object, required: true },
  // Os caminhos que a conta tem.
  caminhos: { type: Array, default: () => ['planilha', 'pdfs'] },
});

const { t } = useI18n();
const tc = chave => t(`RELACIONAMENTOS_CARTEIRA.PDFS.COMO.${chave}`);

// Do mais fácil para o mais trabalhoso.
const DO_MAIS_FACIL = [
  { id: 'agger', icone: 'i-lucide-cloud-download', chave: 'AGGER' },
  { id: 'pdfs', icone: 'i-lucide-file-text', chave: 'PDFS' },
  { id: 'planilha', icone: 'i-lucide-sheet', chave: 'PLANILHA' },
];
const daConta = computed(() =>
  DO_MAIS_FACIL.filter(caminho => props.caminhos.includes(caminho.id)).map(
    (caminho, indice) => ({ ...caminho, maisFacil: indice === 0 })
  )
);
</script>

<template>
  <section
    data-carteira="como-trazer"
    class="flex flex-col w-full h-full overflow-y-auto bg-n-surface-1"
  >
    <div
      class="flex flex-col w-full max-w-3xl gap-6 px-5 py-8 mx-auto md:px-8 md:py-10"
    >
      <VoltarDoTrazer />
      <HeroiEscuro titulo>
        <template #frase>{{ tc('TITULO') }}</template>
        <template #apoio>{{ tc('APOIO') }}</template>
      </HeroiEscuro>
      <ul class="flex flex-col gap-3 p-0 m-0 list-none">
        <li v-for="caminho in daConta" :key="caminho.id">
          <router-link
            :to="rotas[caminho.id]"
            :data-como="caminho.id"
            :data-mais-facil="caminho.maisFacil ? '' : undefined"
            class="flex items-center gap-4 p-4 transition-colors group rounded-2xl min-h-24 sm:gap-5 sm:p-6 bg-n-solid-1 text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
            :class="
              caminho.maisFacil
                ? 'ring-2 ring-n-blue-9 shadow-md hover:bg-n-blue-2'
                : 'ring-1 ring-n-weak hover:ring-n-slate-7 hover:bg-n-alpha-1'
            "
          >
            <span
              aria-hidden="true"
              class="flex items-center justify-center size-12 rounded-2xl shrink-0 sm:size-14"
              :class="
                caminho.maisFacil
                  ? 'bg-n-blue-9 text-white'
                  : 'bg-n-alpha-2 text-n-slate-12'
              "
            >
              <span class="size-6 sm:size-7" :class="caminho.icone" />
            </span>
            <span class="flex flex-col flex-1 min-w-0 gap-1">
              <span
                v-if="caminho.maisFacil"
                data-carteira="mais-facil"
                class="self-start px-2.5 py-0.5 text-xs font-semibold rounded-full bg-n-blue-3 text-n-blue-11"
              >
                {{ tc('MAIS_FACIL') }}
              </span>
              <span class="text-base font-semibold sm:text-lg text-pretty">
                {{ tc(`${caminho.chave}.TITULO`) }}
              </span>
              <span class="text-sm sm:text-base text-n-slate-11 text-pretty">
                {{ tc(`${caminho.chave}.APOIO`) }}
              </span>
            </span>
            <span
              aria-hidden="true"
              class="transition-transform i-lucide-chevron-right size-6 shrink-0 text-n-slate-10 group-hover:translate-x-0.5 group-hover:text-n-slate-12 rtl:rotate-180"
            />
          </router-link>
        </li>
      </ul>
      <LinhaDeConfianca class="self-center" />
    </div>
  </section>
</template>
