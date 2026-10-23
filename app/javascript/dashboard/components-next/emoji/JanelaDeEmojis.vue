<script setup>
// Janela de emojis do painel: nasceu na resposta de e-mail (#1786) e hoje vale na
// caixa de resposta de todos os canais e na Nova conversa (#1895), no lugar da do
// Chatwoot, que a caixa de resposta (com rolagem própria) cortava. Inspirada no Slack e no
// WhatsApp: flutua por cima da tela (nada a corta), busca no topo, barra de categorias
// que leva à seção, grade larga com o emoji maior ao passar o mouse, os usados por
// último primeiro e Esc fecha. Mesmos dados e mesmos "recentes" do painel
// (shared/components/emoji).
import {
  computed,
  nextTick,
  onBeforeUnmount,
  onMounted,
  ref,
  useTemplateRef,
} from 'vue';
import { useI18n } from 'vue-i18n';
import {
  onClickOutside,
  useElementBounding,
  useEventListener,
  useWindowSize,
} from '@vueuse/core';
import Icon from 'next/icon/Icon.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';
import emojiGroups from 'shared/components/emoji/emojisGroup.json';
import {
  addRecentEmoji,
  buildEmojiSections,
  getRecentEmojis,
} from 'shared/components/emoji/pickerHelper';
import { semAcento } from 'dashboard/helper/semAcento';

const props = defineProps({
  // Elemento acima do qual a janela abre (a barra de baixo da caixa de resposta).
  ancora: { type: Object, default: null },
  // Lado da âncora em que a janela se alinha: 'inicio' (esquerda) ou 'fim' (direita, a
  // reação numa mensagem enviada).
  alinhar: { type: String, default: 'inicio' },
  // Na reação pelo celular a busca não ganha foco: o teclado cobriria a grade.
  focarBusca: { type: Boolean, default: true },
});
const emit = defineEmits(['escolher', 'fechar']);

const { t, locale } = useI18n();
const LARGURA = 360;
const ALTURA = 420;
const MARGEM = 12;

const ICONES = {
  recentes: 'i-lucide-clock-3',
  smileys_emotion: 'i-lucide-smile',
  people_body: 'i-lucide-hand',
  animals_nature: 'i-lucide-leaf',
  food_drink: 'i-lucide-coffee',
  travel_places: 'i-lucide-plane',
  activities: 'i-lucide-volleyball',
  objects: 'i-lucide-lightbulb',
  symbols: 'i-lucide-heart',
  flags: 'i-lucide-flag',
};

const busca = ref('');
const recentes = ref(getRecentEmojis());
const destaque = ref(null);
const janela = useTemplateRef('janela');
const grade = useTemplateRef('grade');
const campo = useTemplateRef('campo');

// Nomes em português (CLDR, via emojibase): carregados só quando o painel está em
// português, para a busca achar "coração" e "risada" além de "heart" e "smile".
const nomesEmPortugues = ref({});
const nomeEmPortugues = emoji =>
  (nomesEmPortugues.value[emoji.slug] || '').split(' · ')[0];
const nomeDoEmoji = emoji => nomeEmPortugues(emoji) || emoji.name;

// Cada palavra digitada precisa aparecer no nome (em inglês ou em português):
// "bandeira brasil" acha "bandeira: Brasil".
const achados = termo => {
  const palavras = termo.split(' ').filter(Boolean);
  const casa = texto => palavras.every(palavra => texto.includes(palavra));
  return emojiGroups
    .map(({ name, emojis }) => ({
      name,
      emojis: emojis.filter(
        emoji =>
          casa(semAcento(`${emoji.slug.replaceAll('_', ' ')} ${emoji.name}`)) ||
          casa(semAcento(nomesEmPortugues.value[emoji.slug]))
      ),
    }))
    .filter(grupo => grupo.emojis.length);
};

const secoes = computed(() => {
  const nomeDosRecentes = t('CONVERSA_CANAL.EMAIL.EMOJIS.RECENTES');
  const termo = semAcento(busca.value.trim());
  const base = termo
    ? achados(termo)
    : buildEmojiSections('', recentes.value, nomeDosRecentes);
  return base.map(secao => {
    const grupo = emojiGroups.find(g => g.name === secao.name);
    const slug = grupo?.slug || 'recentes';
    return {
      ...secao,
      slug,
      titulo: t(`CONVERSA_CANAL.EMAIL.EMOJIS.${slug.toUpperCase()}`),
    };
  });
});
const categorias = computed(() => [
  ...(recentes.value.length ? [{ slug: 'recentes' }] : []),
  ...emojiGroups.map(({ slug }) => ({ slug })),
]);
const ativa = ref(categorias.value[0]?.slug);

