<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import FichaDeExemplo from '../../trazer/FichaDeExemplo.vue';
import { useTextosDoSeguro } from '../../../carteira/useTextosDoSeguro';
import { formatarTelefone } from '../../../lista/telefone';

// #2897 — "Como vão ficar": as três fichas de exemplo do bloco A, agora com os
// seguros de cada pessoa embaixo. Quem está sem telefone aparece dizendo isso.
const props = defineProps({
  exemplos: { type: Array, required: true },
});

const { t } = useI18n();
const ca = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.TRAZER.CONFERIR.${chave}`, valores);
const textos = useTextosDoSeguro();

const fichas = computed(() =>
  props.exemplos.map(exemplo => ({
    pessoa: { ...exemplo, telefone: formatarTelefone(exemplo.telefone) },
    semTelefone: !exemplo.telefone,
    seguros: exemplo.seguros.map(seguro =>
      ca('SEGURO_DO_EXEMPLO', {
        tipo: textos.tipo(seguro),
        seguradora: seguro.seguradora,
        data: textos.dataInteira(seguro.termina),
      })
    ),
  }))
);
</script>

<template>
  <section data-carteira="exemplos" class="flex flex-col gap-4">
    <h2 class="m-0 text-2xl font-semibold tracking-tight text-n-slate-12">
      {{ ca('EXEMPLOS') }}
    </h2>
    <div class="grid gap-3 md:grid-cols-3">
      <FichaDeExemplo
        v-for="ficha in fichas"
        :key="ficha.pessoa.nome"
        :pessoa="ficha.pessoa"
      >
        <p
          v-if="ficha.semTelefone"
          data-carteira="exemplo-sem-telefone"
          class="flex items-center gap-2 m-0 text-sm text-n-amber-11"
        >
          <span class="i-lucide-phone-off size-4 shrink-0" aria-hidden="true" />
          {{ ca('SEM_TELEFONE') }}
        </p>
        <ul
          :aria-label="ca('SEGUROS_DE', { nome: ficha.pessoa.nome })"
          class="flex flex-col gap-2 p-0 pt-3 m-0 text-sm list-none border-t border-n-weak text-n-slate-12"
        >
          <li
            v-for="seguro in ficha.seguros"
            :key="seguro"
            data-carteira="seguro-do-exemplo"
            class="flex items-start gap-2 break-words"
          >
            <span
              class="i-lucide-shield-check size-4 shrink-0 mt-0.5 text-n-teal-11"
              aria-hidden="true"
            />
            {{ seguro }}
          </li>
        </ul>
      </FichaDeExemplo>
    </div>
  </section>
</template>
