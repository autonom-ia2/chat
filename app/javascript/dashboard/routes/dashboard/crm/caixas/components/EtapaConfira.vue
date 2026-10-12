<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import FunilSelo from './FunilSelo.vue';
import {
  assuntosDe,
  corDoFunil,
  funisDaCaixa,
  juntar,
  mudancas,
  primeiroNome,
  quemCuida,
  quemFazTriagem,
} from '../helpers/caixa';

// #1149 — etapa 4: a caixa inteira em frases antes do Salvar, com o que muda
// em relação ao que está salvo hoje.
const props = defineProps({
  form: { type: Object, required: true },
  original: { type: Object, required: true },
  funis: { type: Array, required: true },
});

const { t, locale } = useI18n();

const funisMarcados = computed(() => funisDaCaixa(props.form, props.funis));
const varios = computed(() => funisMarcados.value.length > 1);
const nomes = pessoas => juntar(pessoas.map(primeiroNome), locale.value);

const pessoas = computed(() =>
  [...props.form.people]
    .sort(
      (a, b) =>
        Number(a.administrator) - Number(b.administrator) ||
        a.name.localeCompare(b.name)
    )
    .map(pessoa => {
      if (pessoa.administrator) {
        return { pessoa, texto: t('CRM_CAIXAS.CONFIRA.ADMIN') };
      }
      const assuntos = assuntosDe(
        pessoa,
        funisMarcados.value,
        t('CRM_CAIXAS.CONFIRA.SEM_ASSUNTO')
      );
      if (!assuntos.length) {
        return { pessoa, texto: t('CRM_CAIXAS.CONFIRA.NADA') };
      }
      const chave = pessoa.only_own ? 'SO_SUAS' : 'TODAS';
      return {
        pessoa,
        texto: t(`CRM_CAIXAS.CONFIRA.${chave}`, {
          assuntos: juntar(assuntos, locale.value),
        }),
      };
    })
);

const rodizio = computed(() => [
  ...(varios.value
    ? [
        {
          chave: 'triagem',
          nome: t('CRM_CAIXAS.CONFIRA.SEM_ASSUNTO_TITULO'),
          cor: 'bg-n-slate-8',
          quem: nomes(quemFazTriagem(props.form)),
        },
      ]
    : []),
  ...funisMarcados.value.map(funil => ({
    chave: funil.id,
    nome: funil.name,
    cor: corDoFunil(props.funis, funil.id),
    quem: nomes(quemCuida(props.form, funil.id)),
  })),
]);

const lista = computed(() =>
  mudancas(props.original, props.form, props.funis, {
    semAssunto: t('CRM_CAIXAS.CONFIRA.SEM_ASSUNTO'),
    locale: locale.value,
  }).map(({ chave, valores }) =>
    t(`CRM_CAIXAS.MUDA.${chave}`, {
      ...valores,
      resumo: valores.modo
        ? t(`CRM_CAIXAS.MODO_RESUMO.${valores.modo.toUpperCase()}`)
        : '',
    })
  )
);
</script>

<template>
  <div class="flex flex-col gap-4">
    <section
      v-if="!funisMarcados.length"
      class="rounded-2xl border border-n-amber-7 bg-n-amber-2 p-5 text-base text-n-slate-12"
    >
      {{ $t('CRM_CAIXAS.CONFIRA.SAI_DO_CRM') }}
    </section>

    <template v-else>
      <section
        class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-5"
      >
        <h3 class="mb-0 text-base font-semibold text-n-slate-12">
          {{ $t('CRM_CAIXAS.ETAPAS.CHEGA') }}
        </h3>
        <div class="flex flex-wrap gap-2">
          <FunilSelo
            v-for="funil in funisMarcados"
            :key="funil.id"
            :nome="funil.name"
            :cor="corDoFunil(funis, funil.id)"
          />
        </div>
        <p class="mb-0 text-[0.9375rem] text-n-slate-11">
          {{ $t(`CRM_CAIXAS.MODO_RESUMO.${form.modo.toUpperCase()}`) }}
        </p>
      </section>

      <section
        class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-5"
      >
        <h3 class="mb-0 text-base font-semibold text-n-slate-12">
          {{ $t('CRM_CAIXAS.CONFIRA.QUEM_VE') }}
        </h3>
        <ul class="m-0 flex list-none flex-col gap-3 p-0">
          <li
            v-for="linha in pessoas"
            :key="linha.pessoa.id"
            class="flex items-start gap-3"
          >
            <Avatar :name="linha.pessoa.name" :size="28" rounded-full />
            <p class="mb-0 pt-0.5 text-[0.9375rem] text-n-slate-12">
              <strong class="font-semibold">{{ linha.pessoa.name }}</strong>
              {{ linha.texto }}
            </p>
          </li>
        </ul>
      </section>

      <section
        class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-5"
      >
        <h3 class="mb-0 text-base font-semibold text-n-slate-12">
          {{ $t('CRM_CAIXAS.CONFIRA.RODIZIO') }}
        </h3>
        <ul class="m-0 flex list-none flex-col gap-2 p-0">
          <li
            v-for="item in rodizio"
            :key="item.chave"
            class="flex flex-wrap items-center gap-x-2 text-[0.9375rem] text-n-slate-12"
          >
            <span
              class="size-2.5 rounded-full"
              :class="item.cor"
              aria-hidden="true"
            />
            <strong class="font-semibold">{{ item.nome }}:</strong>
            <span :class="item.quem ? '' : 'text-n-ruby-11'">
              {{ item.quem || $t('CRM_CAIXAS.CONFIRA.NINGUEM') }}
            </span>
          </li>
        </ul>
      </section>
    </template>

    <section
      class="flex flex-col gap-3 rounded-2xl border border-n-blue-7 bg-n-blue-2 p-5"
    >
      <h3 class="mb-0 text-base font-semibold text-n-slate-12">
        {{ $t('CRM_CAIXAS.CONFIRA.MUDA') }}
      </h3>
      <ul v-if="lista.length" class="m-0 flex list-none flex-col gap-2 p-0">
        <li
          v-for="frase in lista"
          :key="frase"
          class="flex items-start gap-2 text-[0.9375rem] text-n-slate-12"
        >
          <span
            class="i-lucide-arrow-right mt-1 size-4 shrink-0 text-n-blue-11"
            aria-hidden="true"
          />
          {{ frase }}
        </li>
      </ul>
      <p v-else class="mb-0 text-[0.9375rem] text-n-slate-11">
        {{ $t('CRM_CAIXAS.CONFIRA.NADA_MUDOU') }}
      </p>
    </section>
  </div>
</template>
