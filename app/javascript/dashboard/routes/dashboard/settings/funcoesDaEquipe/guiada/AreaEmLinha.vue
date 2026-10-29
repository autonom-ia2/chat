<script setup>
import { computed, ref } from 'vue';
import {
  LEVELS,
  getLevel,
  levelOptions,
  setLevel,
  toggleExtra,
  visibleExtras,
} from '../../customRoles/permissionMatrix';
import { DONO_DAS_CHAVES, travaDoNivel } from '../areasDaFuncao';
import { TEXTO_DA_TRAVA, motivoDaTrava } from '../motivoDaTrava';
import { devolverFoco } from './focoQueFica';
import { useMemoria } from './memoriaDaConversa';
import { useTextos } from './useTextos';
import EscolhaDeNivel from './EscolhaDeNivel.vue';
import InterruptorDaLinha from './InterruptorDaLinha.vue';

// Uma área com os níveis à mão (#2308, especificação 5.B2): na recolhida de Ajustes e no "Mais" das perguntas. Nível
// que quem monta não pode dar fica com cadeado e o motivo; a área inteira travada mostra só o motivo. Mudou desde o
// começo: faixa de 4 px, "você mudou" e o que era antes. Voltar a um nível por onde passou devolve os ajustes de lá
// (memoriaDaConversa); um ajuste que some ao desligar devolve o foco ao nível escolhido.
const props = defineProps({
  module: { type: Object, required: true },
  permissions: { type: Array, required: true },
  giver: { type: Object, required: true },
  inicial: { type: Array, default: null },
});

const emit = defineEmits(['update:permissions']);
const { t, rotuloDoNivel, antesDoNivel, nomeDaArea } = useTextos();
const memoria = useMemoria();
const raiz = ref(null);

const nivel = computed(() => getLevel(props.module, props.permissions));
const nivelAntes = computed(
  () => props.inicial && getLevel(props.module, props.inicial)
);
const mudou = computed(
  () => Boolean(props.inicial) && nivelAntes.value !== nivel.value
);

const textoDaTrava = motivo =>
  motivo ? t(`FUNCOES_EQUIPE.TRAVA.${TEXTO_DA_TRAVA[motivo]}`) : '';

const opcoes = computed(() =>
  levelOptions(props.module, nivel.value).map(valor => ({
    valor,
    titulo: rotuloDoNivel(props.module, valor),
    trava:
      valor === nivel.value
        ? ''
        : textoDaTrava(travaDoNivel(props.giver, props.module, valor)),
  }))
);
const acima = computed(() =>
  opcoes.value.filter(opcao => opcao.valor !== LEVELS.NONE)
);
const travada = computed(
  () => nivel.value === LEVELS.NONE && acima.value.every(opcao => opcao.trava)
);

// O que pede cuidado mora no Cuidado, não aqui.
const extras = computed(() =>
  visibleExtras(props.module, props.permissions).filter(
    chave => !DONO_DAS_CHAVES.CUIDADO.includes(chave)
  )
);
const travaDoExtra = chave =>
  props.permissions.includes(chave)
    ? ''
    : textoDaTrava(motivoDaTrava(props.giver, chave));

const escolher = valor =>
  emit(
    'update:permissions',
    memoria.trocarNivel(props.module, {
      permissions: props.permissions,
      nivelar: chaves => setLevel(props.module, valor, chaves),
    })
  );
const alternar = chave => {
  emit(
    'update:permissions',
    toggleExtra(props.module, chave, props.permissions)
  );
  devolverFoco(raiz.value, ['[role="radio"][aria-checked="true"]']);
};
</script>

<template>
  <div
    ref="raiz"
    :data-area="module.key"
    class="flex flex-col gap-3 py-3 pe-4"
    :class="mudou ? 'border-s-4 border-n-blue-9 ps-3' : 'ps-4'"
  >
    <div class="flex items-center gap-3">
      <span
        class="grid place-items-center size-10 shrink-0 rounded-xl bg-n-alpha-2 text-n-slate-11"
      >
        <span class="size-5" :class="module.icon" aria-hidden="true" />
      </span>
      <div class="flex flex-col min-w-0 gap-0.5">
        <p
          class="flex flex-wrap items-center gap-2 m-0 font-semibold text-n-slate-12"
        >
          {{ nomeDaArea(module.key) }}
          <span
            v-if="mudou"
            class="px-2 py-0.5 text-xs font-medium rounded-md bg-n-blue-3 text-n-blue-11"
          >
            {{ $t('FUNCOES_EQUIPE.GUIADA.VOCE_MUDOU') }}
          </span>
        </p>
        <p v-if="mudou" class="m-0 text-sm text-n-slate-11">
          {{
            $t('FUNCOES_EQUIPE.GUIADA.ANTES_DE', {
              antes: antesDoNivel(module, nivelAntes, inicial),
            })
          }}
        </p>
        <p
          v-if="travada"
          data-area-travada
          class="flex items-center gap-1.5 m-0 text-sm text-n-slate-11"
        >
          <span class="i-lucide-lock size-4 shrink-0" aria-hidden="true" />
          {{ acima[0].trava }}
        </p>
      </div>
    </div>
    <EscolhaDeNivel
      v-if="!travada"
      :model-value="nivel"
      :opcoes="opcoes"
      :rotulo="nomeDaArea(module.key)"
      compacto
      @update:model-value="escolher"
    />
    <InterruptorDaLinha
      v-for="chave in extras"
      :key="chave"
      :titulo="$t(`FUNCOES_EQUIPE.EXTRAS.${chave}`)"
      :ligado="permissions.includes(chave)"
      :trava="travaDoExtra(chave)"
      class="rounded-xl bg-n-solid-1"
      @alternar="alternar(chave)"
    />
  </div>
</template>
