<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useListaNova } from 'dashboard/components-next/Conversation/ListaDeConversas/useListaNova';

// #1801 — o resumo do dia num herói escuro (o mesmo de Automações). Os números vêm
// do servidor; o número maior que zero leva à lista certa; zero não é clicável. Quem vê os
// totais da conta ganha uma linha discreta da equipe. Uma ação: abrir a próxima conversa.
const props = defineProps({
  dados: { type: Object, required: true },
  // #1897: o destino do rodapé "Como vai o seu mês" (CRM › Números), ou nada.
  comoVaiOMes: { type: Object, default: null },
});

const { t } = useI18n();
const listaNova = useListaNova();

const numeros = computed(() => {
  const { esperamVoce, semResponsavel, foraDoPrazo } = props.dados;
  const lista = [
    { chave: 'ESPERAM', valor: esperamVoce, fazer: props.dados.verEsperam },
    {
      chave: 'SEM_RESPONSAVEL',
      valor: semResponsavel,
      fazer: props.dados.verSemResponsavel,
    },
  ];
  if (foraDoPrazo === null) return lista;
  return [
    ...lista,
    // Só informa: não há lista "fora do prazo" no painel para abrir.
    { chave: 'FORA_DO_PRAZO', valor: foraDoPrazo, alerta: foraDoPrazo > 0 },
  ];
});

// #2211 (A3), com a lista nova: "3 das suas 4 esperam você". Com uma conversa só, antes de carregar ou com a
// chave desligada, fica "Esperam você".
const rotuloDoNumero = numero => {
  const { comVoce, pronto } = props.dados;
  const comDasSuas =
    listaNova.value && numero.chave === 'ESPERAM' && pronto && comVoce > 1;
  if (!comDasSuas) {
    return t(`TELA_INICIAL.RESUMO.NUMEROS.${numero.chave}`);
  }
  return t(
    'TELA_INICIAL.RESUMO.NUMEROS.ESPERAM_DAS_SUAS',
    { total: comVoce },
    numero.valor
  );
};

const clicavel = numero =>
  props.dados.pronto && numero.valor > 0 && Boolean(numero.fazer);

const linhaDaEquipe = computed(() => {
  const { equipe } = props.dados;
  if (!equipe || !props.dados.pronto) return '';
  const partes = [
    t(
      'TELA_INICIAL.RESUMO.EQUIPE.ESPERAM',
      { count: equipe.esperam },
      equipe.esperam
    ),
  ];
  if (equipe.foraDoPrazo !== null) {
    partes.push(
      t(
        'TELA_INICIAL.RESUMO.EQUIPE.FORA_DO_PRAZO',
        { count: equipe.foraDoPrazo },
        equipe.foraDoPrazo
      )
    );
  }
  return partes.join(' · ');
});
</script>

