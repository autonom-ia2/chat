<script setup>
import { computed, ref, useId } from 'vue';
import { useSemFuncao } from '../useSemFuncao';

// As duas funções que vêm com a conta (#2308): Administrador e Sem função. Não mudam. "Ver tudo o que pode" abre o
// contrato de Sem função (semFuncaoCapacidades.json, gerado das policies), com as flags reais da conta.
// Sem a lista de pessoas (falhou), as contagens somem: nunca "nenhuma pessoa" por engano.
defineProps({
  administradores: { type: Number, default: 0 },
  semFuncao: { type: Number, default: 0 },
  semPessoas: { type: Boolean, default: false },
});

const { capacidades, textoDa, notas } = useSemFuncao();
const id = useId();
const aberto = ref(false);

const grupos = computed(() => [
  {
    chave: 'PODE',
    icone: 'i-lucide-check text-n-teal-11',
    itens: capacidades.value.filter(item => item.pode),
  },
  {
    chave: 'NAO_PODE',
    icone: 'i-lucide-x text-n-slate-11',
    itens: capacidades.value.filter(item => !item.pode),
  },
]);
</script>

<template>
  <section data-fixas class="flex flex-col gap-3">
    <h2 class="m-0 text-lg font-semibold text-n-slate-12">
      {{ $t('FUNCOES_EQUIPE.FIXAS.TITULO') }}
    </h2>
    <div class="grid gap-3 sm:grid-cols-2">
      <div
        data-fixa-admin
        class="flex gap-4 p-5 border rounded-2xl border-n-weak bg-n-solid-1"
      >
        <span
          class="grid place-items-center size-11 shrink-0 rounded-xl bg-n-blue-3 text-n-blue-11"
        >
          <span class="i-lucide-shield-check size-5" aria-hidden="true" />
        </span>
        <div class="flex flex-col gap-1">
          <h3 class="m-0 text-base font-semibold text-n-slate-12">
            {{ $t('FUNCOES_EQUIPE.FIXAS.ADMIN.NOME') }}
          </h3>
          <p class="m-0 text-[0.9375rem] text-n-slate-11">
            {{ $t('FUNCOES_EQUIPE.FIXAS.ADMIN.TEXTO') }}
          </p>
          <p v-if="!semPessoas" class="m-0 text-sm text-n-slate-11">
            {{
              $t(
                'FUNCOES_EQUIPE.FIXAS.PESSOAS',
                { n: administradores },
                administradores
              )
            }}
          </p>
        </div>
      </div>
      <div
        data-fixa-sem-funcao
        class="flex gap-4 p-5 border rounded-2xl border-n-weak bg-n-solid-1"
      >
        <span
          class="grid place-items-center size-11 shrink-0 rounded-xl bg-n-alpha-2 text-n-slate-11"
        >
          <span class="i-lucide-user size-5" aria-hidden="true" />
        </span>
        <div class="flex flex-col gap-1">
          <h3 class="m-0 text-base font-semibold text-n-slate-12">
            {{ $t('FUNCOES_EQUIPE.FIXAS.SEM_FUNCAO.NOME') }}
          </h3>
          <p class="m-0 text-[0.9375rem] text-n-slate-11">
            {{ $t('FUNCOES_EQUIPE.FIXAS.SEM_FUNCAO.TEXTO') }}
          </p>
          <p class="m-0 text-[0.9375rem] font-semibold text-n-slate-12">
            {{ $t('FUNCOES_EQUIPE.FIXAS.SEM_FUNCAO.CHAMADA') }}
          </p>
          <p
            class="flex flex-wrap items-center m-0 text-sm gap-x-2 text-n-slate-11"
          >
            <template v-if="!semPessoas">
              {{
                $t('FUNCOES_EQUIPE.FIXAS.PESSOAS', { n: semFuncao }, semFuncao)
              }}
              <span aria-hidden="true">
                {{ $t('FUNCOES_EQUIPE.CONTAGEM.SEPARADOR') }}
              </span>
            </template>
            <button
              type="button"
              data-ver-tudo-sem-funcao
              :aria-expanded="aberto"
              :aria-controls="`${id}-tudo`"
              class="px-1 -mx-1 font-semibold underline rounded min-h-11 underline-offset-4 text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
              @click="aberto = !aberto"
            >
              {{ $t('FUNCOES_EQUIPE.FIXAS.SEM_FUNCAO.VER_TUDO') }}
            </button>
          </p>
          <div
            v-show="aberto"
            :id="`${id}-tudo`"
            data-tudo-sem-funcao
            class="flex flex-col gap-3 pt-2"
          >
            <div
              v-for="grupo in grupos"
              :key="grupo.chave"
              :data-grupo="grupo.chave"
              class="flex flex-col gap-1.5"
            >
              <p class="m-0 text-sm font-semibold text-n-slate-12">
                {{ $t(`FUNCOES_EQUIPE.PREVIA.${grupo.chave}`) }}
              </p>
              <ul class="flex flex-col gap-1.5 p-0 m-0 list-none">
                <li
                  v-for="item in grupo.itens"
                  :key="item.chave"
                  :data-item="item.chave"
                  class="flex items-start gap-2 text-sm text-n-slate-12"
                >
                  <span
                    class="size-4 mt-0.5 shrink-0"
                    :class="grupo.icone"
                    aria-hidden="true"
                  />
                  {{ textoDa(item) }}
                </li>
              </ul>
            </div>
            <p
              v-for="nota in notas"
              :key="nota"
              class="flex items-start gap-2 m-0 text-sm text-n-slate-11"
            >
              <span
                class="i-lucide-info size-4 mt-0.5 shrink-0"
                aria-hidden="true"
              />
              {{ nota }}
            </p>
          </div>
        </div>
      </div>
    </div>
  </section>
</template>
