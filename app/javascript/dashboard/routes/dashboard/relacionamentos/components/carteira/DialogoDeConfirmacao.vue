<script setup>
import { useTemplateRef } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TituloDoDialogo from '../comum/TituloDoDialogo.vue';

// #2897 — a pergunta antes de um passo sem volta na gaveta do seguro: apagar o
// PDF, trocar o PDF que já está guardado e sair do Corrigir sem salvar. Os
// textos vêm de quem usa. Tocar fora não fecha (só Esc e o botão de voltar).
// Quem usa age ao ouvir `confirmar` e fecha o diálogo (`fechar`) quando deu
// certo; se não deu, passa a frase em `alerta` e o diálogo continua aberto, com
// ela dentro.
// #3057 — `tipo` "edit" deixa o botão de confirmar azul (o passo não destrói
// nada, como enviar a proposta); sem ele, vermelho. O que mais a pergunta
// precisa mostrar (um link, por exemplo) vai no slot, abaixo do aviso.
// #3057 — quando as duas saídas são ações (como "Salvar ajustes" e "Sair sem
// salvar"), quem usa põe os botões no slot `rodape`: aí Esc e o fechar só
// fecham a pergunta, sem fazer nenhuma das duas.
// #3057 (revisão) — o rodapé padrão também é daqui, com botões grandes
// (size lg, 44 px de alvo de toque) no lugar dos de 40 px do Dialog.

defineProps({
  // O `data-carteira` do diálogo.
  marca: { type: String, required: true },
  titulo: { type: String, required: true },
  aviso: { type: String, required: true },
  confirmar: { type: String, required: true },
  voltar: { type: String, required: true },
  ocupado: { type: Boolean, default: false },
  alerta: { type: String, default: '' },
  tipo: { type: String, default: 'alert' },
  // O aviso no tamanho do texto principal (comum/TituloDoDialogo.vue).
  avisoForte: { type: Boolean, default: false },
});
const emit = defineEmits(['confirmar', 'fechou']);

const dialogo = useTemplateRef('dialogo');

defineExpose({
  abrir: () => dialogo.value?.open(),
  fechar: () => dialogo.value?.close(),
});
</script>

<template>
  <Dialog
    ref="dialogo"
    :type="tipo"
    width="sm"
    :confirm-button-label="confirmar"
    :cancel-button-label="voltar"
    :is-loading="ocupado"
    :close-on-outside-click="false"
    @confirm="emit('confirmar')"
    @close="emit('fechou')"
  >
    <div :data-carteira="marca" class="flex flex-col gap-3">
      <TituloDoDialogo
        :titulo="titulo"
        :aviso="aviso"
        :aviso-forte="avisoForte"
      />
      <slot />
      <p
        v-if="alerta"
        role="alert"
        data-carteira="alerta-do-dialogo"
        class="m-0 text-base font-medium text-n-ruby-11"
      >
        {{ alerta }}
      </p>
    </div>
    <template #footer>
      <slot name="rodape">
        <div class="flex items-center w-full gap-3">
          <Button
            slate
            faded
            size="lg"
            type="button"
            class="w-full"
            data-carteira="dialogo-voltar"
            :label="voltar"
            @click="dialogo?.close()"
          />
          <Button
            :color="tipo === 'edit' ? 'blue' : 'ruby'"
            size="lg"
            type="submit"
            class="w-full"
            data-carteira="dialogo-confirmar"
            :label="confirmar"
            :is-loading="ocupado"
            :disabled="ocupado"
          />
        </div>
      </slot>
    </template>
  </Dialog>
</template>
