<script setup>
import { computed, ref } from 'vue';
import {
  LEVELS,
  moduleByKey,
  setLevel,
  toggleExtra,
} from '../../customRoles/permissionMatrix';
import { gruposDoCuidado } from '../areasDaFuncao';
import { TEXTO_DA_TRAVA } from '../motivoDaTrava';
import { useTextos } from './useTextos';
import DialogoDaCasa from './DialogoDaCasa.vue';
import InterruptorDaLinha from './InterruptorDaLinha.vue';
import LinhaRecolhida from './LinhaRecolhida.vue';
import PerguntaDaFuncao from './PerguntaDaFuncao.vue';

// Ações que pedem cuidado (#2308, especificação 5.B3 e 7.2), em três grupos: (b) liga junto com a área, com uma
// confirmação só ("Ligar as duas"/"Ligar os dois"); (a) liga agora; (c) recolhida com cadeado. As linhas ligáveis
// ficam na ordem fixa: ligar uma (b) não a tira do lugar.
const props = defineProps({
  permissions: { type: Array, required: true },
  inicial: { type: Array, required: true },
  giver: { type: Object, required: true },
  quem: { type: String, required: true },
  quemSujeito: { type: String, required: true },
});

const emit = defineEmits(['update:permissions', 'pronto']);
const { t, lista, maiuscula } = useTextos();

// Chave i18n do diálogo e da faixa de cada (b).
const JUNTO = { contact_delete: 'CONTATOS', campaign_send: 'CAMPANHAS' };

const ORDEM = [
  'contact_export',
  'conversation_message_delete',
  'crm_manage_ai',
  'contact_delete',
  'campaign_send',
];

const dialogo = ref(null);
const pendente = ref(null);
const desfazer = ref(null);

const grupos = computed(() => gruposDoCuidado(props.giver, props.permissions));
const ligaveis = computed(() => {
  const { ligaJunto, ligaAgora } = grupos.value;
  const junto = new Set(ligaJunto.map(item => item.chave));
  return [...ligaAgora, ...ligaJunto]
    .map(item => ({ ...item, junto: junto.has(item.chave) }))
    .sort((a, b) => ORDEM.indexOf(a.chave) - ORDEM.indexOf(b.chave));
});

const algumaLigada = computed(() =>
  ligaveis.value.some(item => props.permissions.includes(item.chave))
);
const mudou = chave =>
  props.permissions.includes(chave) !== props.inicial.includes(chave);

const tituloDoCadeado = computed(() => {
  const { naoPode } = grupos.value;
  const coisas = maiuscula(
    lista(naoPode.map(item => t(`FUNCOES_EQUIPE.CUIDADO.${item.chave}`)))
  );
  return {
    titulo: t('FUNCOES_EQUIPE.CUIDADO_TELA.CADEADO', naoPode.length),
    coisas,
  };
});

const atualizar = permissions => emit('update:permissions', permissions);

// "Ligar as duas": a área em manage e a chave, exatamente essas duas (especificação 7.7).
const ligarJunto = ({ chave, area }) => {
  const module = moduleByKey(area);
  const antes = props.permissions;
  const comArea = setLevel(module, LEVELS.MANAGE, antes);
  atualizar(toggleExtra(module, chave, comArea));
  desfazer.value = { chave, antes };
};

const alternar = item => {
  const ligando = !props.permissions.includes(item.chave);
  if (ligando && item.junto) {
    pendente.value = item;
    dialogo.value?.abrir();
    return;
  }
  atualizar(toggleExtra(moduleByKey(item.area), item.chave, props.permissions));
};

const confirmar = () => {
  ligarJunto(pendente.value);
  pendente.value = null;
};

const voltarAtras = () => {
  atualizar(desfazer.value.antes);
  desfazer.value = null;
};

const textoDoDialogo = parte =>
  pendente.value
    ? t(
        `FUNCOES_EQUIPE.CUIDADO_TELA.JUNTO.${JUNTO[pendente.value.chave]}.${parte}`,
        {
          quem: props.quem,
        }
      )
    : '';
</script>

