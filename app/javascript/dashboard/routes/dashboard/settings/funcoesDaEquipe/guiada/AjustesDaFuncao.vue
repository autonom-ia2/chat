<script setup>
import { computed } from 'vue';
import {
  CONVERSATION_LEVELS,
  getLevel,
  moduleByKey,
} from '../../customRoles/permissionMatrix';
import {
  DONO_DAS_CHAVES,
  LINHAS,
  areasDaRecolhida,
  resumoDaRecolhida,
} from '../areasDaFuncao';
import { nivelDeVendas } from '../nivelDeVendas';
import { useTextos } from './useTextos';
import AreaEmLinha from './AreaEmLinha.vue';
import BotaoGrande from './BotaoGrande.vue';
import LinhaDaArea from './LinhaDaArea.vue';
import LinhaRecolhida from './LinhaRecolhida.vue';

// Ajustes (#2308, especificação 5.B2 e 7.1): quatro linhas com "Alterar", a recolhida com as outras áreas na ordem
// fixa (a mudada sobe e o título se refaz) e o cadeado de quem não é administrador.
const props = defineProps({
  titulo: { type: String, required: true },
  dica: { type: String, required: true },
  permissions: { type: Array, required: true },
  inicial: { type: Array, required: true },
  giver: { type: Object, required: true },
  comCotacoes: { type: Boolean, default: false },
});

const emit = defineEmits(['update:permissions', 'alterar', 'continuar']);
const { t, lista, maiuscula, minuscula, rotuloDoNivel } = useTextos();

const CONVERSAS_LIMITADAS = {
  'conversation_unassigned_manage conversation_participating_manage':
    'PROPRIAS_TUDO',
  conversation_unassigned_manage: 'PROPRIAS_NOVAS',
  conversation_participating_manage: 'PROPRIAS_AJUDA',
};
const CONVERSAS = {
  [CONVERSATION_LEVELS.NONE]: 'NENHUMA',
  [CONVERSATION_LEVELS.VIEW]: 'SO_OLHA',
  [CONVERSATION_LEVELS.ALL]: 'TODAS',
};
const VENDAS = {
  none: 'NAO_VE',
  view: 'SO_OLHA',
  manage: 'PODE_MEXER',
  tudo: 'TUDO',
};

const estadoDasConversas = permissions => {
  const nivel = getLevel(moduleByKey('CONVERSATIONS'), permissions);
  const escopo = [
    'conversation_unassigned_manage',
    'conversation_participating_manage',
  ]
    .filter(chave => permissions.includes(chave))
    .join(' ');
  const chave =
    nivel === CONVERSATION_LEVELS.LIMITED
      ? CONVERSAS_LIMITADAS[escopo]
      : CONVERSAS[nivel];
  return t(`FUNCOES_EQUIPE.AJUSTES.CONVERSAS.${chave}`);
};

const estadoDosContatos = permissions => {
  const contatos = moduleByKey('CONTACTS');
  return rotuloDoNivel(contatos, getLevel(contatos, permissions));
};

const estadoDasVendas = permissions =>
  t(`FUNCOES_EQUIPE.VENDAS.${VENDAS[nivelDeVendas(permissions)]}.ESTADO`);

// Metas sem R$ ficam inertes no servidor (decisão 14A): a linha não as promete. No "antes", a forma curta.
const estadoDoCuidado = (permissions, curto = false) => {
  const ligadas = DONO_DAS_CHAVES.CUIDADO.filter(
    chave =>
      permissions.includes(chave) &&
      (chave !== 'crm_metas_manage' || permissions.includes('sales_value_view'))
  );
  if (!ligadas.length)
    return curto
      ? t('FUNCOES_EQUIPE.AJUSTES.CUIDADO_NENHUMA_CURTO')
      : t('FUNCOES_EQUIPE.AJUSTES.CUIDADO_NENHUMA');
  return maiuscula(
    lista(ligadas.map(chave => t(`FUNCOES_EQUIPE.CUIDADO.${chave}`)))
  );
};

const linha = ({ pergunta, area, icone, tom, estado }) => {
  const agora = estado(props.permissions);
  const antes = estado(props.inicial, true);
  return {
    pergunta,
    icone,
    tom,
    titulo: t(`FUNCOES_EQUIPE.AREAS.${area}.NOME`),
    estado: agora,
    antes: agora === estado(props.inicial) ? '' : minuscula(antes),
  };
};

// As três linhas fixas (LINHAS do mapa) e o Cuidado.
const DAS_LINHAS = {
  CONVERSATIONS: {
    pergunta: 'conversas',
    icone: 'i-lucide-message-circle',
    tom: 'bg-n-blue-3 text-n-blue-11',
    estado: estadoDasConversas,
  },
  CONTACTS: {
    pergunta: 'contatos',
    icone: 'i-lucide-contact',
    tom: 'bg-n-teal-3 text-n-teal-11',
    estado: estadoDosContatos,
  },
  CRM: {
    pergunta: 'vendas',
    icone: 'i-lucide-kanban-square',
    tom: 'bg-n-iris-3 text-n-iris-11',
    estado: estadoDasVendas,
  },
};
const CUIDADO = {
  pergunta: 'cuidado',
  icone: 'i-lucide-triangle-alert',
  tom: 'bg-n-amber-3 text-n-amber-11',
  estado: estadoDoCuidado,
};