// Posição: em cima da âncora (a barra de baixo da caixa de resposta ou o balão),
// alinhada ao lado pedido; sem espaço em cima, abre do lado que tem mais espaço e
// encolhe para caber. Nunca sai da tela. Acompanha a âncora quando ela muda de tamanho
// ou a página rola (#1895, #2113).
const { width: larguraDaTela, height: alturaDaTela } = useWindowSize();
const ancora = useElementBounding(() => props.ancora);
const DISTANCIA = 8;
const posicao = computed(() => {
  const caixa = props.ancora
    ? {
        left: ancora.left.value,
        right: ancora.right.value,
        top: ancora.top.value,
        bottom: ancora.bottom.value,
      }
    : null;
  const largura = Math.min(LARGURA, larguraDaTela.value - MARGEM * 2);
  const inicio =
    props.alinhar === 'fim' && caixa ? caixa.right - largura : caixa?.left;
  const esquerda = Math.min(
    Math.max(MARGEM, inicio ?? MARGEM),
    larguraDaTela.value - largura - MARGEM
  );
  const espacoEmCima = (caixa?.top ?? alturaDaTela.value) - DISTANCIA - MARGEM;
  const espacoEmBaixo =
    alturaDaTela.value - (caixa?.bottom ?? 0) - DISTANCIA - MARGEM;
  const emCima = espacoEmCima >= ALTURA || espacoEmCima >= espacoEmBaixo;
  const altura = `${Math.min(ALTURA, Math.max(emCima ? espacoEmCima : espacoEmBaixo, 0))}px`;
  return emCima
    ? {
        left: `${esquerda}px`,
        width: `${largura}px`,
        height: altura,
        bottom: `${alturaDaTela.value - (caixa?.top ?? 0) + DISTANCIA}px`,
      }
    : {
        left: `${esquerda}px`,
        width: `${largura}px`,
        height: altura,
        top: `${(caixa?.bottom ?? 0) + DISTANCIA}px`,
      };
});

const escolher = emoji => {
  recentes.value = addRecentEmoji(emoji);
  emit('escolher', emoji.emoji);
};

const irPara = async slug => {
  busca.value = '';
  ativa.value = slug;
  await nextTick();
  grade.value
    ?.querySelector(`[data-secao="${slug}"]`)
    ?.scrollIntoView({ block: 'start' });
};

// Categoria acesa = a seção cujo título está no alto da grade.
const aoRolar = () => {
  const topo = grade.value?.getBoundingClientRect().top ?? 0;
  const titulos = [...(grade.value?.querySelectorAll('[data-secao]') || [])];
  const atual = titulos
    .filter(titulo => titulo.getBoundingClientRect().top - topo <= 8)
    .pop();
  if (atual) ativa.value = atual.dataset.secao;
};

const primeiroDaBusca = () => {
  const emoji = secoes.value[0]?.emojis[0];
  if (emoji) escolher(emoji);
};

onClickOutside(janela, () => emit('fechar'), {
  ignore: [() => props.ancora],
});

// Esc fecha mesmo com o foco fora da janela. Na captura do document, antes dos
// atalhos da tela: só a janela fecha, não a Nova conversa nem a resposta por baixo.
useEventListener(
  document,
  'keydown',
  evento => {
    if (evento.key !== 'Escape') return;
    evento.preventDefault();
    evento.stopPropagation();
    emit('fechar');
  },
  { capture: true }
);

// Ao fechar, o foco volta para onde estava ao abrir, se ficaria perdido (na janela
// que some ou no body). Se a pessoa já clicou em outro campo, fica lá.
let focoAoAbrir = null;
onBeforeUnmount(() => {
  const ativo = document.activeElement;
  const perdido =
    !ativo || ativo === document.body || janela.value?.contains(ativo);
  if (perdido && focoAoAbrir?.isConnected) focoAoAbrir.focus();
});

onMounted(async () => {
  focoAoAbrir = document.activeElement;
  if (props.focarBusca) campo.value?.focus();
  else janela.value?.focus();
  if (!String(locale.value).startsWith('pt')) return;
  const { default: nomes } = await import('./emojisEmPortugues.json');
  nomesEmPortugues.value = nomes;
});
</script>

