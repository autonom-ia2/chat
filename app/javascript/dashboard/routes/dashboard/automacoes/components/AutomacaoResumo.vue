<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { trocarNome } from 'dashboard/helper/automacaoEmPortugues';

// #859/#982 — a automação em três blocos: Quando → Só se → Faz. O texto vem
// pronto de `descreverAutomacao` (helper/automacaoEmPortugues.js). Quando ela
// manda mensagem, a prévia mostra o texto como o cliente vê, com um nome de
// exemplo no lugar da variável. Sem automação ainda, os blocos aparecem vazios
// dizendo que o Guia preenche.
const props = defineProps({
  descricao: { type: Object, default: null },
  regra: { type: Object, default: null },
});

const { t } = useI18n();

const mensagem = computed(() => {
  const acao = (props.regra?.actions || []).find(
    item => item.action_name === 'send_message'
  );
  const texto = Array.isArray(acao?.action_params)
    ? acao.action_params[0]
    : acao?.action_params;
  if (!texto || typeof texto !== 'string') return '';
  return trocarNome(texto, t('AUTOMACOES.RESUMO.NOME_EXEMPLO'));
});

// Com a prévia aparecendo, o passo da mensagem não repete o texto: vira "Manda
// esta mensagem ao cliente", e a prévia mostra qual.
const passos = computed(() =>
  (props.descricao?.entao || []).map((texto, indice) =>
    mensagem.value &&
    props.regra?.actions?.[indice]?.action_name === 'send_message'
      ? t('AUTOMACOES.RESUMO.MANDA_MENSAGEM')
      : texto
  )
);

const situacao = computed(() => {
  if (!props.regra) return null;
  return props.regra.active
    ? {
        texto: t('AUTOMACOES.RESUMO.LIGADA'),
        tom: 'bg-n-teal-3 text-n-teal-11',
        ponto: 'bg-n-teal-9',
      }
    : {
        texto: t('AUTOMACOES.RESUMO.DESLIGADA'),
        tom: 'bg-n-amber-3 text-n-amber-11',
        ponto: 'bg-n-amber-9',
      };
});

const BLOCOS = [
  {
    chave: 'QUANDO',
    icone: 'i-lucide-zap',
    tom: 'bg-n-blue-3 text-n-blue-11',
  },
  {
    chave: 'SE',
    icone: 'i-lucide-list-filter',
    tom: 'bg-n-violet-3 text-n-violet-11',
  },
  {
    chave: 'ENTAO',
    icone: 'i-lucide-send',
    tom: 'bg-n-teal-3 text-n-teal-11',
  },
];
const bloco = chave => BLOCOS.find(item => item.chave === chave);
</script>

