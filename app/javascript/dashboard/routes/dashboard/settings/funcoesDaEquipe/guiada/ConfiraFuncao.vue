<script setup>
import { computed, nextTick } from 'vue';
import { useRouter } from 'vue-router';
import Input from 'dashboard/components-next/input/Input.vue';
import { modulesWithKeys } from '../../customRoles/permissionMatrix';
import { menuDaFuncao } from '../fraseDaFuncao';
import { useTextos } from './useTextos';
import BotaoGrande from './BotaoGrande.vue';
import ComoVaiFicar from './ComoVaiFicar.vue';

// Confira (#2308, especificação 5.B4 e 10.4). No celular, a ordem é: "Vai se chamar … · Trocar", a prévia completa,
// o formulário e a nota; o rodapé fixo repete o menu acima de "Salvar função". No computador, a prévia fica na
// coluna da direita (da página) e esta etapa mostra só o formulário.
const props = defineProps({
  modo: { type: String, required: true },
  permissions: { type: Array, required: true },
  inicial: { type: Array, required: true },
  dicaDoNome: { type: String, default: '' },
  erroDoNome: { type: String, default: '' },
  erro: { type: String, default: '' },
  // Chaves que a cópia cortou porque quem monta não pode dar (especificação 5.C).
  deFora: { type: Array, default: () => [] },
  salvando: { type: Boolean, default: false },
  podeEscolherPessoas: { type: Boolean, default: false },
});

const emit = defineEmits(['salvar']);
const nome = defineModel('nome', { type: String, required: true });
const descricao = defineModel('descricao', { type: String, default: '' });

const router = useRouter();
const { t, te, lista, nomeDaArea } = useTextos();
const ID_DO_NOME = 'funcao-guiada-nome';

const menu = computed(() =>
  lista(
    menuDaFuncao(props.permissions).map(item =>
      t(`FUNCOES_EQUIPE.MENU.${item}`)
    )
  )
);
const canais = computed(
  () => router.resolve({ name: 'settings_inbox_list' }).href
);

// R$ e metas saem juntos (KEY_DEPENDENCIES), e o aviso diz isso numa coisa só.
const JUNTAS = ['sales_value_view', 'crm_metas_manage'];
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

// "Trocar" rola até o campo e põe o foco nele.
const trocarNome = async () => {
  await nextTick();
  const campo = document.getElementById(ID_DO_NOME);
  campo?.scrollIntoView?.({ block: 'center' });
  campo?.focus();
};
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
      data-vai-se-chamar
      class="flex flex-wrap items-center m-0 gap-x-2 lg:hidden text-n-slate-12"
    >
      {{ $t('FUNCOES_EQUIPE.CONFIRA.VAI_SE_CHAMAR') }}
      <strong class="font-semibold">{{ nome }}</strong>
      <button
        type="button"
        class="font-medium underline min-h-11 underline-offset-4 text-n-blue-11"
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
      <Input
        :id="ID_DO_NOME"
        v-model="nome"
        :label="$t('FUNCOES_EQUIPE.CONFIRA.NOME')"
        :message="erroDoNome || dicaDoNome"
        :message-type="erroDoNome ? 'error' : 'info'"
        autocomplete="off"
      />
      <Input
        v-model="descricao"
        :label="$t('FUNCOES_EQUIPE.CONFIRA.PARA_QUEM')"
      />
    </section>

    <p class="flex flex-wrap items-center gap-2 m-0 text-sm text-n-slate-11">
      <span class="i-lucide-info size-4 shrink-0" aria-hidden="true" />
      {{ $t('FUNCOES_EQUIPE.CONFIRA.NOTA_CANAIS') }}
      <a
        :href="canais"
        target="_blank"
        rel="noopener noreferrer"
        class="font-medium underline underline-offset-4 text-n-blue-11"
      >
        {{ $t('FUNCOES_EQUIPE.CONFIRA.VER_CANAIS') }}
      </a>
    </p>
    <p
      v-if="podeEscolherPessoas && modo !== 'alterar'"
      class="flex items-center gap-2 m-0 text-sm text-n-slate-11"
    >
      <span class="i-lucide-users size-4 shrink-0" aria-hidden="true" />
      {{ $t('FUNCOES_EQUIPE.CONFIRA.DEPOIS', { nome }) }}
    </p>

    <p
      v-if="erro"
      data-erro-salvar
      role="alert"
      class="flex items-start gap-2 px-4 py-3 m-0 text-sm rounded-xl bg-n-ruby-2 ring-1 ring-n-ruby-6 text-n-slate-12"
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
        <p data-no-menu class="mt-0 mb-3 text-sm lg:hidden text-n-slate-11">
          {{ $t('FUNCOES_EQUIPE.CONFIRA.NO_MENU', { itens: menu }) }}
        </p>
      </template>
    </BotaoGrande>
  </div>
</template>
