<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { usePeopleAccess } from 'dashboard/composables/usePeopleAccess';
import { CRM_METAS_MANAGE_PERMISSION } from 'dashboard/constants/permissions';
import Input from 'dashboard/components-next/input/Input.vue';
import {
  CONVERSATION_LEVELS,
  modulesWithKeys,
} from '../../customRoles/permissionMatrix';
import { dependenciaDe } from '../chavesDaFuncao';
import { menuDaFuncao, nivel } from '../fraseDaFuncao';
import { useTextos } from './useTextos';
import BotaoGrande from './BotaoGrande.vue';
import ComoVaiFicar from './ComoVaiFicar.vue';
import DialogoDaCasa from './DialogoDaCasa.vue';

// Confira (#2308, especificação 5.B4 e 10.4). No celular, a ordem é: "Vai se chamar … · Trocar", a prévia completa,
// o formulário e a nota; o rodapé fixo repete o menu acima de "Salvar função". No computador, a prévia fica na
// coluna da direita (da página) e esta etapa mostra só o formulário. A nota dos canais só aparece para quem atende
// conversas; "Ver os canais" abre uma folha com os canais que quem monta enxerga (todos, para o administrador; os
// dele, para os outros). Sem nome ("Começar do zero"), nenhuma frase fica pela metade. O erro do nome é anunciado e
// quebra linha no celular. A cada erro ao salvar, a tela rola até ele e põe o foco nele (o campo do nome ou o aviso):
// no celular o botão fica fixo embaixo, e o erro ficaria fora da vista.
const props = defineProps({
  modo: { type: String, required: true },
  permissions: { type: Array, required: true },
  inicial: { type: Array, required: true },
  dicaDoNome: { type: String, default: '' },
  erroDoNome: { type: String, default: '' },
  erro: { type: String, default: '' },
  vezDoErro: { type: Number, default: 0 },
  // Chaves que a cópia cortou porque quem monta não pode dar (especificação 5.C).
  deFora: { type: Array, default: () => [] },
  salvando: { type: Boolean, default: false },
  podeEscolherPessoas: { type: Boolean, default: false },
});

const emit = defineEmits(['salvar']);
const nome = defineModel('nome', { type: String, required: true });
const descricao = defineModel('descricao', { type: String, default: '' });

const { t, te, lista, nomeDaArea } = useTextos();
const { isAdmin } = usePeopleAccess();
const caixas = useMapGetter('inboxes/getInboxes');
const ID_DO_NOME = 'funcao-guiada-nome';
const ID_DO_ERRO = 'funcao-guiada-nome-erro';
const folhaDosCanais = ref(null);

const semNome = computed(() => !nome.value.trim());
const noMenu = computed(() => {
  const itens = menuDaFuncao(props.permissions);
  if (!itens.length) return t('FUNCOES_EQUIPE.CONFIRA.MENU_VAZIO');
  return t('FUNCOES_EQUIPE.CONFIRA.NO_MENU', {
    itens: lista(itens.map(item => t(`FUNCOES_EQUIPE.MENU.${item}`))),
  });
});
const atendeConversas = computed(
  () => nivel('CONVERSATIONS', props.permissions) !== CONVERSATION_LEVELS.NONE
);
const canais = computed(() => (caixas.value || []).map(caixa => caixa.name));
const daFolha = computed(() => (isAdmin.value ? 'DA_CONTA' : 'SEUS'));

// R$ e metas saem juntos (KEY_DEPENDENCIES), e o aviso diz isso numa coisa só.
const JUNTAS = [
  CRM_METAS_MANAGE_PERMISSION,
  dependenciaDe(CRM_METAS_MANAGE_PERMISSION),
];
const coisaDaCopia = chave =>
  te(`FUNCOES_EQUIPE.CONFIRA.COPIA.${chave}`)
    ? t(`FUNCOES_EQUIPE.CONFIRA.COPIA.${chave}`)
    : nomeDaArea(modulesWithKeys([chave])[0]?.key);
