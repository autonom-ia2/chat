<script setup>
import { computed } from 'vue';
import { mesclarPrevia, previaDaFuncao } from '../fraseDaFuncao';
import { useTextos } from './useTextos';

// "Como vai ficar" (#2308, especificação 8): a frase, o Pode e o Não pode, estáveis desde o começo (fotografados de
// `inicial`), e o menu. "novo" só no Pode. Depois de salvar, o título vira "Salva". Só o Pode e o Não pode são
// região viva: a frase leva o nome, e anunciar a cada letra digitada atropelaria quem escreve.
const props = defineProps({
  nome: { type: String, default: '' },
  permissions: { type: Array, required: true },
  inicial: { type: Array, required: true },
  salva: { type: Boolean, default: false },
});

const { t, lista } = useTextos();

const previa = computed(() =>
  mesclarPrevia(
    previaDaFuncao(props.inicial),
    previaDaFuncao(props.permissions)
  )
);

const frase = computed(() => {
  const { destaque, resto } = previa.value.frase;
  const comeco = t(`FUNCOES_EQUIPE.FRASE_INICIO.${destaque}`);
  const abre = props.nome
    ? t('FUNCOES_EQUIPE.PREVIA.ABRE', { nome: props.nome, comeco })
    : t('FUNCOES_EQUIPE.PREVIA.ABRE_SEM_NOME', { comeco });
  return [abre, ...resto.map(chave => t(`FUNCOES_EQUIPE.FRASE.${chave}`))].join(
    ' '
  );
});

const menu = computed(() =>
  lista(previa.value.menu.map(item => t(`FUNCOES_EQUIPE.MENU.${item}`)))
);
</script>

<template>
  <aside
    data-previa
    class="flex flex-col w-full gap-5 p-6 border rounded-2xl border-n-weak bg-n-solid-1"
  >
    <p
      class="flex items-center gap-2 m-0 text-sm font-semibold"
      :class="salva ? 'text-n-teal-11' : 'text-n-blue-11'"
    >
      <span v-if="salva" class="i-lucide-check size-4" aria-hidden="true" />
      {{
        salva
          ? $t('FUNCOES_EQUIPE.PREVIA.SALVA')
          : $t('FUNCOES_EQUIPE.PREVIA.TITULO')
      }}
    </p>
    <p
      data-frase
      class="m-0 text-xl font-semibold leading-snug text-n-slate-12"
    >
      {{ frase }}
    </p>

    <div data-ao-vivo aria-live="polite" class="flex flex-col gap-5">
      <div v-if="previa.pode.length" class="flex flex-col gap-2">
        <h2 class="m-0 text-sm font-semibold text-n-slate-12">
          {{ $t('FUNCOES_EQUIPE.PREVIA.PODE') }}
        </h2>
        <ul data-pode class="flex flex-col gap-1 p-0 m-0 list-none">
          <li
            v-for="item in previa.pode"
            :key="item.id"
            :data-id="item.id"
            class="flex items-start gap-3 px-2 py-1.5 -mx-2 rounded-lg text-[0.9375rem] text-n-slate-12"
            :class="item.novo ? 'bg-n-blue-2' : ''"
          >
            <span
              class="i-lucide-check size-4 mt-1 shrink-0 text-n-teal-11"
              aria-hidden="true"
            />
            <span class="flex-1">{{
              $t(`FUNCOES_EQUIPE.PODE.${item.id}`)
            }}</span>
            <span
              v-if="item.novo"
              data-novo
              class="px-2 py-0.5 text-xs font-medium rounded-md shrink-0 bg-n-blue-3 text-n-blue-11"
            >
              {{ $t('FUNCOES_EQUIPE.PREVIA.NOVO') }}
            </span>
          </li>
        </ul>
      </div>

      <div v-if="previa.naoPode.length" class="flex flex-col gap-2">
        <h2 class="m-0 text-sm font-semibold text-n-slate-12">
          {{ $t('FUNCOES_EQUIPE.PREVIA.NAO_PODE') }}
        </h2>
        <ul data-nao-pode class="flex flex-col gap-1 p-0 m-0 list-none">
          <li
            v-for="id in previa.naoPode"
            :key="id"
            :data-id="id"
            class="flex items-start gap-3 py-1.5 text-[0.9375rem] text-n-slate-12"
          >
            <span
              class="i-lucide-x size-4 mt-1 shrink-0 text-n-slate-11"
              aria-hidden="true"
            />
            {{ $t(`FUNCOES_EQUIPE.PODE.${id}`) }}
          </li>
        </ul>
      </div>
    </div>

    <p
      v-if="previa.menu.length"
      data-menu
      class="pt-4 m-0 text-sm border-t border-n-weak text-n-slate-11"
    >
      {{ $t('FUNCOES_EQUIPE.PREVIA.MENU', { itens: menu }) }}
    </p>
  </aside>
</template>
