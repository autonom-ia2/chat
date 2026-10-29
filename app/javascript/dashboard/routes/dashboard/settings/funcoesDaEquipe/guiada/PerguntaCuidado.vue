<script setup>
import { computed, nextTick, ref } from 'vue';
import {
  LEVELS,
  moduleByKey,
  setLevel,
  toggleExtra,
} from '../../customRoles/permissionMatrix';
import { gruposDoCuidado } from '../areasDaFuncao';
import { dependenciaDe } from '../chavesDaFuncao';
import { TEXTO_DA_TRAVA } from '../motivoDaTrava';
import { chavesDoServidor } from '../semFuncao';
import { devolverFoco } from './focoQueFica';
import { useTextos } from './useTextos';
import DialogoDaCasa from './DialogoDaCasa.vue';
import InterruptorDaLinha from './InterruptorDaLinha.vue';
import LinhaRecolhida from './LinhaRecolhida.vue';
import PerguntaDaFuncao from './PerguntaDaFuncao.vue';

// Ações que pedem cuidado (#2308, especificação 5.B3 e 7.2), em três grupos: (b) liga junto com a área, com uma
// confirmação só ("Ligar as duas"/"Ligar os dois"); (a) liga agora; (c) recolhida com cadeado. As linhas ligáveis
// ficam na ordem fixa: ligar uma (b) não a tira do lugar. O que vem com "Cuida de tudo" fica ligado e travado, pela
// mesma leitura da prévia (chavesDoServidor: uma função antiga com crm_admin sem as seis gravadas); o alcance de quem
// dá conta as chaves gravadas, como o servidor (gruposDoCuidado, revisão do #2308, rodada 4). As metas do mês sem
// R$ também são (b): o diálogo pergunta pelos valores em R$. Desligar uma linha tira só a chave dela; o que entrou
// junto (a área, o R$) fica, e a faixa com "Desfazer" some (revisão do #2308, rodada 3).
const props = defineProps({
  permissions: { type: Array, required: true },
  inicial: { type: Array, required: true },
  giver: { type: Object, required: true },
  nome: { type: String, default: '' },
});

const emit = defineEmits(['update:permissions', 'pronto']);
const { t, lista, maiuscula, comAFuncao } = useTextos();

// Chave i18n do diálogo e da faixa de cada (b).
const JUNTO = {
  contact_delete: 'CONTATOS',
  campaign_send: 'CAMPANHAS',
  crm_metas_manage: 'METAS',
};

const ORDEM = [
  'contact_export',
  'conversation_message_delete',
  'crm_manage_ai',
  'crm_export',
  'crm_metas_manage',
  'contact_delete',
  'campaign_send',
];

const dialogo = ref(null);
const raiz = ref(null);
const pendente = ref(null);
// O último "Ligar as duas": o que ele acrescentou e o que tirou, para desfazer só isso.
const desfazer = ref(null);

const titulo = computed(() =>
  t('FUNCOES_EQUIPE.CUIDADO_TELA.TITULO', { com: comAFuncao(props.nome) })
);

const lidas = computed(() => chavesDoServidor(props.permissions));
const lidasAoAbrir = computed(() => chavesDoServidor(props.inicial));
const grupos = computed(() =>
  gruposDoCuidado(props.giver, props.permissions, lidas.value)
);
const ligaveis = computed(() => {
  const { ligaJunto, ligaAgora } = grupos.value;
  const junto = new Set(ligaJunto.map(item => item.chave));
  return [...ligaAgora, ...ligaJunto]
    .map(item => ({ ...item, junto: junto.has(item.chave) }))
    .sort((a, b) => ORDEM.indexOf(a.chave) - ORDEM.indexOf(b.chave));
});

const ligada = chave => lidas.value.includes(chave);
const algumaLigada = computed(() =>
  ligaveis.value.some(item => ligada(item.chave))
);
const mudou = chave => ligada(chave) !== lidasAoAbrir.value.includes(chave);

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

