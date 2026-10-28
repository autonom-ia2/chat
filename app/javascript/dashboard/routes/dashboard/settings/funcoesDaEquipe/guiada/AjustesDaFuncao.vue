<script setup>
import { computed, ref } from 'vue';
import {
  CONVERSATION_LEVELS,
  LEVELS,
  getLevel,
  moduleByKey,
} from '../../customRoles/permissionMatrix';
import {
  DONO_DAS_CHAVES,
  LINHAS,
  areasDaRecolhida,
  resumoDaRecolhida,
} from '../areasDaFuncao';
import { ALCANCES_DE_CONVERSA } from '../chavesDaFuncao';
import { soOlhaNaArea } from '../fraseDaFuncao';
import { nivelDeVendas } from '../nivelDeVendas';
import { chavesEfetivas } from '../semFuncao';
import { devolverFoco } from './focoQueFica';
import { useTextos } from './useTextos';
import AreaEmLinha from './AreaEmLinha.vue';
import BotaoGrande from './BotaoGrande.vue';
import LinhaDaArea from './LinhaDaArea.vue';
import LinhaRecolhida from './LinhaRecolhida.vue';

// Ajustes (#2308, especificação 5.B2 e 7.1): quatro linhas com "Alterar", a recolhida com as outras áreas na ordem
// fixa (a mudada sobe e o título se refaz) e o cadeado de quem não é administrador. A área que sobe (ou volta) é
// montada de novo em outro lugar: o foco vai junto, para o nível escolhido dela.
const props = defineProps({
  titulo: { type: String, required: true },
  dica: { type: String, required: true },
  permissions: { type: Array, required: true },
  inicial: { type: Array, required: true },
  giver: { type: Object, required: true },
  comCotacoes: { type: Boolean, default: false },
});

const emit = defineEmits(['update:permissions', 'alterar', 'continuar']);
const { t, lista, maiuscula, minuscula, rotuloDoNivel, antesDoNivel } =
  useTextos();
const raiz = ref(null);

