<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import SidePanel from 'dashboard/components-next/side-panel/SidePanel.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import {
  ACOES_DA_PLATAFORMA,
  GRUPOS,
  TIPOS_DE_PASSO,
} from '../prototipo/catalogo';
import { dinheiro } from '../prototipo/frases';

// #2414 F0 — o "+" entre dois passos abre este seletor: os passos por grupo
// (o custo da IA ao lado; o selo quando manda para o cliente) e, no fim, "Todas
// as ações da plataforma", com busca por frase.
const emit = defineEmits(['escolher', 'close']);

const { t } = useI18n();
const painel = ref(null);
const busca = ref('');

const grupos = computed(() =>
  GRUPOS.map(grupo => ({
    ...grupo,
    tipos: Object.entries(TIPOS_DE_PASSO)
      .filter(([, tipo]) => tipo.grupo === grupo.chave)
      .map(([chave, tipo]) => ({ chave, ...tipo })),
  }))
);

// Compara sem acento e sem maiúscula: "orcamento" acha "Orçamento".
const MARCAS_DE_ACENTO = [0x300, 0x36f];
const simples = texto =>
  Array.from((texto || '').normalize('NFD'))
    .filter(letra => {
      const codigo = letra.codePointAt(0);
      return codigo < MARCAS_DE_ACENTO[0] || codigo > MARCAS_DE_ACENTO[1];
    })
    .join('')
    .toLowerCase();

const fraseDaAcao = acao =>
  acao.semFrase
    ? t('AUTOMACAO_LIVRE.PLATAFORMA.AVANCADA')
    : t(`AUTOMACAO_LIVRE.PLATAFORMA.${acao.chave}`);

const acoes = computed(() => {
  const palavras = simples(busca.value).split(' ').filter(Boolean);
  return ACOES_DA_PLATAFORMA.map(acao => ({
    ...acao,
    frase: fraseDaAcao(acao),
  })).filter(acao =>
    palavras.every(palavra => simples(acao.frase).includes(palavra))
  );
});

const escolherTipo = tipo => emit('escolher', { tipo });
const escolherAcao = acao =>
  emit('escolher', { tipo: 'acao_plataforma', acao: acao.chave });

const open = () => {
  busca.value = '';
  painel.value?.open();
};
const close = () => painel.value?.close();

defineExpose({ open, close });
</script>

<template>
  <SidePanel
    ref="painel"
    :title="$t('AUTOMACAO_LIVRE.SELETOR.TITULO')"
    :description="$t('AUTOMACAO_LIVRE.SELETOR.TEXTO')"
    width="lg"
    @close="emit('close')"
  >
    <div data-seletor class="flex flex-col gap-6">
      <section
        v-for="grupo in grupos"
        :key="grupo.chave"
        :data-grupo="grupo.chave"
        class="flex flex-col gap-2"
      >
        <h4
          class="flex items-center gap-2 mb-0 text-sm font-semibold text-n-slate-11"
        >
          <span class="size-4" :class="grupo.icone" aria-hidden="true" />
          {{ $t(`AUTOMACAO_LIVRE.GRUPOS.${grupo.chave}`) }}
        </h4>
        <ul class="flex flex-col gap-1.5 p-0 m-0 list-none">
          <li v-for="tipo in grupo.tipos" :key="tipo.chave">
            <button
              type="button"
              :data-tipo="tipo.chave"
              class="flex items-center w-full gap-3 px-3 py-2 border text-start rounded-xl min-h-11 border-n-weak bg-n-solid-1 hover:border-n-blue-7 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
              @click="escolherTipo(tipo.chave)"
            >
              <span
                class="size-5 text-n-slate-11"
                :class="tipo.icone"
                aria-hidden="true"
              />
              <span class="flex-1 text-[0.9375rem] text-n-slate-12">
                {{
                  $t(
                    `AUTOMACAO_LIVRE.SELETOR.TIPOS.${tipo.chave.toUpperCase()}`
                  )
                }}
              </span>
              <span
                v-if="tipo.custo"
                class="text-xs font-medium whitespace-nowrap text-n-iris-11"
              >
                {{
                  $t('AUTOMACAO_LIVRE.CUSTO', { custo: dinheiro(tipo.custo) })
                }}
              </span>
              <span
                v-if="tipo.semVolta"
                class="i-lucide-send size-4 text-n-amber-11"
                :title="$t('AUTOMACAO_LIVRE.SELO_SEM_VOLTA')"
                :aria-label="$t('AUTOMACAO_LIVRE.SELO_SEM_VOLTA')"
                role="img"
              />
            </button>
          </li>
        </ul>
      </section>

      <section data-grupo="PLATAFORMA" class="flex flex-col gap-2">
        <h4
          class="flex items-center gap-2 mb-0 text-sm font-semibold text-n-slate-11"
        >
          <span class="i-lucide-blocks size-4" aria-hidden="true" />
          {{ $t('AUTOMACAO_LIVRE.GRUPOS.PLATAFORMA') }}
        </h4>
        <Input
          v-model="busca"
          data-busca
          :label="$t('AUTOMACAO_LIVRE.SELETOR.BUSCA_ROTULO')"
          :placeholder="$t('AUTOMACAO_LIVRE.SELETOR.BUSCA')"
        />
        <p v-if="!acoes.length" class="mb-0 text-sm text-n-slate-11">
          {{ $t('AUTOMACAO_LIVRE.SELETOR.NADA') }}
        </p>
        <ul class="flex flex-col gap-1.5 p-0 m-0 list-none">
          <li v-for="acao in acoes" :key="acao.chave">
            <button
              type="button"
              :data-acao="acao.chave"
              class="flex items-center w-full gap-3 px-3 py-2 border text-start rounded-xl min-h-11 border-n-weak bg-n-solid-1 hover:border-n-blue-7 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
              @click="escolherAcao(acao)"
            >
              <span class="flex-1 text-[0.9375rem] text-n-slate-12">
                {{ acao.frase }}
              </span>
              <span
                v-if="acao.semVolta"
                class="i-lucide-send size-4 text-n-amber-11"
                :title="$t('AUTOMACAO_LIVRE.SELO_SEM_VOLTA')"
                :aria-label="$t('AUTOMACAO_LIVRE.SELO_SEM_VOLTA')"
                role="img"
              />
            </button>
          </li>
        </ul>
      </section>
    </div>
  </SidePanel>
</template>