<template>
  <PerguntaDaFuncao
    :titulo="$t('FUNCOES_EQUIPE.CUIDADO_TELA.TITULO', { quem: quemSujeito })"
    @pronto="emit('pronto')"
  >
    <template #dica>
      <p class="m-0 text-base text-n-slate-11">
        <template v-if="algumaLigada">
          {{ $t('FUNCOES_EQUIPE.CUIDADO_TELA.DICA_LIGADA') }}
        </template>
        <template v-else>
          <span class="hidden sm:inline">
            {{ $t('FUNCOES_EQUIPE.CUIDADO_TELA.DICA') }}
          </span>
          <span class="sm:hidden">
            {{ $t('FUNCOES_EQUIPE.CUIDADO_TELA.DICA_CURTA') }}
          </span>
        </template>
      </p>
    </template>

    <div
      v-if="desfazer"
      data-faixa-junto
      role="status"
      class="flex items-center gap-3 px-4 py-3 border rounded-2xl border-n-blue-6 bg-n-blue-2"
    >
      <span
        class="i-lucide-info size-5 shrink-0 text-n-blue-11"
        aria-hidden="true"
      />
      <p class="flex-1 m-0 font-medium text-n-slate-12">
        {{
          $t(
            `FUNCOES_EQUIPE.CUIDADO_TELA.JUNTO.${JUNTO[desfazer.chave]}.AGORA`,
            {
              quem,
            }
          )
        }}
      </p>
      <button
        type="button"
        data-desfazer
        class="px-4 text-sm font-medium rounded-xl min-h-11 bg-n-alpha-2 text-n-slate-12 hover:bg-n-alpha-3"
        @click="voltarAtras"
      >
        {{ $t('FUNCOES_EQUIPE.GUIADA.DESFAZER') }}
      </button>
    </div>

    <div
      class="flex flex-col overflow-hidden border divide-y rounded-2xl border-n-weak divide-n-weak bg-n-solid-1"
    >
      <InterruptorDaLinha
        v-for="item in ligaveis"
        :key="item.chave"
        :data-cuidado="item.chave"
        :titulo="$t(`FUNCOES_EQUIPE.CUIDADO_TELA.LINHA.${item.chave}.TITULO`)"
        :texto="$t(`FUNCOES_EQUIPE.CUIDADO_TELA.LINHA.${item.chave}.TEXTO`)"
        :nota="
          item.junto
            ? $t(
                `FUNCOES_EQUIPE.CUIDADO_TELA.JUNTO.${JUNTO[item.chave]}.NOTA`,
                {
                  quem,
                }
              )
            : ''
        "
        :ligado="permissions.includes(item.chave)"
        :mudou="mudou(item.chave)"
        @alternar="alternar(item)"
      />
    </div>

    <LinhaRecolhida
      v-if="grupos.naoPode.length"
      icone="i-lucide-lock"
      :titulo="tituloDoCadeado.titulo"
      :estado="tituloDoCadeado.coisas"
    >
      <ul class="flex flex-col p-0 m-0 list-none divide-y divide-n-weak">
        <li
          v-for="item in grupos.naoPode"
          :key="item.chave"
          :data-cadeado="item.chave"
          class="flex flex-col gap-1 px-4 py-3"
        >
          <span class="font-medium text-n-slate-12">
            {{ $t(`FUNCOES_EQUIPE.CUIDADO_TELA.LINHA.${item.chave}.TITULO`) }}
          </span>
          <span class="flex items-center gap-1.5 text-sm text-n-slate-11">
            <span class="i-lucide-lock size-4 shrink-0" aria-hidden="true" />
            {{ $t(`FUNCOES_EQUIPE.TRAVA.${TEXTO_DA_TRAVA[item.motivo]}`) }}
          </span>
        </li>
      </ul>
    </LinhaRecolhida>

    <DialogoDaCasa
      ref="dialogo"
      :titulo="textoDoDialogo('TITULO')"
      :texto="textoDoDialogo('TEXTO')"
      :risco="textoDoDialogo('RISCO')"
      :seguro="$t('FUNCOES_EQUIPE.GUIADA.AGORA_NAO')"
      :acao="textoDoDialogo('LIGAR')"
      @acao="confirmar"
      @seguro="pendente = null"
    />
  </PerguntaDaFuncao>
</template>
