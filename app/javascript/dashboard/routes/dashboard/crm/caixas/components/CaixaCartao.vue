<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import CaixaIcone from './CaixaIcone.vue';
import FunilSelo from './FunilSelo.vue';
import {
  corDoFunil,
  faltaTriagem,
  funisDaCaixa,
  juntar,
  legadoPendente,
  modoDaCaixa,
  primeiroNome,
  quemFazTriagem,
} from '../helpers/caixa';

// #1149 — uma caixa na lista: o que chega, quem cuida e o que o sistema faz
// sozinho, em frases. O botão abre a caixa nas etapas.
const props = defineProps({
  caixa: { type: Object, required: true },
  funis: { type: Array, required: true },
  salvaAgora: { type: Boolean, default: false },
});

defineEmits(['alterar']);

const { t, locale } = useI18n();

const ligada = computed(() => props.caixa.crm_enabled);
const funis = computed(() => funisDaCaixa(props.caixa, props.funis));
// Todo mundo da caixa, administrador incluído: numa conta em que só há
// administradores, "0 pessoas" diria que ninguém cuida, e todos veem tudo.
const pessoas = computed(() => props.caixa.people.length);
const triagem = computed(() =>
  juntar(quemFazTriagem(props.caixa).map(primeiroNome), locale.value)
);
const sozinho = computed(() =>
  t(`CRM_CAIXAS.MODO_RESUMO.${modoDaCaixa(props.caixa).toUpperCase()}`)
);

const aviso = computed(() => {
  if (!ligada.value) return '';
  if (faltaTriagem(props.caixa)) return t('CRM_CAIXAS.CARTAO.AVISO_TRIAGEM');
  if (legadoPendente(props.caixa)) return t('CRM_CAIXAS.CARTAO.AVISO_LEGADO');
  return '';
});
</script>

<template>
  <article
    data-caixa
    class="flex flex-col gap-5 rounded-2xl border bg-n-solid-1 p-5 md:p-6"
    :class="aviso ? 'border-n-amber-7' : 'border-n-weak'"
  >
    <header class="flex items-start gap-3">
      <CaixaIcone :canal="caixa.inbox.channel_type" />
      <div class="min-w-0 flex-1">
        <h2 class="mb-1 truncate text-lg font-semibold text-n-slate-12">
          {{ caixa.inbox.name }}
        </h2>
        <span
          class="inline-flex items-center gap-1.5 text-sm"
          :class="ligada ? 'text-n-teal-11' : 'text-n-slate-11'"
        >
          <span
            class="size-2 rounded-full"
            :class="ligada ? 'bg-n-teal-9' : 'bg-n-slate-8'"
            aria-hidden="true"
          />
          {{
            ligada
              ? $t('CRM_CAIXAS.CARTAO.NO_CRM')
              : $t('CRM_CAIXAS.CARTAO.FORA')
          }}
        </span>
      </div>
      <span
        v-if="salvaAgora"
        class="inline-flex items-center gap-1.5 rounded-lg bg-n-teal-3 px-2.5 py-1 text-sm font-medium text-n-teal-11"
        role="status"
      >
        <span class="i-lucide-check size-4" aria-hidden="true" />
        {{ $t('CRM_CAIXAS.CARTAO.SALVA') }}
      </span>
    </header>

    <p
      v-if="aviso"
      class="mb-0 flex items-start gap-2 rounded-xl bg-n-amber-3 px-3 py-2.5 text-[0.9375rem] text-n-slate-12"
    >
      <span
        class="i-lucide-triangle-alert mt-0.5 size-4 shrink-0 text-n-amber-11"
        aria-hidden="true"
      />
      {{ aviso }}
    </p>

    <dl v-if="ligada" class="m-0 grid gap-4">
      <div class="grid gap-1.5">
        <dt class="text-sm text-n-slate-11">
          {{ $t('CRM_CAIXAS.CARTAO.CHEGA') }}
        </dt>
        <dd class="m-0 flex flex-wrap gap-2">
          <FunilSelo
            v-for="funil in funis"
            :key="funil.id"
            :nome="funil.name"
            :cor="corDoFunil(props.funis, funil.id)"
          />
        </dd>
      </div>
      <div class="grid gap-1">
        <dt class="text-sm text-n-slate-11">
          {{ $t('CRM_CAIXAS.CARTAO.CUIDAM') }}
        </dt>
        <dd class="m-0 text-[0.9375rem] text-n-slate-12">
          {{ $t('CRM_CAIXAS.CARTAO.PESSOAS', { n: pessoas }, pessoas) }}
          <template v-if="funis.length > 1 && triagem">
            {{ $t('CRM_CAIXAS.CARTAO.SEM_ASSUNTO', { nomes: triagem }) }}
          </template>
        </dd>
      </div>
      <div class="grid gap-1">
        <dt class="text-sm text-n-slate-11">
          {{ $t('CRM_CAIXAS.CARTAO.SOZINHO') }}
        </dt>
        <dd class="m-0 text-[0.9375rem] text-n-slate-12">{{ sozinho }}</dd>
      </div>
    </dl>
    <p v-else class="mb-0 text-[0.9375rem] text-n-slate-11">
      {{ $t('CRM_CAIXAS.CARTAO.FORA_TEXTO') }}
    </p>

    <footer class="mt-auto flex">
      <Button
        data-alterar
        :label="
          ligada
            ? $t('CRM_CAIXAS.CARTAO.ALTERAR')
            : $t('CRM_CAIXAS.CARTAO.LIGAR')
        "
        :icon="ligada ? 'i-lucide-pencil' : 'i-lucide-plus'"
        :slate="ligada"
        :faded="ligada"
        class="!min-h-11"
        @click="$emit('alterar', caixa)"
      />
    </footer>
  </article>
</template>