const [NOVAS, AJUDA] = ALCANCES_DE_CONVERSA;
const CONVERSAS_LIMITADAS = {
  [`${NOVAS} ${AJUDA}`]: 'PROPRIAS_TUDO',
  [NOVAS]: 'PROPRIAS_NOVAS',
  [AJUDA]: 'PROPRIAS_AJUDA',
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

// No nível de ver, "Só olha" só quando nada muda na área (soOlhaNaArea, a regra da frase e da Perda de acesso); senão
// "Vê" ("antes: via").
const veSemSoOlhar = (area, nivel, permissions) =>
  nivel === LEVELS.VIEW && !soOlhaNaArea(area, permissions);
const textoDeVer = antes =>
  t(`FUNCOES_EQUIPE.GUIADA.${antes ? 'ANTES' : 'NIVEL'}.VE`);

// O "antes" fala sempre no passado e na forma curta ("antes: atendia só as próprias", "antes: só olhava"), como a
// recolhida e a especificação 5.B2.
const estadoDasConversas = (permissions, antes = false) => {
  const nivel = getLevel(moduleByKey('CONVERSATIONS'), permissions);
  const limitado = nivel === CONVERSATION_LEVELS.LIMITED;
  if (veSemSoOlhar('CONVERSATIONS', nivel, permissions))
    return textoDeVer(antes);
  if (antes)
    return t(
      `FUNCOES_EQUIPE.AJUSTES.ANTES.CONVERSAS.${limitado ? 'PROPRIAS' : CONVERSAS[nivel]}`
    );
  if (!limitado)
    return t(`FUNCOES_EQUIPE.AJUSTES.CONVERSAS.${CONVERSAS[nivel]}`);
  const escopo = ALCANCES_DE_CONVERSA.filter(chave =>
    permissions.includes(chave)
  ).join(' ');
  return t(`FUNCOES_EQUIPE.AJUSTES.CONVERSAS.${CONVERSAS_LIMITADAS[escopo]}`);
};

const estadoDosContatos = (permissions, antes = false) => {
  const contatos = moduleByKey('CONTACTS');
  const nivel = getLevel(contatos, permissions);
  return antes
    ? antesDoNivel(contatos, nivel, permissions)
    : rotuloDoNivel(contatos, nivel, permissions);
};

const estadoDasVendas = (permissions, antes = false) => {
  if (veSemSoOlhar('CRM', nivelDeVendas(permissions), permissions))
    return textoDeVer(antes);
  const nivel = VENDAS[nivelDeVendas(permissions)];
  return antes
    ? t(`FUNCOES_EQUIPE.AJUSTES.ANTES.VENDAS.${nivel}`)
    : t(`FUNCOES_EQUIPE.VENDAS.${nivel}.ESTADO`);
};

// O que a função dá de fato (chavesEfetivas, a mesma leitura da prévia e do Cuidado): metas sem R$ ficam inertes no
// servidor (especificação 7.5) e a linha não as promete; uma função antiga com crm_admin sem as seis gravadas mostra o
// que ele dá. No "antes", a forma curta.
const estadoDoCuidado = (permissions, curto = false) => {
  const efetivas = chavesEfetivas(permissions);
  const ligadas = DONO_DAS_CHAVES.CUIDADO.filter(chave =>
    efetivas.includes(chave)
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

// Estado curto: uma área só ganha o nome; até duas de um lado, os nomes ("Mexe em Etiquetas e Canais"); mais, a conta
// ("Mexe em 3 áreas e só olha outras 5."), sem o lado que é zero. "Só olha" só quando nenhuma das que estão no nível de
// ver ainda muda algo (soOlhaNaArea: os relatórios de atendimento também escrevem a nota da avaliação); senão "vê".
const ATE_DUAS = 2;
const DE_VER = {
  soOlha: {
    UMA: 'UMA_OLHA',
    SO: 'SO_OLHA',
    NOMES: 'MEXE_E_OLHA_NOMES',
    CONTA: 'MEXE_E_OLHA',
  },
  ve: { UMA: 'UMA_VE', SO: 'VE', NOMES: 'MEXE_E_VE_NOMES', CONTA: 'MEXE_E_VE' },
};
const contaDasAreas = () => {
  const { olha, mexe } = resumo.value;
  const soOlhando = olha.every(area => soOlhaNaArea(area, props.permissions));
  const deVer = DE_VER[soOlhando ? 'soOlha' : 've'];
  const nAreas = n => t('FUNCOES_EQUIPE.AJUSTES.RECOLHIDA.N_AREAS', { n }, n);
  const areasOuConta = keys =>
    keys.length <= ATE_DUAS ? lista(nomes(keys)) : nAreas(keys.length);
  if (olha.length + mexe.length === 1)
    return olha.length
      ? t(`FUNCOES_EQUIPE.AJUSTES.RECOLHIDA.${deVer.UMA}`, {
          area: t(`FUNCOES_EQUIPE.AREAS.${olha[0]}.NA_FRASE`),
        })
      : t('FUNCOES_EQUIPE.AJUSTES.RECOLHIDA.UMA_MEXE', {
          area: nomes(mexe)[0],
        });
  if (!olha.length)
    return t('FUNCOES_EQUIPE.AJUSTES.RECOLHIDA.SO_MEXE', {
      mexe: areasOuConta(mexe),
    });
  if (!mexe.length)
    return t(`FUNCOES_EQUIPE.AJUSTES.RECOLHIDA.${deVer.SO}`, {
      olha: areasOuConta(olha),
    });
  if (olha.length <= ATE_DUAS)
    return t(`FUNCOES_EQUIPE.AJUSTES.RECOLHIDA.${deVer.NOMES}`, {
      mexe: areasOuConta(mexe),
      olha: lista(nomes(olha)),
    });
  return t(
    `FUNCOES_EQUIPE.AJUSTES.RECOLHIDA.${deVer.CONTA}`,
    { mexe: areasOuConta(mexe), olha: olha.length },
    olha.length
  );
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

// A área mexida pode subir da recolhida (ou voltar para ela): o foco segue para o nível escolhido dela.
const atualizar = permissions => {
  const area = document.activeElement?.closest?.('[data-area]')?.dataset.area;
  emit('update:permissions', permissions);
  if (!area) return;
  devolverFoco(raiz.value, [
    `[data-area="${area}"] [role="radio"][aria-checked="true"]`,
    'h1',
  ]);
};
</script>

<template>
  <div ref="raiz" class="flex flex-col gap-5">
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
