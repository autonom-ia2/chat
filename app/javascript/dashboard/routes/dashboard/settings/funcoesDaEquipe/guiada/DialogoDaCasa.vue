<script setup>
import { computed, nextTick, ref, useId } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';

// O diálogo da casa (#2308, especificação 9), uma anatomia só: quadrado de 44 px com ícone por tipo, título,
// explicação, risco opcional e o rodapé (à direita no computador; empilhado, na largura toda, no celular, com o
// seguro em cima, como no mockup). Cuidado = âmbar com ação azul; destrutivo = ruby com ação vermelha; aviso = cinza,
// só com o botão de fechar (a folha dos canais). O <dialog> modal deixa o resto inerte (foco preso); o botão seguro
// tem o foco inicial e responde ao Esc; ao fechar, o foco volta a quem abriu ou, se ele sumiu (o cartão apagado), ao
// `focoDeReserva`. Com `fechaNaAcao` desligado, a ação não fecha: quem usa grava, marca `ocupado` (o rótulo vira
// `acaoOcupada`, e seguro, Esc e um segundo clique ficam travados) e chama fechar() no fim.
const props = defineProps({
  tipo: {
    type: String,
    default: 'cuidado',
    validator: valor => ['cuidado', 'destrutivo', 'aviso'].includes(valor),
  },
  icone: { type: String, default: '' },
  titulo: { type: String, required: true },
  texto: { type: String, default: '' },
  risco: { type: String, default: '' },
  seguro: { type: String, required: true },
  acao: { type: String, default: '' },
  // Mesmo rótulo, só o estado muda (especificação 9): "Mover as pessoas e apagar" espera o destino.
  acaoDesabilitada: { type: Boolean, default: false },
  fechaNaAcao: { type: Boolean, default: true },
  ocupado: { type: Boolean, default: false },
  acaoOcupada: { type: String, default: '' },
  // Seletor de um alvo estável (o título da página) para quando quem abriu some.
  focoDeReserva: { type: String, default: '' },
  // Seletor, dentro do diálogo, do campo que recebe o foco quando ele é aberto de novo já aberto (o destino do apagar).
  focoAoReabrir: { type: String, default: '' },
});

const emit = defineEmits(['seguro', 'acao']);

const id = useId();
const dialogo = ref(null);
const botaoSeguro = ref(null);
const cabecalho = ref(null);
let gatilho = null;

const destrutivo = computed(() => props.tipo === 'destrutivo');
const ESTILO = {
  cuidado: {
    icone: 'i-lucide-triangle-alert',
    tom: 'bg-n-amber-3 text-n-amber-11',
  },
  destrutivo: { icone: 'i-lucide-trash-2', tom: 'bg-n-ruby-3 text-n-ruby-11' },
  aviso: { icone: 'i-lucide-info', tom: 'bg-n-alpha-2 text-n-slate-11' },
};
const estilo = computed(() => ESTILO[props.tipo]);

const focarTitulo = () => cabecalho.value?.focus();

// Abrir de novo com ele aberto (o apagar que volta a perguntar) troca o conteúdo: o foco vai ao campo marcado ou, sem
// ele, ao título, para o leitor de tela dizer o que mudou (revisão do #2308, rodada 4).
const reabrir = async () => {
  await nextTick();
  const campo =
    props.focoAoReabrir && dialogo.value?.querySelector(props.focoAoReabrir);
  if (campo) campo.focus();
  else focarTitulo();
};

const abrir = async () => {
  if (dialogo.value?.open) {
    await reabrir();
    return;
  }
  gatilho = document.activeElement;
  dialogo.value?.showModal?.();
  await nextTick();
  botaoSeguro.value?.$el?.focus();
};

const fechar = async () => {
  dialogo.value?.close?.();
  const quemAbriu = gatilho;
  gatilho = null;
  quemAbriu?.focus?.();
  if (!props.focoDeReserva) return;
  await nextTick();
  if (!quemAbriu?.isConnected)
    document.querySelector(props.focoDeReserva)?.focus();
};

const escolher = evento => {
  if (props.ocupado) return;
  if (evento === 'acao') {
    if (props.fechaNaAcao) fechar();
    emit('acao');
    return;
  }
  fechar();
  emit('seguro');
};

// O Esc dispara "cancel" no <dialog>: vira a ação segura (e não faz nada enquanto grava).
const aoCancelar = evento => {
  evento.preventDefault();
  escolher('seguro');
};

// No Chrome, um segundo Esc sem "cancel" atendido fecha o <dialog> direto (close watcher). Enquanto grava, o Esc
// para no teclado e não chega a ele.
const aoEsc = evento => {
  if (props.ocupado) evento.preventDefault();
};

defineExpose({ abrir, fechar, focarTitulo });
</script>

<template>
  <TeleportWithDirection to="body">
    <dialog
      ref="dialogo"
      :aria-labelledby="`${id}-titulo`"
      :aria-describedby="`${id}-texto`"
      class="w-full p-0 bg-transparent max-w-md rounded-2xl shadow-xl backdrop:bg-n-alpha-black1 max-sm:m-0 max-sm:mt-auto max-sm:max-w-none max-sm:rounded-b-none"
      @cancel="aoCancelar"
      @keydown.esc="aoEsc"
    >
      <div
        class="flex flex-col gap-4 p-6 rounded-2xl max-sm:rounded-b-none bg-n-solid-1"
      >
        <span
          class="grid place-items-center size-11 rounded-xl"
          :class="estilo.tom"
        >
          <span
            class="size-5"
            :class="icone || estilo.icone"
            aria-hidden="true"
          />
        </span>
        <h2
          :id="`${id}-titulo`"
          ref="cabecalho"
          tabindex="-1"
          class="m-0 text-lg font-semibold leading-snug outline-none text-n-slate-12"
        >
          {{ titulo }}
        </h2>
        <div :id="`${id}-texto`" class="flex flex-col gap-2">
          <p v-if="texto" class="m-0 text-[0.9375rem] text-n-slate-11">
            {{ texto }}
          </p>
          <p
            v-if="risco"
            data-risco
            class="flex items-start gap-2 m-0 text-sm text-n-slate-12"
          >
            <span
              class="i-lucide-triangle-alert size-4 mt-0.5 shrink-0 text-n-amber-11"
              aria-hidden="true"
            />
            {{ risco }}
          </p>
          <slot />
        </div>
        <div class="flex flex-col gap-2 sm:flex-row sm:justify-end">
          <Button
            ref="botaoSeguro"
            data-seguro
            type="button"
            :label="seguro"
            :disabled="ocupado"
            slate
            faded
            class="max-sm:w-full max-sm:!h-12 min-h-11"
            @click="escolher('seguro')"
          />
          <Button
            v-if="acao"
            data-acao
            type="button"
            :label="ocupado && acaoOcupada ? acaoOcupada : acao"
            :color="destrutivo ? 'ruby' : 'blue'"
            :disabled="acaoDesabilitada || ocupado"
            :aria-busy="ocupado || undefined"
            class="max-sm:w-full max-sm:!h-12 min-h-11"
            @click="escolher('acao')"
          />
        </div>
      </div>
    </dialog>
  </TeleportWithDirection>
</template>
