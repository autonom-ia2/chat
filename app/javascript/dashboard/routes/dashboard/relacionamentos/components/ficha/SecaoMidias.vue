<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { quandoRelativo } from '../../ficha/formatos';
import { useIdioma } from '../../ficha/idioma';
import { SEPARADOR } from '../comum/ponto';
import CartaoDaSecao from './CartaoDaSecao.vue';
import FalhaDaParte from './FalhaDaParte.vue';

// #3078 — as mídias da empresa (a aba Mídias da ficha antiga): as mais novas
// fotos, documentos, áudios e vídeos trocados nas conversas das pessoas dela,
// com de quem e quando. "Ver todas as mídias" (`verTodas`) abre a tela de
// mídias da empresa, que procura, filtra, mostra e baixa. `falhou`: a leitura
// não veio. Só existe na conta com as mídias de Relacionamentos ligadas (a
// página decide). Quem não pode abrir a tela de mídias (a rota pede
// administrador ou agente) não tem "Ver todas" (`podeVerTodas` falso).
defineProps({
  // { itens: [{ id, nome, tipo, quando, pessoa }], total }.
  midias: { type: Object, required: true },
  agora: { type: Number, default: () => Date.now() },
  falhou: { type: Boolean, default: false },
  podeVerTodas: { type: Boolean, default: true },
});
const emit = defineEmits(['tentar', 'verTodas']);

const ICONES = {
  imagem: 'i-lucide-image',
  documento: 'i-lucide-file-text',
  audio: 'i-lucide-mic',
  video: 'i-lucide-video',
};

const { t } = useI18n();
const idioma = useIdioma();
const rm = (chave, valores) =>
  t(`RELACIONAMENTOS_FICHA.EMPRESA.MIDIAS.${chave}`, valores);
</script>

<template>
  <CartaoDaSecao :titulo="rm('TITULO')" data-relacionamentos="midias">
    <template v-if="podeVerTodas && !falhou && midias.total" #acao>
      <Button
        data-relacionamentos="ver-todas-as-midias"
        slate
        faded
        class="!h-11 whitespace-nowrap"
        :label="rm('VER_TODAS', { total: midias.total })"
        @click="emit('verTodas')"
      />
    </template>
    <FalhaDaParte v-if="falhou" @tentar="emit('tentar')" />
    <p v-else-if="!midias.itens.length" class="m-0 text-base text-n-slate-11">
      {{ rm('VAZIO') }}
    </p>
    <ul v-else class="flex flex-col gap-3 p-0 m-0 list-none">
      <li
        v-for="midia in midias.itens"
        :key="midia.id"
        data-relacionamentos="midia"
        class="flex items-center gap-3"
      >
        <span
          class="flex items-center justify-center size-11 rounded-xl shrink-0 bg-n-alpha-2 text-n-slate-11"
          role="img"
          :aria-label="t(`RELACIONAMENTOS_FICHA.ARQUIVOS.TIPO.${midia.tipo}`)"
        >
          <span class="size-5" :class="ICONES[midia.tipo]" />
        </span>
        <div class="min-w-0">
          <p class="m-0 text-base truncate text-n-slate-12">
            {{ midia.nome }}
          </p>
          <p class="m-0 text-sm truncate text-n-slate-11">
            {{
              [midia.pessoa, quandoRelativo(midia.quando, agora, idioma)]
                .filter(Boolean)
                .join(SEPARADOR)
            }}
          </p>
        </div>
      </li>
    </ul>
  </CartaoDaSecao>
</template>
