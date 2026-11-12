<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { chaveDoTexto } from '../catalogo';
import { useVitrine } from '../useVitrine';
import VitrinePreco from './VitrinePreco.vue';
import VitrineRodapeGratis from './VitrineRodapeGratis.vue';
import VitrineSeloPremium from './VitrineSeloPremium.vue';

// #2858 F2 — o cartão de uma ferramenta pronta: o que ela faz em uma frase, o apoio ("tabela FIPE") só como detalhe, e
// um selo: o agente escolhido já sabe, ou quantas perguntas ela responde. O cartão inteiro é o botão que abre o
// detalhe. No pé, o rodapé do mesmo tamanho nos dois tipos: o preço do Premium ou o "Consulta grátis" (`mt-auto`
// prende no fundo, e o selo de perguntas fica logo acima, alinhado entre os cartões da linha).
const props = defineProps({
  ferramenta: { type: Object, required: true },
  tom: { type: String, default: 'azul' },
  // Nome do agente escolhido que já tem esta ferramenta; vazio quando não tem.
  jaSabe: { type: String, default: '' },
  destaque: { type: Boolean, default: false },
  // F7: o preço e as grátis que restam do card Premium; null nos grátis (que não ganham selo).
  premium: { type: Object, default: null },
});

const emit = defineEmits(['abrir']);

const NS = 'AGENTS.VITRINE';
const { t, te, locale } = useI18n();
const { atualizadoEm, estaEmPreparacao } = useVitrine();

// #2858 F5 — a base que a plataforma baixa diz de quando é a cópia ("Atualizado em 11/11/2026"); antes da primeira
// cópia, que os dados chegam logo; se a primeira cópia já falhou, "em preparação" (sem prometer prazo). O dia vem do
// servidor ("2026-11-11") e é mostrado no formato do idioma da tela.
const atualizacao = computed(() => {
  if (!props.ferramenta.base) return '';
  const dia = atualizadoEm(props.ferramenta.id);
  if (!dia && estaEmPreparacao(props.ferramenta.id)) {
    return t(`${NS}.CARTAO.EM_PREPARACAO`);
  }
  if (!dia) return t(`${NS}.CARTAO.PREPARANDO`);
  const [ano, mes, diaDoMes] = dia.split('-').map(Number);
  const texto = new Date(ano, mes - 1, diaDoMes).toLocaleDateString(
    String(locale.value).replace('_', '-')
  );
  return t(`${NS}.CARTAO.ATUALIZADO_EM`, { data: texto });
});

const textos = computed(() => {
  const base = `${NS}.FERRAMENTAS.${chaveDoTexto(props.ferramenta.id)}`;
  return {
    nome: t(`${base}.NOME`),
    // O apoio é opcional: ferramenta sem fonte para citar não tem a chave.
    apoio: te(`${base}.APOIO`) ? t(`${base}.APOIO`) : '',
    faz: t(`${base}.FAZ`),
  };
});

const TONS = {
  azul: 'bg-n-blue-3 text-n-blue-11',
  teal: 'bg-n-teal-3 text-n-teal-11',
  ambar: 'bg-n-amber-3 text-n-amber-11',
  rosa: 'bg-n-ruby-3 text-n-ruby-11',
  violeta: 'bg-n-iris-3 text-n-iris-11',
  cinza: 'bg-n-slate-3 text-n-slate-11',
};

const selo = computed(() => {
  if (props.jaSabe) {
    return {
      texto: t(`${NS}.CARTAO.JA_SABE`, { nome: props.jaSabe }),
      icone: 'i-lucide-check',
      classe: 'bg-n-teal-3 text-n-teal-11',
    };
  }
  if (props.ferramenta.consultas) {
    return {
      texto: t(`${NS}.CARTAO.CONSULTAS`, { n: props.ferramenta.consultas }),
      icone: 'i-lucide-messages-square',
      classe: 'bg-n-alpha-2 text-n-slate-11',
    };
  }
  return null;
});
</script>

<template>
  <button
    type="button"
    :data-vitrine-cartao="ferramenta.id"
    class="flex flex-col w-full h-full gap-3 p-5 text-start transition shadow-sm rounded-2xl bg-n-solid-1 ring-1 ring-inset hover:-translate-y-0.5 hover:shadow-md focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-blue-11"
    :class="destaque ? 'ring-n-blue-6' : 'ring-n-weak hover:ring-n-blue-6'"
    @click="emit('abrir', ferramenta)"
  >
    <span class="flex items-start gap-3">
      <span
        aria-hidden="true"
        class="grid rounded-xl place-items-center size-11 shrink-0"
        :class="TONS[tom] || TONS.azul"
      >
        <span :class="ferramenta.icone" class="size-6" />
      </span>
      <span class="flex flex-col flex-1 min-w-0 gap-0.5">
        <span class="text-base font-semibold leading-snug text-n-slate-12">
          {{ textos.nome }}
        </span>
        <span v-if="textos.apoio" class="text-xs text-n-slate-11">
          {{ textos.apoio }}
        </span>
      </span>
      <VitrineSeloPremium v-if="premium" class="mt-0.5" />
    </span>
    <span class="flex-1 text-sm leading-relaxed text-n-slate-11">
      {{ textos.faz }}
    </span>
    <span
      v-if="atualizacao"
      data-vitrine-atualizado
      class="inline-flex items-center gap-1.5 text-xs text-n-slate-11"
    >
      <span class="i-lucide-refresh-cw size-3.5" aria-hidden="true" />
      {{ atualizacao }}
    </span>
    <span
      v-if="selo"
      class="inline-flex items-center self-start gap-1.5 px-2.5 py-1 text-xs font-medium rounded-lg"
      :class="selo.classe"
    >
      <span :class="selo.icone" class="size-3.5" aria-hidden="true" />
      {{ selo.texto }}
    </span>
    <VitrinePreco v-if="premium" :premium="premium" class="mt-auto" />
    <!-- Card pago sem o dado do servidor não ganha rodapé: não pode dizer "Consulta grátis". -->
    <VitrineRodapeGratis v-else-if="!ferramenta.premium" class="mt-auto" />
  </button>
</template>
