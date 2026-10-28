<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import MaisDaFuncao from './MaisDaFuncao.vue';
import { cuidadosDaFuncao, fraseDoCartao } from '../fraseDoCartao';

// Uma função da conta na lista (#2308, especificação 5.A): o que ela pode em uma frase, o selo do que pede
// cuidado, quem usa e as ações. Travada (roleLockReason) fica tracejada, só com o motivo.
const props = defineProps({
  funcao: { type: Object, required: true },
  pessoas: { type: Array, default: () => [] },
  tom: { type: String, required: true },
  travada: { type: Boolean, default: false },
  podeDuplicar: { type: Boolean, default: true },
  podeEscolherPessoas: { type: Boolean, default: false },
});

const emit = defineEmits(['alterar', 'duplicar', 'apagar', 'escolherPessoas']);

const { t, locale } = useI18n();

const MAX_ROSTOS = 4;

const frase = computed(() => fraseDoCartao(props.funcao.permissions || []));
const restoDaFrase = computed(() =>
  frase.value.resto.map(chave => t(`FUNCOES_EQUIPE.FRASE.${chave}`)).join(' ')
);

const selo = computed(() => {
  const cuidados = cuidadosDaFuncao(props.funcao.permissions || []);
  if (!cuidados.length) return '';
  const lista = new Intl.ListFormat(locale.value.replaceAll('_', '-'), {
    type: 'conjunction',
  });
  const coisas = lista.format(
    cuidados.map(chave => t(`FUNCOES_EQUIPE.CUIDADO.${chave}`))
  );
  return t('FUNCOES_EQUIPE.CARTAO.SELO', { coisas });
});

const outrasPessoas = computed(() =>
  Math.max(props.pessoas.length - MAX_ROSTOS, 0)
);
</script>

<template>
  <li
    data-cartao-funcao
    class="flex flex-col gap-4 p-4 border rounded-2xl bg-n-solid-1 sm:flex-row sm:items-center sm:p-5"
    :class="
      travada ? 'border-dashed border-n-slate-8' : 'shadow-sm border-n-weak'
    "
  >
    <span
      class="hidden sm:grid place-items-center size-11 shrink-0 rounded-xl"
      :class="travada ? 'bg-n-alpha-2 text-n-slate-11' : tom"
    >
      <span class="i-lucide-user-round-cog size-5" aria-hidden="true" />
    </span>

    <div class="flex flex-col flex-1 min-w-0 gap-1.5">
      <div
        class="flex flex-col sm:flex-row sm:flex-wrap sm:items-baseline sm:gap-x-3"
      >
        <h2 class="m-0 text-lg font-semibold break-words text-n-slate-12">
          {{ funcao.name }}
        </h2>
        <span v-if="funcao.description" class="text-sm text-n-slate-11">
          {{ funcao.description }}
        </span>
      </div>
      <p
        data-frase
        class="m-0 text-[0.9375rem] leading-relaxed text-n-slate-11"
      >
        <span class="font-medium text-n-slate-12">
          {{ $t(`FUNCOES_EQUIPE.FRASE.${frase.destaque}`) }}
        </span>
        {{ restoDaFrase }}
      </p>
      <span
        v-if="selo"
        data-selo-cuidado
        class="inline-flex items-start self-start gap-1.5 px-2.5 py-1 mt-0.5 text-sm rounded-lg bg-n-alpha-2 text-n-slate-12"
      >
        <span
          class="i-lucide-triangle-alert size-4 mt-0.5 shrink-0 text-n-amber-11"
          aria-hidden="true"
        />
        {{ selo }}
      </span>

      <div
        v-if="pessoas.length"
        data-pessoas
        class="flex items-center gap-2.5 min-h-11"
      >
        <span class="flex -space-x-1.5" aria-hidden="true">
          <Avatar
            v-for="pessoa in pessoas.slice(0, MAX_ROSTOS)"
            :key="pessoa.id"
            :name="pessoa.name"
            :src="pessoa.thumbnail"
            :size="32"
            rounded-full
            class="ring-2 ring-n-solid-1"
          />
          <span
            v-if="outrasPessoas"
            class="grid text-xs font-medium rounded-full place-items-center size-8 ring-2 ring-n-solid-1 bg-n-alpha-2 text-n-slate-12"
          >
            {{
              $t('FUNCOES_EQUIPE.CARTAO.OUTRAS_PESSOAS', { n: outrasPessoas })
            }}
          </span>
        </span>
        <span class="text-sm font-medium text-n-slate-12">
          {{
            $t(
              'FUNCOES_EQUIPE.CARTAO.PESSOAS',
              { n: pessoas.length },
              pessoas.length
            )
          }}
        </span>
      </div>
      <p
        v-else
        data-ninguem
        class="flex flex-wrap items-center m-0 text-sm gap-x-2 min-h-11 text-n-slate-11"
      >
        {{ $t('FUNCOES_EQUIPE.CARTAO.NINGUEM') }}
        <template v-if="podeEscolherPessoas">
          <span aria-hidden="true">
            {{ $t('FUNCOES_EQUIPE.CONTAGEM.SEPARADOR') }}
          </span>
          <button
            type="button"
            data-escolher-pessoas
            class="px-1 -mx-1 font-semibold underline rounded min-h-11 underline-offset-4 text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            :aria-label="
              $t('FUNCOES_EQUIPE.CARTAO.ESCOLHER_PESSOAS_ROTULO', {
                nome: funcao.name,
              })
            "
            @click="emit('escolherPessoas')"
          >
            {{ $t('FUNCOES_EQUIPE.CARTAO.ESCOLHER_PESSOAS') }}
          </button>
        </template>
      </p>
    </div>

    <p
      v-if="travada"
      data-travada
      class="inline-flex items-center gap-2 m-0 text-sm font-medium shrink-0 text-n-slate-12"
    >
      <span class="i-lucide-lock size-4 shrink-0" aria-hidden="true" />
      {{ $t('FUNCOES_EQUIPE.CARTAO.TRAVADO') }}
    </p>
    <div v-else class="grid grid-cols-2 gap-2 sm:flex shrink-0">
      <Button
        data-alterar
        :label="$t('FUNCOES_EQUIPE.CARTAO.ALTERAR')"
        :aria-label="
          $t('FUNCOES_EQUIPE.CARTAO.ALTERAR_ROTULO', { nome: funcao.name })
        "
        icon="i-lucide-pencil"
        slate
        faded
        class="min-h-11"
        @click="emit('alterar')"
      />
      <MaisDaFuncao
        :nome="funcao.name"
        :pode-duplicar="podeDuplicar"
        @duplicar="emit('duplicar')"
        @apagar="emit('apagar')"
      />
    </div>
  </li>
</template>
