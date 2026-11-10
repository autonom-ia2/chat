<script setup>
import { useI18n } from 'vue-i18n';
import { chaveDoTexto, ferramentaPorId } from '../catalogo';

// #2858 F3 — no Confira do Construtor: as ferramentas prontas que o Construtor escolheu, pelo sentido do que a pessoa
// contou, para o agente já nascer com elas. Mostrar antes de fazer: cada uma com ícone, uma linha e "Tirar"; elas
// entram no "Começar". Lista vazia ("nenhuma combina"): o bloco não aparece. Sem a chave das ferramentas
// (`semPermissao`), uma frase diz que elas ficam para quem cuida das ferramentas, sem "Tirar".
const props = defineProps({
  nome: { type: String, required: true },
  ids: { type: Array, required: true },
  semPermissao: { type: Boolean, default: false },
});

const emit = defineEmits(['tirar']);

const NS = 'AGENTS.VITRINE';
const { t, locale } = useI18n();
const texto = (id, campo) =>
  t(`${NS}.FERRAMENTAS.${chaveDoTexto(id)}.${campo}`);
const icone = id => ferramentaPorId(id)?.icone || 'i-lucide-wrench';
const nomes = () =>
  new Intl.ListFormat(String(locale.value).replace('_', '-'), {
    type: 'conjunction',
  }).format(props.ids.map(id => texto(id, 'NOME')));
</script>

<template>
  <!-- display: contents: sem caixa própria, o vazio não ocupa espaço nem cria gap na coluna da página. -->
  <div class="contents">
    <section
      v-if="ids.length"
      data-ja-vem
      aria-labelledby="ja-vem-titulo"
      class="flex flex-col gap-3 p-4 rounded-2xl bg-n-solid-2 ring-1 ring-inset ring-n-weak"
    >
      <div class="flex flex-col gap-0.5">
        <h3
          id="ja-vem-titulo"
          class="flex items-center gap-2 m-0 text-base font-semibold text-n-slate-12"
        >
          <span
            class="i-lucide-package-check size-5 text-n-blue-11"
            aria-hidden="true"
          />
          {{
            semPermissao
              ? t(`${NS}.JA_VEM.TITULO_SEM_PERMISSAO`, { nome })
              : t(`${NS}.JA_VEM.TITULO`, { nome })
          }}
        </h3>
        <p class="m-0 text-sm text-n-slate-11">
          {{
            semPermissao
              ? t(`${NS}.JA_VEM.SEM_PERMISSAO`, { nome, ferramentas: nomes() })
              : t(`${NS}.JA_VEM.TEXTO`)
          }}
        </p>
      </div>
      <ul v-if="!semPermissao" class="flex flex-col gap-1 p-0 m-0 list-none">
        <li
          v-for="id in ids"
          :key="id"
          :data-ja-vem-item="id"
          class="flex items-center gap-3 py-1"
        >
          <span
            aria-hidden="true"
            class="grid rounded-lg place-items-center size-9 shrink-0 bg-n-blue-3 text-n-blue-11"
          >
            <span :class="icone(id)" class="size-5" />
          </span>
          <span class="flex flex-col flex-1 min-w-0">
            <span class="text-sm font-semibold text-n-slate-12">
              {{ texto(id, 'NOME') }}
            </span>
            <span class="text-sm text-n-slate-11">
              {{ texto(id, 'FAZ') }}
            </span>
          </span>
          <button
            type="button"
            data-ja-vem-tirar
            :aria-label="
              t(`${NS}.JA_VEM.TIRAR_SR`, { ferramenta: texto(id, 'NOME') })
            "
            class="px-3 text-sm font-medium rounded-lg min-h-11 text-n-ruby-11 hover:bg-n-ruby-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
            @click="emit('tirar', id)"
          >
            {{ t(`${NS}.JA_VEM.TIRAR`) }}
          </button>
        </li>
      </ul>
    </section>
  </div>
</template>
