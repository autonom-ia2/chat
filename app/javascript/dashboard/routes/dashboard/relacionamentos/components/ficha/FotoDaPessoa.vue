<script setup>
import { computed, onBeforeUnmount, ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';

// #3075 — a foto da pessoa, no topo da gaveta "Alterar informações" (a ficha
// antiga trocava e tirava a foto no próprio retrato). Nada vai ao servidor
// aqui: a escolha fica no formulário (`mudar`) e é gravada no "Salvar".
//  - "Pôr foto" / "Trocar foto" abre a escolha de arquivo do aparelho. Aceita o
//    que o servidor aceita (JPG, PNG, GIF e WEBP, até 15 MB, Avatarable); o que
//    não serve diz o que fazer, e a foto de antes continua;
//  - "Remover foto" deixa as iniciais no lugar e diz que a foto sai ao salvar;
//  - "Voltar como estava" desfaz a troca ou o remover, antes de salvar.
// A prévia da foto escolhida é solta da memória quando sai da tela (remover,
// voltar como estava, outra foto ou a gaveta fechada).
const props = defineProps({
  nome: { type: String, default: '' },
  // A foto gravada hoje (thumbnail).
  atual: { type: String, default: '' },
  // A troca pedida: { arquivo, previa }, { tirar: true } ou null.
  foto: { type: Object, default: null },
});
const emit = defineEmits(['mudar']);

const TIPOS_ACEITOS = ['image/jpeg', 'image/png', 'image/gif', 'image/webp'];
const MAIOR_FOTO_EM_BYTES = 15 * 1024 * 1024;

const { t } = useI18n();
const fa = chave => t(`RELACIONAMENTOS_FICHA.GAVETA.FOTO.${chave}`);
const arquivo = useTemplateRef('arquivo');
const erro = ref('');
let previaAberta = '';

const largarPrevia = () => {
  if (previaAberta) URL.revokeObjectURL(previaAberta);
  previaAberta = '';
};
onBeforeUnmount(largarPrevia);

const naTela = computed(() => {
  if (props.foto?.tirar) return '';
  return props.foto?.previa || props.atual;
});
const temFoto = computed(() => Boolean(naTela.value));
const mudou = computed(() => Boolean(props.foto));
const aviso = computed(() => {
  if (props.foto?.tirar) return fa('VAI_SAIR');
  if (props.foto?.arquivo) return fa('VAI_ENTRAR');
  return '';
});

const escolher = () => {
  erro.value = '';
  arquivo.value?.click();
};

const aoEscolher = evento => {
  const escolhido = evento.target.files?.[0];
  // O mesmo arquivo pode ser escolhido de novo depois de "Voltar como estava".
  evento.target.value = '';
  if (!escolhido) return;
  if (!TIPOS_ACEITOS.includes(escolhido.type)) {
    erro.value = fa('ERRO_TIPO');
    return;
  }
  if (escolhido.size > MAIOR_FOTO_EM_BYTES) {
    erro.value = fa('ERRO_TAMANHO');
    return;
  }
  largarPrevia();
  previaAberta = URL.createObjectURL(escolhido);
  emit('mudar', { arquivo: escolhido, previa: previaAberta });
};

const tirar = () => {
  erro.value = '';
  largarPrevia();
  emit('mudar', { tirar: true });
};

const manter = () => {
  erro.value = '';
  largarPrevia();
  emit('mudar', null);
};
</script>

<template>
  <div
    data-relacionamentos="foto-da-pessoa"
    class="flex items-start min-w-0 gap-4"
  >
    <Avatar
      :name="nome"
      :src="naTela"
      :size="72"
      rounded-full
      class="shrink-0"
    />
    <div class="flex flex-col min-w-0 gap-2">
      <div class="flex flex-wrap gap-2">
        <Button
          data-relacionamentos="escolher-foto"
          slate
          faded
          type="button"
          icon="i-lucide-image-up"
          class="!h-11"
          :label="fa(temFoto ? 'TROCAR' : 'POR')"
          @click="escolher"
        />
        <Button
          v-if="temFoto"
          data-relacionamentos="tirar-foto"
          slate
          ghost
          type="button"
          icon="i-lucide-image-off"
          class="!h-11"
          :label="fa('TIRAR')"
          @click="tirar"
        />
        <Button
          v-if="mudou"
          data-relacionamentos="manter-foto"
          slate
          ghost
          type="button"
          class="!h-11"
          :label="fa('MANTER')"
          @click="manter"
        />
      </div>
      <p
        v-if="aviso"
        data-relacionamentos="aviso-da-foto"
        class="m-0 text-sm text-n-slate-11"
      >
        {{ aviso }}
      </p>
      <p
        v-if="erro"
        role="alert"
        data-relacionamentos="erro-da-foto"
        class="m-0 text-sm text-n-ruby-11"
      >
        {{ erro }}
      </p>
    </div>
    <input
      ref="arquivo"
      type="file"
      class="hidden"
      :accept="TIPOS_ACEITOS.join(',')"
      :aria-label="fa(temFoto ? 'TROCAR' : 'POR')"
      @change="aoEscolher"
    />
  </div>
</template>
