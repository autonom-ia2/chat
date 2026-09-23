<script setup>
import { computed } from 'vue';
import { useRouter } from 'vue-router';
import { renderizar, refDoLink } from '../helpers/markdown';

const props = defineProps({
  conteudo: { type: String, default: '' },
  classeDaLetra: { type: String, default: 'prose-lg' },
});

const router = useRouter();
const html = computed(() => renderizar(props.conteudo));

// Link para outro artigo abre aqui dentro, sem recarregar; o resto segue o próprio link (nova aba).
const aoClicar = evento => {
  const link = evento.target.closest?.('a');
  const ref = refDoLink(link?.getAttribute('href'));
  if (!ref) return;
  evento.preventDefault();
  router.push({ name: 'central_de_ajuda_artigo', params: { ref } });
};
</script>

<template>
  <article
    v-dompurify-html="html"
    class="prose max-w-none text-n-slate-12 prose-headings:text-n-slate-12 prose-headings:font-semibold prose-h2:text-[1.4em] prose-h2:mt-10 prose-h2:mb-3 prose-p:text-[1em] prose-p:text-n-slate-12 prose-p:leading-relaxed prose-li:text-[1em] prose-li:text-n-slate-12 prose-li:marker:text-n-slate-10 prose-li:my-1 prose-strong:text-n-slate-12 prose-a:text-n-blue-11 prose-a:text-[1em] prose-a:underline prose-a:underline-offset-2 prose-img:rounded-xl prose-img:border prose-img:border-n-weak"
    :class="classeDaLetra"
    @click="aoClicar"
  />
</template>
