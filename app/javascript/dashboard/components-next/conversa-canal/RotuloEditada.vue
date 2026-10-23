<script setup>
// "Editada" antes da hora (#1702), como no WhatsApp. No app quem recebe não vê o texto
// antigo; aqui a equipe vê: clicar abre as versões anteriores, da mais nova para a mais
// antiga, cada uma com a hora em que foi trocada (no fuso da conta).
import { computed, nextTick, ref, useId, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { onClickOutside } from '@vueuse/core';
import { versoesAnteriores } from './marcasDaMensagem';
import { horaDaMensagem, idiomaDoPainel } from './dataDaConversa';
import { useFuso } from './pele';

const props = defineProps({
  atributos: { type: Object, required: true },
  // Rótulo no início da linha (mensagem recebida no Instagram, #2113): as versões abrem
  // alinhadas pelo início, para dentro da conversa, e não cortam na borda.
  abrirNoInicio: { type: Boolean, default: false },
});

const { t, locale } = useI18n();
const fuso = useFuso();
const aberto = ref(false);
const raiz = useTemplateRef('raiz');
const botao = useTemplateRef('botao');
const painel = useTemplateRef('painel');
const idPainel = `versoes-${useId()}`;

const versoes = computed(() =>
  versoesAnteriores(props.atributos)
    .map((versao, posicao) => {
      const quando = Math.floor(Date.parse(versao.editedAt) / 1000);
      return {
        chave: `${posicao}-${versao.editedAt}`,
        texto: versao.content,
        hora: Number.isFinite(quando)
          ? horaDaMensagem(quando, fuso.value, idiomaDoPainel(locale.value))
          : '',
      };
    })
    .reverse()
);

const fechar = () => {
  aberto.value = false;
};
onClickOutside(raiz, fechar);

// Ao abrir, o foco vai para o painel (o leitor de tela lê as versões); o Esc devolve
// o foco ao "Editada".
const alternar = async () => {
  aberto.value = !aberto.value;
  if (!aberto.value) return;
  await nextTick();
  painel.value?.focus();
};
const fecharPeloTeclado = () => {
  if (!aberto.value) return;
  fechar();
  botao.value?.focus();
};
</script>

<template>
  <span
    ref="raiz"
    class="relative inline-flex"
    @keydown.esc.stop="fecharPeloTeclado"
  >
    <button
      ref="botao"
      type="button"
      class="inline rounded-sm pointer-events-auto hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-[#53BDEB] skip-context-menu"
      :aria-expanded="aberto"
      :aria-controls="idPainel"
      data-rotulo-editada
      @click.stop="alternar"
    >
      {{ t('CONVERSA_CANAL.EDITADA.ROTULO') }}
    </button>
    <div
      v-if="aberto"
      :id="idPainel"
      ref="painel"
      tabindex="-1"
      role="dialog"
      :aria-label="t('CONVERSA_CANAL.EDITADA.TITULO')"
      :class="
        abrirNoInicio ? 'ltr:left-0 rtl:right-0' : 'ltr:right-0 rtl:left-0'
      "
      class="absolute bottom-full z-10 mb-1 w-64 max-w-[80vw] p-3 rounded-[10px] text-start whitespace-normal bg-white dark:bg-[#242626] text-[#0A0A0A] dark:text-[#FAFAFA] shadow-[0_2px_8px_rgba(11,20,26,0.26)] pointer-events-auto"
      data-versoes-anteriores
    >
      <p
        class="mb-2 text-[12px] font-medium text-[#666666] dark:text-[#A7A8A8]"
      >
        {{ t('CONVERSA_CANAL.EDITADA.TITULO') }}
      </p>
      <p v-if="!versoes.length" class="text-[13px]">
        {{ t('CONVERSA_CANAL.EDITADA.SEM_VERSOES') }}
      </p>
      <ol v-else class="flex flex-col gap-2 m-0 list-none">
        <li
          v-for="versao in versoes"
          :key="versao.chave"
          class="text-[13px] leading-[18px]"
          data-versao-anterior
        >
          <span class="block break-words whitespace-pre-wrap">
            {{ versao.texto }}
          </span>
          <span
            v-if="versao.hora"
            class="block text-[11px] text-[#666666] dark:text-[#A7A8A8]"
          >
            {{ t('CONVERSA_CANAL.EDITADA.TROCADA_AS', { hora: versao.hora }) }}
          </span>
        </li>
      </ol>
    </div>
  </span>
</template>