<template>
  <section
    class="flex flex-col gap-6 p-6 border shadow-md rounded-3xl border-n-weak bg-n-solid-1"
    :aria-label="$t('AUTOMACOES.RESUMO.TITULO')"
  >
    <div class="flex flex-wrap items-center justify-between gap-3">
      <h2 class="text-lg font-semibold text-n-slate-12">
        {{ $t('AUTOMACOES.RESUMO.TITULO') }}
      </h2>
      <span
        v-if="situacao"
        data-situacao-pilula
        class="inline-flex items-center gap-2 px-3 py-1.5 text-sm font-medium rounded-full"
        :class="situacao.tom"
      >
        <span class="rounded-full size-2" :class="situacao.ponto" />
        {{ situacao.texto }}
      </span>
    </div>

    <div v-if="!descricao" data-resumo-vazio class="flex flex-col gap-5">
      <div
        v-for="item in BLOCOS"
        :key="item.chave"
        class="flex items-center gap-4"
      >
        <span
          class="grid border-2 border-dashed rounded-2xl place-items-center size-11 shrink-0 border-n-slate-6 text-n-slate-9"
        >
          <span class="size-5" :class="item.icone" aria-hidden="true" />
        </span>
        <div class="flex flex-col gap-1.5 flex-1">
          <span
            class="text-xs font-semibold tracking-wider uppercase text-n-slate-10"
          >
            {{ $t(`AUTOMACOES.RESUMO.${item.chave}`) }}
          </span>
          <span class="h-3 rounded-full w-3/4 bg-n-alpha-2" />
        </div>
      </div>
      <p class="mb-0 text-[0.9375rem] text-n-slate-11">
        {{ $t('AUTOMACOES.RESUMO.VAZIO') }}
      </p>
    </div>

    <ol v-else class="flex flex-col gap-5 p-0 m-0 list-none">
      <li class="flex gap-4">
        <span
          class="grid rounded-2xl place-items-center size-11 shrink-0"
          :class="bloco('QUANDO').tom"
        >
          <span
            class="size-5"
            :class="bloco('QUANDO').icone"
            aria-hidden="true"
          />
        </span>
        <div class="flex flex-col min-w-0 gap-1">
          <span
            class="text-xs font-semibold tracking-wider uppercase text-n-slate-10"
          >
            {{ $t('AUTOMACOES.RESUMO.QUANDO') }}
          </span>
          <span data-quando class="text-base text-n-slate-12 break-words">
            {{ descricao.quando }}
          </span>
        </div>
      </li>
      <li class="flex gap-4">
        <span
          class="grid rounded-2xl place-items-center size-11 shrink-0"
          :class="bloco('SE').tom"
        >
          <span class="size-5" :class="bloco('SE').icone" aria-hidden="true" />
        </span>
        <div class="flex flex-col min-w-0 gap-1">
          <span
            class="text-xs font-semibold tracking-wider uppercase text-n-slate-10"
          >
            {{ $t('AUTOMACOES.RESUMO.SE') }}
          </span>
          <ul
            v-if="descricao.se.length"
            data-se
            class="flex flex-col gap-1 p-0 m-0 list-none"
          >
            <li
              v-for="(condicao, indice) in descricao.se"
              :key="indice"
              class="text-base text-n-slate-12 break-words"
            >
              <span v-if="indice > 0" class="text-n-slate-11">
                {{ descricao.se[indice - 1].liga }}
              </span>
              {{ condicao.texto }}
            </li>
          </ul>
          <span v-else class="text-base text-n-slate-12">
            {{ $t('AUTOMACOES.RESUMO.SEM_CONDICAO') }}
          </span>
        </div>
      </li>
      <li class="flex gap-4">
        <span
          class="grid rounded-2xl place-items-center size-11 shrink-0"
          :class="bloco('ENTAO').tom"
        >
          <span
            class="size-5"
            :class="bloco('ENTAO').icone"
            aria-hidden="true"
          />
        </span>
        <div class="flex flex-col flex-1 min-w-0 gap-1">
          <span
            class="text-xs font-semibold tracking-wider uppercase text-n-slate-10"
          >
            {{ $t('AUTOMACOES.RESUMO.ENTAO') }}
          </span>
          <ul data-entao class="flex flex-col gap-1 p-0 m-0 list-none">
            <li
              v-for="(acao, indice) in passos"
              :key="indice"
              class="text-base text-n-slate-12 break-words"
            >
              {{ acao }}
            </li>
          </ul>
          <figure
            v-if="mensagem"
            data-previa
            class="flex flex-col gap-2 p-3.5 mt-3 m-0 rounded-2xl bg-n-teal-2"
          >
            <p
              class="self-start max-w-[92%] px-3.5 py-2.5 m-0 text-[0.9375rem] leading-relaxed whitespace-pre-line break-words rounded-xl rounded-bl-sm shadow-sm bg-n-solid-1 text-n-slate-12"
            >
              {{ mensagem }}
            </p>
            <figcaption class="text-xs text-n-slate-11">
              {{ $t('AUTOMACOES.RESUMO.PREVIA') }}
            </figcaption>
          </figure>
        </div>
      </li>
    </ol>
  </section>
</template>
