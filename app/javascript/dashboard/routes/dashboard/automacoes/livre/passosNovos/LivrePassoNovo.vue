<script setup>
import LivreAprovacao from './LivreAprovacao.vue';
import LivreRepetir from './LivreRepetir.vue';
import LivreBloco from './LivreBloco.vue';
import LivreConsulta from './LivreConsulta.vue';
import LivreReuniao from './LivreReuniao.vue';
import LivrePesquisa from './LivrePesquisa.vue';
import LivrePassoNovoPrevia from './LivrePassoNovoPrevia.vue';
import { P, temMotor } from './passosNovos';

// Protótipo #2931–#2936 — a peça do "Alterar" para os passos novos: o
// formulário de cada um, já pronto, e a prévia do ensaio e do histórico. O
// passo inteiro entra e sai por `modelValue`, como no "para cada item" (G24).
defineProps({
  modelValue: { type: Object, required: true },
  catalogo: { type: Object, required: true },
  opcoes: { type: Object, required: true },
  atributosDo: { type: Function, required: true },
  etapas: { type: Array, default: () => [] },
});

const emit = defineEmits(['update:modelValue']);
const mudar = novo => emit('update:modelValue', novo);
</script>

<template>
  <div class="flex flex-col gap-6" data-peca="passo_novo">
    <p
      v-if="!temMotor(modelValue)"
      data-em-teste
      role="note"
      class="px-4 py-3 mb-0 text-sm rounded-xl bg-n-blue-2 text-n-blue-12"
    >
      {{ $t(`${P}.EM_TESTE`) }}
    </p>

    <LivreAprovacao
      v-if="modelValue.tipo === 'pedir_aprovacao'"
      :model-value="modelValue"
      :catalogo="catalogo"
      :opcoes="opcoes"
      :atributos-do="atributosDo"
      @update:model-value="mudar"
    />
    <LivreRepetir
      v-else-if="modelValue.tipo === 'repetir_lista'"
      :model-value="modelValue"
      :opcoes="opcoes"
      :etapas="etapas"
      @update:model-value="mudar"
    />
    <LivreBloco
      v-else-if="modelValue.tipo === 'usar_bloco'"
      :model-value="modelValue"
      :catalogo="catalogo"
      @update:model-value="mudar"
    />
    <LivreConsulta
      v-else-if="modelValue.tipo === 'consultar'"
      :model-value="modelValue"
      :catalogo="catalogo"
      :atributos-do="atributosDo"
      @update:model-value="mudar"
    />
    <LivreReuniao
      v-else-if="modelValue.tipo === 'marcar_reuniao'"
      :model-value="modelValue"
      :catalogo="catalogo"
      :opcoes="opcoes"
      :atributos-do="atributosDo"
      @update:model-value="mudar"
    />
    <LivrePesquisa
      v-else-if="modelValue.tipo === 'pesquisa_nota'"
      :model-value="modelValue"
      :catalogo="catalogo"
      :atributos-do="atributosDo"
      @update:model-value="mudar"
    />

    <LivrePassoNovoPrevia :passo="modelValue" />
  </div>
</template>
