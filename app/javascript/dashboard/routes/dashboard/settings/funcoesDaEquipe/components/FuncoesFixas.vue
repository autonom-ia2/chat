<script setup>
// As duas funções que vêm com a conta (#2308): Administrador e Sem função. Não mudam; o texto de Sem função
// segue a especificação 5.A até o contrato gerado do servidor chegar (PR 2).
defineProps({
  administradores: { type: Number, default: 0 },
  semFuncao: { type: Number, default: 0 },
});
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
          <p class="m-0 text-sm text-n-slate-11">
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
          <p class="m-0 text-sm text-n-slate-11">
            {{
              $t('FUNCOES_EQUIPE.FIXAS.PESSOAS', { n: semFuncao }, semFuncao)
            }}
          </p>
        </div>
      </div>
    </div>
  </section>
</template>