const linhas = computed(() =>
  [
    ...LINHAS.map(area => ({ ...DAS_LINHAS[area], area })),
    {
      ...CUIDADO,
      area: 'CUIDADO',
    },
  ].map(linha)
);

const areas = computed(() =>
  areasDaRecolhida({
    giver: props.giver,
    permissions: props.permissions,
    inicial: props.inicial,
    comCotacoes: props.comCotacoes,
  })
);
const resumo = computed(() =>
  resumoDaRecolhida(areas.value.recolhidas, props.permissions)
);

const nomes = keys => keys.map(key => t(`FUNCOES_EQUIPE.AREAS.${key}.NOME`));

// Título: as duas primeiras áreas mexíveis + "e mais N" (especificação 7.1).
const tituloDaRecolhida = computed(() => {
  const { primeiras, mais } = resumo.value;
  if (!mais) return lista(nomes(primeiras));
  return t(
    'FUNCOES_EQUIPE.AJUSTES.RECOLHIDA.TITULO',
    { areas: nomes(primeiras).join(', '), n: mais },
    mais
  );
});

// Estado curto: uma área só ganha o nome; mais de uma, a conta ("Mexe em 3 áreas e só olha 5.").
const contaDasAreas = () => {
  const { olha, mexe } = resumo.value;
  const nAreas = n => t('FUNCOES_EQUIPE.AJUSTES.RECOLHIDA.N_AREAS', { n }, n);
  if (olha.length + mexe.length === 1)
    return olha.length
      ? t('FUNCOES_EQUIPE.AJUSTES.RECOLHIDA.UMA_OLHA', {
          area: t(`FUNCOES_EQUIPE.AREAS.${olha[0]}.COM_ARTIGO`),
        })
      : t('FUNCOES_EQUIPE.AJUSTES.RECOLHIDA.UMA_MEXE', {
          area: nomes(mexe)[0],
        });
  if (!olha.length)
    return t('FUNCOES_EQUIPE.AJUSTES.RECOLHIDA.SO_MEXE', {
      mexe: nAreas(mexe.length),
    });
  if (!mexe.length)
    return t('FUNCOES_EQUIPE.AJUSTES.RECOLHIDA.SO_OLHA', {
      olha: nAreas(olha.length),
    });
  return t('FUNCOES_EQUIPE.AJUSTES.RECOLHIDA.MEXE_E_OLHA', {
    mexe: nAreas(mexe.length),
    olha: olha.length,
  });
};

const estadoDaRecolhida = computed(() => {
  const { olha, mexe } = resumo.value;
  if (!olha.length && !mexe.length)
    return t('FUNCOES_EQUIPE.AJUSTES.RECOLHIDA.NADA');
  const todas = olha.length + mexe.length === areas.value.recolhidas.length;
  return todas
    ? contaDasAreas()
    : `${contaDasAreas()} ${t('FUNCOES_EQUIPE.AJUSTES.RECOLHIDA.OUTRAS')}`;
});

const atualizar = permissions => emit('update:permissions', permissions);
</script>

<template>
  <div class="flex flex-col gap-5">
    <header class="flex flex-col gap-2">
      <h1
        class="m-0 text-2xl font-bold tracking-tight sm:text-3xl text-n-slate-12"
      >
        {{ titulo }}
      </h1>
      <p class="m-0 text-base text-n-slate-11">{{ dica }}</p>
    </header>

    <ul
      class="flex flex-col p-0 m-0 overflow-hidden list-none border divide-y rounded-2xl border-n-weak divide-n-weak bg-n-solid-1"
    >
      <LinhaDaArea
        v-for="item in linhas"
        :key="item.pergunta"
        :data-linha="item.pergunta"
        :icone="item.icone"
        :tom="item.tom"
        :titulo="item.titulo"
        :estado="item.estado"
        :antes="item.antes"
        @alterar="emit('alterar', item.pergunta)"
      />
      <li v-for="module in areas.subiram" :key="module.key">
        <AreaEmLinha
          :module="module"
          :permissions="permissions"
          :inicial="inicial"
          :giver="giver"
          @update:permissions="atualizar"
        />
      </li>
    </ul>

    <LinhaRecolhida
      v-if="areas.recolhidas.length || areas.cadeado.length"
      icone="i-lucide-layout-grid"
      :titulo="tituloDaRecolhida"
      :estado="estadoDaRecolhida"
    >
      <div class="flex flex-col divide-y divide-n-weak">
        <AreaEmLinha
          v-for="module in [...areas.recolhidas, ...areas.cadeado]"
          :key="module.key"
          :module="module"
          :permissions="permissions"
          :giver="giver"
          @update:permissions="atualizar"
        />
      </div>
    </LinhaRecolhida>

    <p class="flex items-center gap-2 m-0 text-sm text-n-slate-11">
      <span class="i-lucide-shield size-4 shrink-0" aria-hidden="true" />
      {{ $t('FUNCOES_EQUIPE.AJUSTES.SO_DO_ADMIN') }}
    </p>

    <BotaoGrande
      :label="$t('FUNCOES_EQUIPE.GUIADA.CONTINUAR')"
      @click="emit('continuar')"
    />
  </div>
</template>