<template>
  <TeleportWithDirection to="body">
    <!-- #1895: abre também de dentro do popover da Nova conversa (z-[9999]). Fica por cima
      dele, e data-popover-content diz ao popover que clique e Esc aqui são de uma
      sobreposta: escolher um emoji não fecha a Nova conversa. -->
    <div
      ref="janela"
      role="dialog"
      :aria-label="t('CONVERSA_CANAL.EMAIL.EMOJIS.TITULO')"
      class="fixed z-[10000] flex flex-col overflow-hidden rounded-2xl outline-none border border-n-weak bg-n-solid-1 shadow-[0_8px_32px_rgba(0,0,0,0.18),0_2px_6px_rgba(0,0,0,0.08)]"
      :style="posicao"
      tabindex="-1"
      data-janela-de-emojis
      data-popover-content
    >
      <div class="px-3 pt-3 pb-2">
        <label class="relative block">
          <Icon
            icon="i-lucide-search"
            class="pointer-events-none absolute start-3 top-1/2 size-4 -translate-y-1/2 text-n-slate-10"
          />
          <input
            ref="campo"
            v-model="busca"
            type="search"
            :placeholder="t('CONVERSA_CANAL.EMAIL.EMOJIS.BUSCAR')"
            :aria-label="t('CONVERSA_CANAL.EMAIL.EMOJIS.BUSCAR')"
            class="!mb-0 h-10 w-full !rounded-full !border !border-solid !border-n-weak !bg-n-alpha-1 !ps-9 !pe-3 text-sm text-n-slate-12 placeholder:text-n-slate-10 !outline-0 focus:!border-n-brand focus:!outline-0"
            data-buscar-emoji
            @keydown.enter.prevent="primeiroDaBusca"
          />
        </label>
      </div>
      <nav
        v-if="!busca.trim()"
        class="flex items-center justify-between gap-0.5 border-b border-n-weak px-2 pb-1.5"
        :aria-label="t('CONVERSA_CANAL.EMAIL.EMOJIS.CATEGORIAS')"
      >
        <button
          v-for="categoria in categorias"
          :key="categoria.slug"
          type="button"
          class="relative grid size-8 place-content-center rounded-lg transition-colors"
          :class="
            ativa === categoria.slug
              ? 'bg-n-alpha-2 text-n-slate-12'
              : 'text-n-slate-10 hover:bg-n-alpha-1 hover:text-n-slate-12'
          "
          :aria-label="
            t(`CONVERSA_CANAL.EMAIL.EMOJIS.${categoria.slug.toUpperCase()}`)
          "
          :title="
            t(`CONVERSA_CANAL.EMAIL.EMOJIS.${categoria.slug.toUpperCase()}`)
          "
          :aria-current="ativa === categoria.slug || undefined"
          @click="irPara(categoria.slug)"
        >
          <Icon :icon="ICONES[categoria.slug]" class="size-[18px]" />
          <span
            v-if="ativa === categoria.slug"
            class="absolute -bottom-1.5 left-1/2 h-0.5 w-4 -translate-x-1/2 rounded-full bg-n-brand"
            aria-hidden="true"
          />
        </button>
      </nav>
      <div
        ref="grade"
        class="flex-1 overflow-y-auto overscroll-contain px-2 pb-2 [scrollbar-width:thin]"
        @scroll.passive="aoRolar"
      >
        <p
          v-if="!secoes.length"
          class="flex flex-col items-center gap-2 py-12 text-center text-sm text-n-slate-11"
        >
          <Icon icon="i-lucide-search-x" class="size-7 text-n-slate-10" />
          {{ t('CONVERSA_CANAL.EMAIL.EMOJIS.NADA') }}
        </p>
        <section v-for="secao in secoes" :key="secao.slug + secao.name">
          <h4
            class="sticky top-0 z-10 bg-n-solid-1 px-1.5 pb-1 pt-2.5 text-[11px] font-semibold uppercase tracking-wider text-n-slate-10 backdrop-blur"
            :data-secao="secao.slug"
          >
            {{ secao.titulo }}
          </h4>
          <div class="grid grid-cols-8 gap-0.5">
            <button
              v-for="emoji in secao.emojis"
              :key="secao.slug + emoji.slug"
              type="button"
              class="grid aspect-square place-content-center rounded-lg text-[22px] leading-none transition-transform duration-100 hover:scale-110 hover:bg-n-alpha-2 focus-visible:bg-n-alpha-2 focus-visible:outline-none"
              :aria-label="nomeDoEmoji(emoji)"
              :title="nomeDoEmoji(emoji)"
              @mouseenter="destaque = emoji"
              @focus="destaque = emoji"
              @click="escolher(emoji)"
            >
              {{ emoji.emoji }}
            </button>
          </div>
        </section>
      </div>
      <footer
        class="flex h-12 items-center gap-2.5 border-t border-n-weak bg-n-alpha-1 px-3"
        aria-hidden="true"
      >
        <span class="text-[28px] leading-none">
          {{ destaque?.emoji || '😊' }}
        </span>
        <span class="truncate text-xs text-n-slate-11">
          {{
            destaque
              ? nomeEmPortugues(destaque) || `:${destaque.slug}:`
              : t('CONVERSA_CANAL.EMAIL.EMOJIS.DICA')
          }}
        </span>
      </footer>
    </div>
  </TeleportWithDirection>
</template>
