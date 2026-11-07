<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import AcharPainel from './AcharPainel.vue';
import AcharEscolhaGrande from './AcharEscolhaGrande.vue';
import AcharLinhaFrase from './AcharLinhaFrase.vue';
import AcharEstado from './AcharEstado.vue';

// #2692 — F1, a folha "O que fazer com as {n} empresas?" (v4). Dois cartões
// grandes e, abaixo do escolhido, a prévia em linhas-frase com "Alterar". Com
// um destino só possível, a folha abre direto na prévia dele, com o título
// dele. Os números não se repetem: o título diz quantas, o botão diz o que
// acontece.
// Rodada 2: a conta fecha. "Por que {n} não vão" soma tudo o que não vai (os
// motivos do sistema e as que a pessoa tirou) e aparece igual nos dois
// destinos; a prévia da lista diz só o que é dela (quem não tem celular nem
// e-mail). Erro no envio: o principal vira "Tentar de novo".
// Rodada 3: uma coluna só, também em 1440. Depois de escolher, os dois cartões
// viram uma linha ("Mandar para o funil ✓ · Trocar") e a prévia sobe, para o
// "Com quem fica" aparecer sem rolar. Na lista, quem não tem celular nem
// e-mail entra no "Por que {n} não vão" (a conta fecha nas achadas).
const props = defineProps({
  n: { type: Number, required: true },
  podeFunil: { type: Boolean, default: false },
  podeLista: { type: Boolean, default: false },
  escolha: { type: String, default: null },
  destino: { type: Object, default: null },
  pessoa: { type: String, required: true },
  podeTrocarPessoa: { type: Boolean, default: false },
  naoVao: { type: Array, default: () => [] },
  semContatoLista: { type: Number, default: 0 },
  nomeLista: { type: String, default: '' },
  entramLista: { type: Number, default: 0 },
  enviando: { type: Object, default: null },
  guardando: { type: Boolean, default: false },
  erro: { type: String, default: null },
  mostrarFora: { type: Boolean, default: false },
});
const emit = defineEmits([
  'escolher',
  'alterarDestino',
  'alterarPessoa',
  'mandar',
  'guardar',
  'close',
  'update:nomeLista',
  'update:mostrarFora',
]);

const { t } = useI18n();
const NS = 'PROSPECTING_ACHAR.FOLHA';
const editandoNome = ref(false);

const dois = computed(() => props.podeFunil && props.podeLista);
const escolhaFinal = computed(() => {
  if (dois.value) return props.escolha;
  return props.podeFunil ? 'funil' : 'lista';
});
const titulo = computed(() => {
  if (dois.value) return t(`${NS}.TITULO`, { n: props.n });
  return t(`${NS}.${props.podeFunil ? 'FUNIL' : 'LISTA'}.TITULO`);
});
// Lista: a base é a seleção ("Entram 12 das 14"); só quem não tem contato
// fica de fora. Funil: a conta fecha nas achadas (rodada 4).
const ehLista = computed(() => escolhaFinal.value === 'lista');
const motivosNaoVao = computed(() => {
  if (!ehLista.value) return props.naoVao;
  return props.semContatoLista
    ? [{ motivo: 'sem_contato', n: props.semContatoLista }]
    : [];
});
const totalNaoVao = computed(() =>
  motivosNaoVao.value.reduce((soma, item) => soma + item.n, 0)
);
const OPCOES = {
  funil: { icone: 'i-lucide-square-kanban', tom: 'bg-n-blue-3 text-n-blue-11' },
  lista: { icone: 'i-lucide-send', tom: 'bg-n-teal-3 text-n-teal-11' },
};

const CHAVES_FORA = {
  no_funil: 'NO_FUNIL',
  nao_quer: 'NAO_QUER',
  tirou: 'TIROU',
  fechou: 'FECHOU',
  voce_tirou: 'VOCE_TIROU',
  sem_contato: 'SEM_CONTATO',
  voce_mandou: 'VOCE_MANDOU',
};
const enviando = computed(() => Boolean(props.enviando));

