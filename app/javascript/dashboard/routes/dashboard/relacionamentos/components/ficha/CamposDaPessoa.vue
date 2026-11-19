<script setup>
import { computed, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import CampoDeTelefone from 'dashboard/components-next/conversa-canal/mais/CampoDeTelefone.vue';
import { REDES } from '../../ficha/informacoes';
import { opcoesDePais } from '../../ficha/paises';
import { useIdioma } from '../../ficha/idioma';
import CampoDeTexto from './CampoDeTexto.vue';
import CamposDaConta from './CamposDaConta.vue';
import EscolhaDaEmpresa from './EscolhaDaEmpresa.vue';
import FotoDaPessoa from './FotoDaPessoa.vue';

// #2894 — os campos da gaveta "Alterar informações". Não altera nada: cada
// mudança sobe por um evento e quem usa cria o formulário novo. As redes sociais
// ficam recolhidas atrás de um botão (rótulo na mesma margem dos campos; a seta
// vai depois do texto).
// #3075 — e o resto da ficha antiga: a foto (no topo), o país, a empresa
// cadastrada (com a chave `companies`; sem ela, o nome escrito, como antes),
// "Sobre a pessoa" e os campos personalizados com o controle do tipo de cada
// um. Os que aparecem na ficha (`campos` com `principal`) vêm primeiro; os
// outros ficam atrás de "Mais campos", que abre sozinho quando um deles tem
// erro. O nome escrito na busca da empresa e ainda não escolhido sobe como
// `mudar('empresaPendente', nome)`. #3078 — os campos da conta moram em
// CamposDaConta (a gaveta da empresa usa o mesmo).
const props = defineProps({
  formulario: { type: Object, required: true },
  // O formulário de quando a gaveta abriu: o que cada campo tinha.
  inicial: { type: Object, required: true },
  erros: { type: Object, default: () => ({}) },
  // A foto gravada hoje.
  fotoAtual: { type: String, default: '' },
  comEmpresas: { type: Boolean, default: false },
  buscarEmpresas: { type: Function, default: null },
  // Os campos personalizados (ficha/atributos.js#camposDaPessoa).
  campos: { type: Array, default: () => [] },
});
const emit = defineEmits([
  'mudar',
  'mudarRede',
  'mudarAtributo',
  'mudarEmpresa',
]);

const { t } = useI18n();
const idioma = useIdioma();
const redesAbertas = ref(false);
const idDasRedes = useId();
const idDoPais = useId();
const ra = chave => t(`RELACIONAMENTOS_FICHA.GAVETA.${chave}`);
const mensagem = campo => (campo ? ra(`ERRO.${campo}`) : '');

const CAMPOS_DE_TEXTO = [
  { campo: 'nome', rotulo: 'NOME', foco: true },
  { campo: 'email', rotulo: 'EMAIL', tipo: 'email' },
  { campo: 'cpf', rotulo: 'CPF', modo: 'numeric' },
  { campo: 'cidade', rotulo: 'CIDADE' },
];

const paises = computed(() =>
  opcoesDePais(idioma.value, ra('PAIS_NENHUM'), props.formulario.pais)
);
const empresaInicial = computed(() => ({
  id: props.inicial.empresaId,
  nome: props.inicial.empresa,
}));
const comEscolhaDeEmpresa = computed(
  () => props.comEmpresas && Boolean(props.buscarEmpresas)
);
const empresa = computed(() => ({
  id: props.formulario.empresaId,
  nome: props.formulario.empresa,
  nova: props.formulario.empresaNova,
}));
</script>

<template>
  <form class="flex flex-col gap-5" novalidate @submit.prevent>
    <FotoDaPessoa
      :nome="formulario.nome"
      :atual="fotoAtual"
      :foto="formulario.foto"
      @mudar="foto => emit('mudar', 'foto', foto)"
    />
    <template v-for="item in CAMPOS_DE_TEXTO" :key="item.campo">
      <CampoDeTexto
        :model-value="formulario[item.campo]"
        :rotulo="ra(item.rotulo)"
        :type="item.tipo || 'text'"
        :inputmode="item.modo"
        :data-foco="item.foco ? '' : undefined"
        :erro="mensagem(erros[item.campo])"
        @update:model-value="valor => emit('mudar', item.campo, valor)"
      />
      <CampoDeTelefone
        v-if="item.campo === 'nome'"
        :model-value="formulario.telefone"
        :label="ra('TELEFONE')"
        :rotulo-do-pais="ra('PAIS')"
        :erro="mensagem(erros.telefone)"
        @update:model-value="valor => emit('mudar', 'telefone', valor)"
      />
    </template>

    <div data-relacionamentos="pais-da-pessoa" class="flex flex-col min-w-0">
      <label :for="idDoPais" class="mb-1.5 text-heading-3 text-n-slate-12">
        {{ ra('PAIS_ONDE_MORA') }}
      </label>
      <ChoiceSelect
        :model-value="formulario.pais"
        :options="paises"
        :trigger-id="idDoPais"
        :aria-label="ra('PAIS_ONDE_MORA')"
        :placeholder="ra('PAIS_ESCOLHA')"
        class="w-full"
        @update:model-value="codigo => emit('mudar', 'pais', codigo)"
      />
    </div>

    <EscolhaDaEmpresa
      v-if="comEscolhaDeEmpresa"
      :empresa="empresa"
      :empresa-inicial="empresaInicial"
      :buscar="buscarEmpresas"
      :erro="mensagem(erros.empresa)"
      @mudar="escolhida => emit('mudarEmpresa', escolhida)"
      @pendente="nome => emit('mudar', 'empresaPendente', nome)"
    />
    <CampoDeTexto
      v-else
      :model-value="formulario.empresa"
      :rotulo="ra('EMPRESA')"
      @update:model-value="nome => emit('mudarEmpresa', { nome })"
    />

    <CampoDeTexto
      :model-value="formulario.sobre"
      :rotulo="ra('SOBRE')"
      :linhas="3"
      :placeholder="ra('SOBRE_EXEMPLO')"
      :ajuda="ra('SOBRE_AJUDA')"
      data-relacionamentos="sobre-a-pessoa"
      @update:model-value="texto => emit('mudar', 'sobre', texto)"
    />

    <div class="flex flex-col gap-4">
      <button
        type="button"
        data-relacionamentos="redes-sociais"
        :aria-expanded="redesAbertas ? 'true' : 'false'"
        :aria-controls="idDasRedes"
        class="inline-flex items-center gap-2 p-0 text-base font-medium bg-transparent border-0 text-start min-h-11 text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        @click="redesAbertas = !redesAbertas"
      >
        {{ ra('REDES') }}
        <span
          class="size-4 i-lucide-chevron-right rtl:rotate-180"
          :class="{ 'rotate-90 rtl:rotate-90': redesAbertas }"
          aria-hidden="true"
        />
      </button>
      <div v-show="redesAbertas" :id="idDasRedes" class="flex flex-col gap-4">
        <CampoDeTexto
          v-for="rede in REDES"
          :key="rede"
          :model-value="formulario.redes[rede]"
          :rotulo="ra(`REDE.${rede}`)"
          @update:model-value="valor => emit('mudarRede', rede, valor)"
        />
      </div>
    </div>

    <CamposDaConta
      v-if="campos.length"
      :campos="campos"
      :valores="formulario.atributos"
      :iniciais="inicial.atributos"
      :erros="erros"
      @mudar="(chave, valor) => emit('mudarAtributo', chave, valor)"
    />
  </form>
</template>
