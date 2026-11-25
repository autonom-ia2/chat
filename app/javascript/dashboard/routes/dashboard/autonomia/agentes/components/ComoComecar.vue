<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ModeloCartao from './ModeloCartao.vue';
import RamosProntos from './RamosProntos.vue';
import OpcaoDeComeco from './OpcaoDeComeco.vue';
import AgenteErro from './AgenteErro.vue';
import AvisoSemCanal from './AvisoSemCanal.vue';
import { MODELOS } from '../constants/modelos';
import { OPCOES_DE_COMECO, PAPEL } from '../constants/papeis';

// #3219 — passo 2, dentro do herói navy: "Como você quer começar?".
// Atender clientes, sem ramos: os três modelos com o celular de exemplo são o principal; "Conversar com a IA" e
// "Escrever eu mesmo" ficam embaixo, discretos. Com ramos (conta de seguros): os ramos são o principal, e os três
// modelos gerais viram linhas compactas na mesma seção de baixo ("Não achou o seu seguro?"), junto dos dois jeitos.
// No Copiloto não há pronto: os dois jeitos lado a lado, do mesmo tamanho, e "Conversar" é o recomendado.
// `semCanal`: a conta ainda não tem canal; o aviso fica embaixo dos prontos (só atender clientes precisa de canal).
// `comecando`: a chave (ramo, modelo ou jeito) que a pessoa acabou de escolher, ou null; trava os outros.
// `falhou`: true quando a última escolha não abriu; o aviso fica no topo, com "Tentar de novo".
const props = defineProps({
  papel: { type: String, required: true },
  ramos: { type: Array, default: () => [] },
  podeUsar: { type: Boolean, default: false },
  comecando: { type: String, default: null },
  falhou: { type: Boolean, default: false },
  semCanal: { type: Boolean, default: false },
});

const emit = defineEmits([
  'usarRamo',
  'usarModelo',
  'usarOpcao',
  'tentarDeNovo',
]);

const { t } = useI18n();
const NS = 'AGENTS.JORNADA.CRIAR_EM_PASSOS.COMO';
const atender = computed(() => props.papel === PAPEL.ATENDER);
const comRamos = computed(() => atender.value && props.ramos.length > 0);
const bloqueado = chave => !!props.comecando && props.comecando !== chave;
const MODELOS_EM_LINHA = MODELOS.map(modelo => ({
  chave: modelo.chave,
  icone: modelo.icone,
  base: `AGENTS.JORNADA.MODELOS.${modelo.i18n}`,
}));
</script>

<template>
  <div data-como-comecar class="flex flex-col gap-6">
    <AgenteErro
      v-if="falhou"
      data-erro-ao-comecar
      :titulo="t(`${NS}.ERRO`)"
      :acao="t('AGENTS.JORNADA.COMUM.TENTAR_DE_NOVO')"
      :carregando="!!comecando"
      @acao="emit('tentarDeNovo')"
    />

    <template v-if="comRamos">
      <RamosProntos
        :ramos="ramos"
        :pode-usar="podeUsar"
        :comecando="comecando"
        @usar="chave => emit('usarRamo', chave)"
      />
      <AvisoSemCanal v-if="semCanal" />
      <section
        v-if="podeUsar"
        aria-labelledby="outro-jeito-titulo"
        class="flex flex-col gap-3 pt-6 border-t border-white/15"
      >
        <h2
          id="outro-jeito-titulo"
          class="m-0 text-xl font-semibold text-white"
        >
          {{ t(`${NS}.OUTRO_JEITO`) }}
        </h2>
        <ul
          :aria-label="t('AGENTS.JORNADA.MODELOS.ROTULO')"
          class="grid grid-cols-1 gap-3 p-0 m-0 list-none md:grid-cols-3"
        >
          <OpcaoDeComeco
            v-for="modelo in MODELOS_EM_LINHA"
            :key="modelo.chave"
            :opcao="modelo"
            variante="linha"
            :pode-usar="podeUsar"
            :comecando="comecando === modelo.chave"
            :bloqueado="bloqueado(modelo.chave)"
            @usar="chave => emit('usarModelo', chave)"
          />
        </ul>
        <ul class="grid grid-cols-1 gap-3 p-0 m-0 list-none md:grid-cols-2">
          <OpcaoDeComeco
            v-for="opcao in OPCOES_DE_COMECO"
            :key="opcao.chave"
            :opcao="opcao"
            variante="linha"
            :pode-usar="podeUsar"
            :comecando="comecando === opcao.chave"
            :bloqueado="bloqueado(opcao.chave)"
            @usar="chave => emit('usarOpcao', chave)"
          />
        </ul>
      </section>
    </template>

    <template v-else-if="atender">
      <ul
        :aria-label="t('AGENTS.JORNADA.MODELOS.ROTULO')"
        class="grid grid-cols-1 gap-4 p-0 m-0 list-none md:grid-cols-3"
      >
        <ModeloCartao
          v-for="modelo in MODELOS"
          :key="modelo.chave"
          :modelo="modelo"
          :pode-usar="podeUsar"
          :comecando="comecando === modelo.chave"
          :bloqueado="bloqueado(modelo.chave)"
          @usar="chave => emit('usarModelo', chave)"
        />
      </ul>
      <AvisoSemCanal v-if="semCanal" />
      <section
        v-if="podeUsar"
        aria-labelledby="do-zero-titulo"
        class="flex flex-col gap-3 pt-6 border-t border-white/15"
      >
        <h2 id="do-zero-titulo" class="m-0 text-xl font-semibold text-white">
          {{ t(`${NS}.DO_ZERO`) }}
        </h2>
        <ul class="grid grid-cols-1 gap-3 p-0 m-0 list-none md:grid-cols-2">
          <OpcaoDeComeco
            v-for="opcao in OPCOES_DE_COMECO"
            :key="opcao.chave"
            :opcao="opcao"
            variante="linha"
            :pode-usar="podeUsar"
            :comecando="comecando === opcao.chave"
            :bloqueado="bloqueado(opcao.chave)"
            @usar="chave => emit('usarOpcao', chave)"
          />
        </ul>
      </section>
    </template>

    <ul
      v-else
      :aria-label="t(`${NS}.OPCOES`)"
      class="grid grid-cols-1 gap-4 p-0 m-0 list-none md:grid-cols-2"
    >
      <OpcaoDeComeco
        v-for="(opcao, indice) in OPCOES_DE_COMECO"
        :key="opcao.chave"
        :opcao="opcao"
        :principal="indice === 0"
        :pode-usar="podeUsar"
        :comecando="comecando === opcao.chave"
        :bloqueado="bloqueado(opcao.chave)"
        @usar="chave => emit('usarOpcao', chave)"
      />
    </ul>
  </div>
</template>