const botao = computed(() => {
  if (!escolhaFinal.value) {
    return { rotulo: t(`${NS}.ESCOLHA_O_QUE`), desabilitado: true };
  }
  if (escolhaFinal.value === 'funil') {
    if (props.enviando) {
      return {
        rotulo: t(`${NS}.MANDANDO`, {
          feitas: props.enviando.feitas,
          total: props.enviando.total,
        }),
        ocupado: true,
      };
    }
    if (!props.destino) {
      return {
        rotulo: t(`${NS}.MANDAR`, { n: props.n }),
        desabilitado: true,
        dica: t(`${NS}.DICA_FUNIL`),
      };
    }
    if (props.erro === 'funil') {
      return { rotulo: t(`${NS}.TENTAR`), acao: 'mandar' };
    }
    return { rotulo: t(`${NS}.MANDAR`, { n: props.n }), acao: 'mandar' };
  }
  if (props.guardando) return { rotulo: t(`${NS}.GUARDANDO`), ocupado: true };
  if (!props.entramLista) {
    return { rotulo: t(`${NS}.NINGUEM`), desabilitado: true };
  }
  return {
    rotulo: t(`${NS}.GUARDAR`, { n: props.entramLista }),
    acao: 'guardar',
  };
});
const agirBotao = () => {
  if (botao.value.acao === 'mandar') emit('mandar');
  if (botao.value.acao === 'guardar') emit('guardar');
};

// Ao abrir "Por que N não vão", a lista vem para a vista (fica abaixo da dobra
// no celular).
const listaFora = ref(null);
watch(
  () => props.mostrarFora,
  async aberta => {
    if (!aberta) return;
    await nextTick();
    listaFora.value?.scrollIntoView({ block: 'nearest' });
  },
  { immediate: true }
);
</script>

