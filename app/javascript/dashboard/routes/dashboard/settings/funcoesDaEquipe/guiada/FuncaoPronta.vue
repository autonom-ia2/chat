<script setup>
import { computed } from 'vue';
import { ICONE_DA_CAPACIDADE, useCartao } from './useCartao';

// Um cartão de função pronta (#2308, especificação 5.B1 e 9). Anatomia única; tocar em qualquer parte faz a ação
// principal (botão esticado). Quando a conta já tem a função, o rodapé diz quantas pessoas a usam e, com Pessoas e
// alcance, a ação principal é "Pôr uma pessoa nela", com o link irmão "Criar outra a partir da pronta".
const props = defineProps({
  cartao: { type: Object, required: true },
  // { funcao, pessoas } da função da conta com o mesmo nome, ou null.
  existente: { type: Object, default: null },
  podePorPessoa: { type: Boolean, default: false },
  // Por que não põe pessoas nela: ABOVE, MINE ou '' (sem Pessoas, nada a dizer).
  travaDaPessoa: { type: String, default: '' },
});

const emit = defineEmits(['criar', 'porPessoa']);
const { capacidade, selo, trava, nome, descricao } = useCartao();

const textoDoSelo = computed(() => selo(props.cartao.selo));
const poe = computed(() => Boolean(props.existente) && props.podePorPessoa);

// O nome tem a mesma letra e a mesma caixa nos dois tipos de cartão (anatomia única, especificação 9): o botão não
// herda o tamanho e o peso do título, e o _base.scss dá a todo <button> py-1 px-2.5, que empurrava o nome 10 px para
// a direita do ícone e mudava a altura da linha. A classe vai no próprio nome, botão ou não, com p-0 e m-0.
const NOME = 'p-0 m-0 text-lg font-semibold leading-snug text-n-slate-12';
const ESTICADO =
  'after:absolute after:inset-0 after:rounded-2xl focus-visible:outline-none';
</script>

<template>
  <li
    :data-pronta="cartao.chave"
    class="relative flex flex-col gap-3 p-5 transition border rounded-2xl border-n-weak bg-n-solid-1 hover:border-n-blue-7 has-[:focus-visible]:ring-2 has-[:focus-visible]:ring-n-brand"
  >
    <span
      class="grid place-items-center size-11 rounded-xl"
      :class="cartao.tom"
    >
      <span class="size-5" :class="cartao.icone" aria-hidden="true" />
    </span>
    <h2 class="flex items-center gap-2 m-0">
      <button
        v-if="!existente"
        type="button"
        data-principal
        data-nome
        class="flex-1 text-start"
        :class="[NOME, ESTICADO]"
        :aria-label="
          $t('FUNCOES_EQUIPE.ESCOLHA.CRIAR', { nome: nome(cartao.chave) })
        "
        @click="emit('criar')"
      >
        {{ nome(cartao.chave) }}
      </button>
      <span v-else data-nome class="flex-1" :class="NOME">
        {{ nome(cartao.chave) }}
      </span>
      <span
        v-if="!existente"
        class="i-lucide-chevron-right size-5 text-n-slate-11 rtl:rotate-180"
        aria-hidden="true"
      />
    </h2>
    <p class="m-0 text-[0.9375rem] leading-snug text-n-slate-11">
      {{ descricao(cartao.chave) }}
    </p>
    <ul class="flex flex-col gap-1.5 p-0 m-0 list-none text-[0.9375rem]">
      <li
        v-for="item in cartao.capacidades"
        :key="item.chave"
        :data-tipo="item.tipo"
        class="flex items-start gap-2 text-n-slate-12"
      >
        <span
          class="size-4 mt-1 shrink-0"
          :class="ICONE_DA_CAPACIDADE[item.tipo]"
          aria-hidden="true"
        />
        {{ capacidade(item) }}
      </li>
    </ul>
    <p
      v-if="textoDoSelo"
      data-selo-cuidado
      class="flex items-start gap-1.5 px-2.5 py-1.5 m-0 text-sm rounded-lg bg-n-alpha-2 text-n-slate-12"
    >
      <span
        class="i-lucide-triangle-alert size-4 mt-0.5 shrink-0 text-n-amber-11"
        aria-hidden="true"
      />
      {{ textoDoSelo }}
    </p>
    <p
      v-for="item in cartao.travas"
      :key="item.motivo"
      :data-trava="item.motivo"
      class="flex items-start gap-1.5 m-0 text-sm text-n-slate-11"
    >
      <span class="i-lucide-lock size-4 mt-0.5 shrink-0" aria-hidden="true" />
      {{ trava(item) }}
    </p>

    <footer
      v-if="existente"
      class="flex flex-col gap-3 pt-3 mt-auto border-t border-n-weak"
    >
      <p class="flex items-center gap-1.5 m-0 text-sm text-n-slate-11">
        <span class="i-lucide-info size-4 shrink-0" aria-hidden="true" />
        {{
          $t(
            'FUNCOES_EQUIPE.ESCOLHA.JA_TEM',
            { n: existente.pessoas },
            existente.pessoas
          )
        }}
      </p>
      <p
        v-if="travaDaPessoa"
        data-trava-pessoa
        class="m-0 text-sm text-n-slate-11"
      >
        {{ $t(`FUNCOES_EQUIPE.ESCOLHA.TRAVA_PESSOA.${travaDaPessoa}`) }}
      </p>
      <div class="flex flex-wrap items-center gap-x-4 gap-y-2">
        <button
          type="button"
          data-principal
          class="inline-flex items-center gap-2 px-4 text-sm font-medium rounded-xl min-h-11 bg-n-alpha-2 text-n-slate-12"
          :class="ESTICADO"
          :aria-label="
            poe
              ? $t('FUNCOES_EQUIPE.ESCOLHA.POR_PESSOA_ROTULO', {
                  nome: nome(cartao.chave),
                })
              : $t('FUNCOES_EQUIPE.ESCOLHA.CRIAR_A_PARTIR_ROTULO', {
                  nome: nome(cartao.chave),
                })
          "
          @click="poe ? emit('porPessoa') : emit('criar')"
        >
          <span
            v-if="poe"
            class="i-lucide-user-plus size-4"
            aria-hidden="true"
          />
          {{
            poe
              ? $t('FUNCOES_EQUIPE.ESCOLHA.POR_PESSOA')
              : $t('FUNCOES_EQUIPE.ESCOLHA.CRIAR_A_PARTIR')
          }}
        </button>
        <button
          v-if="poe"
          type="button"
          data-criar-a-partir
          :aria-label="
            $t('FUNCOES_EQUIPE.ESCOLHA.CRIAR_A_PARTIR_ROTULO', {
              nome: nome(cartao.chave),
            })
          "
          class="relative z-10 px-0 text-sm font-medium underline min-h-11 underline-offset-4 text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="emit('criar')"
        >
          {{ $t('FUNCOES_EQUIPE.ESCOLHA.CRIAR_A_PARTIR') }}
        </button>
      </div>
    </footer>
  </li>
</template>