// A faixa "Agora…" vale enquanto o que o "Ligar as duas" acrescentou continua ligado: desligou, ela some.
const faixa = computed(() => {
  if (!desfazer.value) return '';
  const { chave, acrescentadas } = desfazer.value;
  if (!acrescentadas.every(item => props.permissions.includes(item))) return '';
  return t(`FUNCOES_EQUIPE.CUIDADO_TELA.JUNTO.${JUNTO[chave]}.AGORA`);
});

const atualizar = permissions => emit('update:permissions', permissions);

// "Ligar as duas": a área em manage e a chave, exatamente essas duas (especificação 7.7). As metas trazem o R$ pelo
// toggleExtra (KEY_DEPENDENCIES).
const ligarJunto = ({ chave, area }) => {
  const module = moduleByKey(area);
  const antes = props.permissions;
  const comArea = dependenciaDe(chave)
    ? antes
    : setLevel(module, LEVELS.MANAGE, antes);
  const depois = toggleExtra(module, chave, comArea);
  const acrescentadas = depois.filter(item => !antes.includes(item));
  atualizar(depois);
  desfazer.value = {
    chave,
    acrescentadas,
    tiradas: antes.filter(item => !depois.includes(item)),
  };
};

// Desligar tira só a chave da linha; o que entrou junto fica, e o "Desfazer" daquele "Ligar as duas" acaba.
const desligar = item => {
  desfazer.value = null;
  atualizar(toggleExtra(moduleByKey(item.area), item.chave, props.permissions));
};

// Uma linha que só aparece ligada some ao desligar: o foco vai para a primeira linha ou para o título.
const alternar = item => {
  if (ligada(item.chave)) {
    desligar(item);
    devolverFoco(raiz.value?.$el, ['[data-interruptor]', 'h1']);
    return;
  }
  if (item.junto) {
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

// Desfaz só o que o "Ligar as duas" mudou, sobre o estado de agora (delta inverso): o que a pessoa ligou depois fica.
// A especificação 7.7 diz "restaura o array anterior"; o delta inverso vem da revisão do #2308 (rodada 2), porque
// restaurar o array apagaria as mudanças feitas depois, e falta registrá-lo na especificação. O foco volta ao
// interruptor da linha (o botão "Desfazer" some).
const voltarAtras = async () => {
  const { chave, acrescentadas, tiradas } = desfazer.value;
  atualizar([
    ...props.permissions.filter(item => !acrescentadas.includes(item)),
    ...tiradas.filter(item => !props.permissions.includes(item)),
  ]);
  desfazer.value = null;
  await nextTick();
  document
    .querySelector(`[data-cuidado="${chave}"] [data-interruptor]`)
    ?.focus();
};

const textoDoDialogo = parte =>
  pendente.value
    ? t(
        `FUNCOES_EQUIPE.CUIDADO_TELA.JUNTO.${JUNTO[pendente.value.chave]}.${parte}`
      )
    : '';

const travaDaLinha = item =>
  item.preso ? t('FUNCOES_EQUIPE.VENDAS.VEM_COM_TUDO') : '';
</script>

<template>
  <PerguntaDaFuncao ref="raiz" :titulo="titulo" @pronto="emit('pronto')">
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

    <div role="status">
      <div
        v-if="faixa"
        data-faixa-junto
        class="flex items-center gap-3 px-4 py-3 border rounded-2xl border-n-blue-6 bg-n-blue-2"
      >
        <span
          class="i-lucide-info size-5 shrink-0 text-n-blue-11"
          aria-hidden="true"
        />
        <p class="flex-1 m-0 font-medium text-n-slate-12">{{ faixa }}</p>
        <button
          type="button"
          data-desfazer
          class="px-4 text-sm font-medium rounded-xl min-h-11 bg-n-alpha-2 text-n-slate-12 hover:bg-n-alpha-3 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="voltarAtras"
        >
          {{ $t('FUNCOES_EQUIPE.GUIADA.DESFAZER') }}
        </button>
      </div>
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
            ? $t(`FUNCOES_EQUIPE.CUIDADO_TELA.JUNTO.${JUNTO[item.chave]}.NOTA`)
            : ''
        "
        :trava="travaDaLinha(item)"
        :ligado="ligada(item.chave)"
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