<template>
  <AcharPainel :titulo="titulo" @close="emit('close')">
    <div
      v-if="dois && escolha"
      class="flex items-center gap-3 p-3 border-2 border-solid rounded-2xl border-n-blue-9 bg-n-solid-1"
      :class="{ 'pointer-events-none opacity-60': enviando }"
      data-escolhido
    >
      <span
        class="grid shrink-0 size-10 place-items-center rounded-xl"
        :class="OPCOES[escolha].tom"
        aria-hidden="true"
      >
        <span class="size-5" :class="OPCOES[escolha].icone" />
      </span>
      <span class="flex-1 min-w-0 text-base font-semibold text-n-slate-12">
        {{ $t(`${NS}.${escolha === 'funil' ? 'FUNIL' : 'LISTA'}.TITULO`) }}
      </span>
      <Button
        :label="$t('PROSPECTING_ACHAR.COMUM.ALTERAR')"
        slate
        faded
        size="sm"
        class="!min-h-11 !rounded-xl shrink-0"
        data-trocar-escolha
        @click="emit('escolher', null)"
      />
    </div>
    <div
      v-else-if="dois"
      role="radiogroup"
      class="flex flex-col gap-3"
      :class="{ 'pointer-events-none opacity-60': enviando }"
    >
      <AcharEscolhaGrande
        icone="i-lucide-square-kanban"
        :titulo="$t(`${NS}.FUNIL.TITULO`)"
        :texto="$t(`${NS}.FUNIL.TEXTO`)"
        :escolhido="escolha === 'funil'"
        data-escolha-funil
        @escolher="emit('escolher', 'funil')"
      />
      <AcharEscolhaGrande
        icone="i-lucide-send"
        tom="bg-n-teal-3 text-n-teal-11"
        :titulo="$t(`${NS}.LISTA.TITULO`)"
        :texto="$t(`${NS}.LISTA.TEXTO`)"
        :escolhido="escolha === 'lista'"
        data-escolha-lista
        @escolher="emit('escolher', 'lista')"
      />
    </div>

    <AcharEstado
      v-if="erro"
      faixa
      tom="erro"
      :texto="$t(erro === 'lista' ? `${NS}.ERRO_LISTA` : `${NS}.ERRO_FUNIL`)"
    />

    <div
      v-if="escolhaFinal === 'funil'"
      class="flex flex-col gap-3"
      :class="{ 'pointer-events-none opacity-60': enviando }"
      data-previa-funil
    >
      <AcharLinhaFrase
        v-if="destino"
        icone="i-lucide-columns-3"
        :texto="
          $t(`${NS}.PARA_ONDE`, {
            funil: destino.funil.nome,
            etapa: destino.etapa.nome,
          })
        "
        pode-alterar
        @alterar="emit('alterarDestino')"
      />
      <AcharLinhaFrase
        v-else
        icone="i-lucide-columns-3"
        tom="cinza"
        tracejada
        :texto="$t(`${NS}.ESCOLHA_FUNIL`)"
        :rotulo-acao="$t('PROSPECTING_ACHAR.COMUM.ESCOLHER')"
        pode-alterar
        data-sem-destino
        @alterar="emit('alterarDestino')"
      />
      <AcharLinhaFrase
        icone="i-lucide-user-round"
        tom="verde"
        :texto="$t(`${NS}.COM_QUEM`, { pessoa })"
        :pode-alterar="podeTrocarPessoa"
        data-com-quem
        @alterar="emit('alterarPessoa')"
      />
    </div>

    <div
      v-if="escolhaFinal === 'lista'"
      class="flex flex-col gap-3"
      data-previa-lista
    >
      <AcharLinhaFrase
        icone="i-lucide-list"
        tom="verde"
        :rotulo="$t(`${NS}.NOME_LISTA_ROTULO`)"
        :texto="nomeLista"
        pode-alterar
        @alterar="editandoNome = !editandoNome"
      />
      <input
        v-if="editandoNome"
        :value="nomeLista"
        type="text"
        :aria-label="$t(`${NS}.NOME_LISTA_ROTULO`)"
        class="w-full h-12 px-3 text-base border outline-none !mb-0 rounded-xl border-n-weak bg-n-solid-1 text-n-slate-12 focus:border-n-blue-9"
        @input="emit('update:nomeLista', $event.target.value)"
      />
      <AcharLinhaFrase
        icone="i-lucide-users"
        :texto="$t(`${NS}.ENTRAM`, { n: entramLista, total: n })"
      />
    </div>

    <section v-if="escolhaFinal && totalNaoVao" class="flex flex-col gap-2">
      <button
        type="button"
        class="flex items-center self-start gap-1.5 px-1 text-sm font-medium min-h-11 text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        :aria-expanded="mostrarFora"
        data-ver-fora
        @click="emit('update:mostrarFora', !mostrarFora)"
      >
        <span
          class="transition-transform i-lucide-chevron-down size-4"
          :class="{ '-rotate-90 rtl:rotate-90': !mostrarFora }"
          aria-hidden="true"
        />
        {{
          $t(
            `${NS}.${ehLista ? 'NAO_ENTRAM_LINK' : 'NAO_VAO_LINK'}`,
            { n: totalNaoVao },
            totalNaoVao
          )
        }}
      </button>
      <ul
        v-if="mostrarFora"
        ref="listaFora"
        class="flex flex-col gap-1 p-4 m-0 list-none rounded-2xl bg-n-slate-2"
        data-lista-fora
      >
        <li
          v-for="item in motivosNaoVao"
          :key="item.motivo"
          class="text-base text-n-slate-12"
        >
          {{
            $t(
              `${NS}.FORA_MOTIVOS.${CHAVES_FORA[item.motivo]}`,
              { n: item.n },
              item.n
            )
          }}
        </li>
      </ul>
    </section>

    <template #rodape>
      <p
        v-if="botao.dica"
        class="m-0 text-sm text-center text-n-slate-11"
        role="status"
        data-dica-folha
      >
        {{ botao.dica }}
      </p>
      <Button
        :label="botao.rotulo"
        :disabled="botao.desabilitado"
        :is-loading="botao.ocupado"
        class="!h-auto !min-h-12 !whitespace-normal !rounded-xl !py-2 !text-base"
        data-principal-folha
        @click="agirBotao"
      />
    </template>
  </AcharPainel>
</template>