<template>
  <section
    data-tela-inicial
    class="flex items-center justify-center w-full h-full p-4 overflow-auto bg-n-surface-1 md:p-10"
  >
    <div
      class="relative w-full max-w-3xl px-6 py-8 overflow-hidden text-white shadow-xl rounded-3xl bg-n-heroi dark:bg-n-heroi-escuro ring-1 ring-inset ring-white/10 md:px-10 md:py-10"
    >
      <span
        aria-hidden="true"
        class="absolute rounded-full pointer-events-none -end-16 -top-24 size-80 border-[3rem] border-n-blue-9 opacity-15"
      />
      <span
        aria-hidden="true"
        class="absolute rounded-full pointer-events-none end-32 -bottom-36 size-56 border-[2rem] border-n-blue-7 opacity-10"
      />
      <div class="relative flex flex-col gap-8">
        <header class="flex flex-col gap-2">
          <p
            class="mb-0 text-sm font-medium first-letter:uppercase text-white/60"
          >
            {{ dados.hoje }}
          </p>
          <h1
            class="mb-0 text-3xl font-bold leading-tight tracking-tight text-white md:text-4xl"
          >
            {{
              dados.tudoEmDia
                ? $t('TELA_INICIAL.TUDO_EM_DIA')
                : $t('TELA_INICIAL.RESUMO.TITULO')
            }}
          </h1>
          <p v-if="dados.pronto" class="mb-0 text-base text-white/75">
            {{
              $t(
                'TELA_INICIAL.RESUMO.COM_VOCE',
                { count: dados.comVoce },
                dados.comVoce
              )
            }}
          </p>
        </header>

        <ul
          class="grid gap-3 p-0 m-0 list-none"
          :class="numeros.length === 3 ? 'sm:grid-cols-3' : 'sm:grid-cols-2'"
        >
          <li v-for="numero in numeros" :key="numero.chave">
            <component
              :is="clicavel(numero) ? 'button' : 'div'"
              :type="clicavel(numero) ? 'button' : undefined"
              :data-numero="numero.chave"
              :data-clicavel="clicavel(numero) || undefined"
              class="flex flex-col items-start w-full h-full gap-1 p-5 transition text-start rounded-2xl bg-white/5 ring-1 ring-inset ring-white/10"
              :class="
                clicavel(numero)
                  ? 'hover:bg-white/10 focus-visible:outline focus-visible:outline-2 focus-visible:outline-white'
                  : ''
              "
              @click="clicavel(numero) && numero.fazer()"
            >
              <span
                class="text-4xl font-semibold leading-none tabular-nums"
                :class="numero.alerta ? 'text-n-amber-9' : 'text-white'"
              >
                {{
                  dados.pronto
                    ? numero.valor
                    : $t('TELA_INICIAL.RESUMO.CARREGANDO')
                }}
              </span>
              <span class="flex items-center gap-1 text-sm text-white/75">
                {{ rotuloDoNumero(numero) }}
                <span
                  v-if="clicavel(numero)"
                  class="i-lucide-chevron-right size-4 text-white/40 rtl:rotate-180"
                  aria-hidden="true"
                />
              </span>
            </component>
          </li>
        </ul>

        <p
          v-if="dados.estado === 'erro'"
          data-erro
          class="mb-0 text-sm text-white/75"
        >
          {{ $t('TELA_INICIAL.RESUMO.ERRO') }}
          <button
            type="button"
            data-tentar-de-novo
            class="font-semibold text-white underline underline-offset-2 hover:text-white/80 focus-visible:outline focus-visible:outline-2 focus-visible:outline-white"
            @click="dados.tentarDeNovo()"
          >
            {{ $t('TELA_INICIAL.RESUMO.TENTAR_DE_NOVO') }}
          </button>
        </p>
        <div
          v-else-if="dados.pronto && dados.proxima"
          class="flex flex-col items-start gap-3 sm:flex-row sm:items-center sm:gap-5"
        >
          <button
            type="button"
            data-abrir-proxima
            class="inline-flex items-center justify-center gap-3 px-6 text-base font-semibold transition bg-white min-h-12 rounded-xl text-n-heroi hover:bg-white/90 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white"
            @click="dados.abrir(dados.proxima)"
          >
            {{ $t('TELA_INICIAL.ABRIR_PROXIMA') }}
            <span
              class="i-lucide-arrow-right size-5 rtl:rotate-180"
              aria-hidden="true"
            />
          </button>
          <p class="mb-0 text-sm text-white/60">
            {{
              dados.nomeDoCliente(dados.proxima)
                ? $t('TELA_INICIAL.PROXIMA_ESPERA', {
                    nome: dados.nomeDoCliente(dados.proxima),
                    tempo: dados.esperaHa(dados.proxima),
                  })
                : $t('TELA_INICIAL.PROXIMA_ESPERA_SEM_NOME', {
                    tempo: dados.esperaHa(dados.proxima),
                  })
            }}
          </p>
        </div>
        <div v-else-if="dados.pronto" class="flex flex-col items-start gap-3">
          <button
            type="button"
            data-acao-do-vazio
            class="inline-flex items-center justify-center gap-3 px-6 text-base font-semibold transition bg-white min-h-12 rounded-xl text-n-heroi hover:bg-white/90 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white"
            @click="dados.acaoDoVazio.fazer()"
          >
            {{ $t(`TELA_INICIAL.${dados.acaoDoVazio.rotulo}`) }}
            <span
              class="i-lucide-arrow-right size-5 rtl:rotate-180"
              aria-hidden="true"
            />
          </button>
        </div>

        <div v-if="linhaDaEquipe" class="pt-5 border-t border-white/10">
          <component
            :is="dados.equipe && dados.equipe.esperam > 0 ? 'button' : 'p'"
            :type="dados.equipe.esperam > 0 ? 'button' : undefined"
            data-equipe
            class="flex items-center gap-2 mb-0 text-sm transition text-white/60"
            :class="
              dados.equipe.esperam > 0
                ? 'hover:text-white focus-visible:outline focus-visible:outline-2 focus-visible:outline-white'
                : ''
            "
            @click="dados.equipe.esperam > 0 && dados.verEquipe()"
          >
            <span class="i-lucide-users size-4" aria-hidden="true" />
            {{ linhaDaEquipe }}
          </component>
        </div>

        <div
          v-if="comoVaiOMes"
          class="hidden pt-5 border-t border-white/10 md:block"
        >
          <RouterLink
            :to="comoVaiOMes"
            data-como-vai-o-mes
            class="inline-flex items-center gap-2 text-sm font-medium transition min-h-11 text-white/75 hover:text-white focus-visible:outline focus-visible:outline-2 focus-visible:outline-white"
          >
            <span class="i-lucide-chart-column size-4" aria-hidden="true" />
            {{ $t('CRM_NUMEROS_V2.TELA_INICIAL') }}
            <span
              class="i-lucide-arrow-right size-4 rtl:rotate-180"
              aria-hidden="true"
            />
          </RouterLink>
        </div>
      </div>
    </div>
  </section>
</template>
