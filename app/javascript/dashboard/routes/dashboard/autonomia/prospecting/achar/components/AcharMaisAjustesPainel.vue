<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import AudienceListSwitch from 'dashboard/components-next/CampaignJourney/AudienceListSwitch.vue';
import AcharPainel from './AcharPainel.vue';
import AcharEscolhaCartao from './AcharEscolhaCartao.vue';

// #2692 — T0a, painel "Mais ajustes" (v4), por cima de "Como procurar". Seções
// recolhíveis, todas fechadas. Na demonstração, "Nota no Google" já abre.
// Fora deste protótipo: o mapa de "Desenhar a área" e "Salvar como modelo".
// Rodada 4: "Limpar ajustes" sobe para o lado do título e o rodapé tem
// "Cancelar". Rodada 5: "Quem vem primeiro" voltou para cá (decisão do
// Rodrigo: a presença fraca nunca no caminho principal).
// D4 (crítica r5): uma saída só no topo (a seta), cada ajuste já mostra a
// escolha (sem abrir e fechar), "Limpar ajustes" é um link no fim da lista e
// o rodapé diz "Pronto" (a raiz é que diz "Usar esta escolha").
// O rascunho começa pelo que já estava escolhido (`ajustes`): reabrir o painel
// e tocar "Pronto" não apaga nada (revisão 2 da F1).
const props = defineProps({
  primeiro: { type: String, default: 'melhores' },
  ajustes: { type: Object, default: null },
});
const emit = defineEmits(['aplicar', 'close']);

const { t } = useI18n();
const NS = 'PROSPECTING_ACHAR.MAIS_AJUSTES';

const VAZIO = {
  nota: 'qualquer',
  avaliacoes: 'qualquer',
  site: 'tanto',
  fotos: 'tanto',
  aberta: false,
  mostraHorario: false,
  primeiro: 'melhores',
};
const rascunho = ref({
  ...VAZIO,
  ...(props.ajustes || {}),
  primeiro: props.primeiro,
});

const mudar = (campo, valor) => {
  rascunho.value = { ...rascunho.value, [campo]: valor };
};

const opcoes = (prefixo, chaves) =>
  chaves.map(chave => ({
    value: chave.toLowerCase(),
    label: t(`${NS}.${prefixo}.${chave}`),
  }));
const NOTAS = computed(() =>
  opcoes('NOTA', ['QUALQUER', 'N3', 'N4', 'N45', 'ABAIXO_4'])
);
const AVALIACOES = computed(() =>
  opcoes('AVALIACOES', ['QUALQUER', 'N10', 'N20', 'N50'])
);
const TEM_OU_NAO = [
  { id: 'tanto', chave: 'TANTO_FAZ' },
  { id: 'tem', chave: 'TEM' },
  { id: 'nao', chave: 'NAO_TEM' },
];
const SECOES = ['nota', 'avaliacoes', 'site', 'fotos', 'horario', 'primeiro'];
const TITULOS = {
  nota: `${NS}.NOTA.TITULO`,
  avaliacoes: `${NS}.AVALIACOES.TITULO`,
  site: `${NS}.SITE`,
  fotos: `${NS}.FOTOS`,
  horario: `${NS}.HORARIO.TITULO`,
  primeiro: `${NS}.PRIMEIRO.TITULO`,
};
</script>

<template>
  <AcharPainel :titulo="$t(`${NS}.TITULO`)" voltar @close="emit('close')">
    <section
      v-for="secao in SECOES"
      :key="secao"
      class="flex flex-col gap-3 pb-5 border-b border-n-weak"
      :data-secao="secao"
    >
      <h3 class="m-0 text-base font-semibold text-n-slate-12">
        {{ $t(TITULOS[secao]) }}
      </h3>
      <ChoiceSelect
        v-if="secao === 'nota'"
        :model-value="rascunho.nota"
        :options="NOTAS"
        :aria-label="$t(TITULOS.nota)"
        @update:model-value="mudar('nota', $event)"
      />
      <ChoiceSelect
        v-else-if="secao === 'avaliacoes'"
        :model-value="rascunho.avaliacoes"
        :options="AVALIACOES"
        :aria-label="$t(TITULOS.avaliacoes)"
        @update:model-value="mudar('avaliacoes', $event)"
      />
      <div
        v-else-if="secao === 'site' || secao === 'fotos'"
        role="radiogroup"
        class="grid grid-cols-3 gap-2"
      >
        <AcharEscolhaCartao
          v-for="opcao in TEM_OU_NAO"
          :key="opcao.id"
          :titulo="$t(`${NS}.${opcao.chave}`)"
          :escolhido="rascunho[secao] === opcao.id"
          @escolher="mudar(secao, opcao.id)"
        />
      </div>
      <div
        v-else-if="secao === 'primeiro'"
        role="radiogroup"
        class="grid gap-3"
        data-quem-primeiro
      >
        <AcharEscolhaCartao
          :titulo="$t(`${NS}.PRIMEIRO.MELHORES`)"
          :escolhido="rascunho.primeiro === 'melhores'"
          @escolher="mudar('primeiro', 'melhores')"
        />
        <AcharEscolhaCartao
          :titulo="$t(`${NS}.PRIMEIRO.POUCO`)"
          :texto="$t(`${NS}.PRIMEIRO.POUCO_TEXTO`)"
          :escolhido="rascunho.primeiro === 'pouco'"
          @escolher="mudar('primeiro', 'pouco')"
        />
      </div>
      <template v-else>
        <div class="flex items-center justify-between gap-3">
          <span class="text-base text-n-slate-12">
            {{ $t(`${NS}.HORARIO.ABERTA`) }}
          </span>
          <AudienceListSwitch
            :on="rascunho.aberta"
            :label="$t(`${NS}.HORARIO.ABERTA`)"
            @toggle="mudar('aberta', !rascunho.aberta)"
          />
        </div>
        <div class="flex items-center justify-between gap-3">
          <span class="text-base text-n-slate-12">
            {{ $t(`${NS}.HORARIO.MOSTRA`) }}
          </span>
          <AudienceListSwitch
            :on="rascunho.mostraHorario"
            :label="$t(`${NS}.HORARIO.MOSTRA`)"
            @toggle="mudar('mostraHorario', !rascunho.mostraHorario)"
          />
        </div>
      </template>
    </section>
    <Button
      :label="$t(`${NS}.LIMPAR`)"
      variant="link"
      class="self-start !min-h-11 !px-0"
      data-limpar
      @click="rascunho = { ...VAZIO }"
    />
    <template #rodape>
      <Button
        :label="$t('PROSPECTING_ACHAR.COMUM.PRONTO')"
        class="!min-h-12 !rounded-xl !text-base"
        data-aplicar
        @click="emit('aplicar', rascunho)"
      />
    </template>
  </AcharPainel>
</template>