const aviso = computed(() => {
  if (!props.deFora.length) return '';
  const juntas = JUNTAS.every(chave => props.deFora.includes(chave));
  const resto = juntas
    ? props.deFora.filter(chave => !JUNTAS.includes(chave))
    : props.deFora;
  const coisas = [
    ...(juntas ? [t('FUNCOES_EQUIPE.CONFIRA.COPIA.VALORES_E_METAS')] : []),
    ...new Set(resto.map(coisaDaCopia)),
  ];
  return t('FUNCOES_EQUIPE.CONFIRA.AVISO_COPIA', { coisas: lista(coisas) });
});

const avisoDoErro = ref(null);
const levarAte = elemento => {
  elemento?.scrollIntoView?.({ block: 'center' });
  elemento?.focus();
};

// "Trocar" rola até o campo e põe o foco nele.
const trocarNome = async () => {
  await nextTick();
  levarAte(document.getElementById(ID_DO_NOME));
};

watch(
  () => props.vezDoErro,
  async () => {
    await nextTick();
    if (props.erroDoNome) levarAte(document.getElementById(ID_DO_NOME));
    else levarAte(avisoDoErro.value);
  }
);
</script>

<template>
  <div class="flex flex-col gap-5">
    <h1
      class="m-0 text-2xl font-bold tracking-tight sm:text-3xl text-n-slate-12"
    >
      {{
        modo === 'duplicar'
          ? $t('FUNCOES_EQUIPE.CONFIRA.TITULO_COPIA')
          : $t('FUNCOES_EQUIPE.CONFIRA.TITULO')
      }}
    </h1>

    <p
      v-if="aviso"
      data-aviso-copia
      class="flex items-start gap-2 px-4 py-3 m-0 text-sm rounded-xl bg-n-amber-2 ring-1 ring-n-amber-6 text-n-slate-12"
    >
      <span
        class="i-lucide-triangle-alert size-4 mt-0.5 shrink-0 text-n-amber-11"
        aria-hidden="true"
      />
      {{ aviso }}
    </p>

    <p
      v-if="semNome"
      data-vai-se-chamar
      class="flex flex-wrap items-center m-0 gap-x-2 lg:hidden text-n-slate-12"
    >
      <button
        type="button"
        class="px-0 font-medium underline rounded min-h-11 underline-offset-4 text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        @click="trocarNome"
      >
        {{ $t('FUNCOES_EQUIPE.CONFIRA.DAR_NOME') }}
      </button>
    </p>
    <p
      v-else
      data-vai-se-chamar
      class="flex flex-wrap items-center m-0 gap-x-2 lg:hidden text-n-slate-12"
    >
      {{ $t('FUNCOES_EQUIPE.CONFIRA.VAI_SE_CHAMAR') }}
      <strong class="font-semibold">{{ nome }}</strong>
      <span aria-hidden="true" class="text-n-slate-11">
        {{ $t('FUNCOES_EQUIPE.CONTAGEM.SEPARADOR') }}
      </span>
      <button
        type="button"
        class="px-0 font-medium underline rounded min-h-11 underline-offset-4 text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        @click="trocarNome"
      >
        {{ $t('FUNCOES_EQUIPE.CONFIRA.TROCAR') }}
      </button>
    </p>
    <ComoVaiFicar
      data-previa-celular
      class="lg:hidden"
      :nome="nome"
      :permissions="permissions"
      :inicial="inicial"
    />

    <section
      data-formulario
      class="flex flex-col gap-4 p-5 border rounded-2xl border-n-weak bg-n-solid-1"
    >
      <div class="flex flex-col gap-1">
        <Input
          :id="ID_DO_NOME"
          v-model="nome"
          :label="$t('FUNCOES_EQUIPE.CONFIRA.NOME')"
          :message="erroDoNome ? '' : dicaDoNome"
          :message-type="erroDoNome ? 'error' : 'info'"
          :aria-invalid="Boolean(erroDoNome)"
          :aria-describedby="erroDoNome ? ID_DO_ERRO : undefined"
          wrap-message
          autocomplete="off"
        />
        <p
          v-if="erroDoNome"
          :id="ID_DO_ERRO"
          data-erro-nome
          role="alert"
          class="m-0 text-sm break-words text-n-ruby-11"
        >
          {{ erroDoNome }}
        </p>
      </div>
      <Input
        v-model="descricao"
        :label="$t('FUNCOES_EQUIPE.CONFIRA.PARA_QUEM')"
      />
    </section>

    <p
      v-if="atendeConversas"
      data-nota-canais
      class="flex flex-wrap items-center gap-2 m-0 text-sm text-n-slate-11"
    >
      <span class="i-lucide-info size-4 shrink-0" aria-hidden="true" />
      {{ $t('FUNCOES_EQUIPE.CONFIRA.NOTA_CANAIS') }}
      <button
        type="button"
        data-ver-canais
        class="px-0 font-medium underline min-h-11 underline-offset-4 text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        @click="folhaDosCanais?.abrir()"
      >
        {{ $t('FUNCOES_EQUIPE.CONFIRA.VER_CANAIS') }}
      </button>
    </p>
    <DialogoDaCasa
      ref="folhaDosCanais"
      tipo="aviso"
      icone="i-lucide-inbox"
      :titulo="$t(`FUNCOES_EQUIPE.CONFIRA.CANAIS.${daFolha}.TITULO`)"
      :texto="$t(`FUNCOES_EQUIPE.CONFIRA.CANAIS.${daFolha}.TEXTO`)"
      :seguro="$t('FUNCOES_EQUIPE.CONFIRA.CANAIS.FECHAR')"
    >
      <ul
        v-if="canais.length"
        data-canais
        class="flex flex-col gap-1.5 p-0 m-0 list-none"
      >
        <li
          v-for="canal in canais"
          :key="canal"
          class="flex items-center gap-2 text-[0.9375rem] text-n-slate-12"
        >
          <span
            class="i-lucide-inbox size-4 shrink-0 text-n-slate-11"
            aria-hidden="true"
          />
          {{ canal }}
        </li>
      </ul>
      <p v-else class="m-0 text-sm text-n-slate-11">
        {{ $t(`FUNCOES_EQUIPE.CONFIRA.CANAIS.${daFolha}.VAZIO`) }}
      </p>
    </DialogoDaCasa>
    <p
      v-if="podeEscolherPessoas && modo !== 'alterar'"
      class="flex items-center gap-2 m-0 text-sm text-n-slate-11"
    >
      <span class="i-lucide-users size-4 shrink-0" aria-hidden="true" />
      {{
        semNome
          ? $t('FUNCOES_EQUIPE.CONFIRA.DEPOIS_SEM_NOME')
          : $t('FUNCOES_EQUIPE.CONFIRA.DEPOIS', { nome })
      }}
    </p>

    <p
      v-if="erro"
      ref="avisoDoErro"
      data-erro-salvar
      role="alert"
      tabindex="-1"
      class="flex items-start gap-2 px-4 py-3 m-0 text-sm outline-none rounded-xl bg-n-ruby-2 ring-1 ring-n-ruby-6 text-n-slate-12"
    >
      <span
        class="i-lucide-circle-alert size-4 mt-0.5 shrink-0 text-n-ruby-11"
        aria-hidden="true"
      />
      {{ erro }}
    </p>

    <BotaoGrande
      :label="
        modo === 'alterar'
          ? $t('FUNCOES_EQUIPE.CONFIRA.SALVAR_ALTERACOES')
          : $t('FUNCOES_EQUIPE.CONFIRA.SALVAR')
      "
      :carregando="salvando"
      @click="emit('salvar')"
    >
      <template #acima>
        <p data-no-menu class="mt-0 mb-3 text-sm md:hidden text-n-slate-11">
          {{ noMenu }}
        </p>
      </template>
    </BotaoGrande>
  </div>
</template>
