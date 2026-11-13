<script setup>
import { nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import AgenteBotao from '../AgenteBotao.vue';
import { chaveDoTexto, ferramentaPorId } from '../../vitrine/catalogo';
import { MAXIMO_DE_LETRAS_DO_QUANDO } from '../../constants/modelosDeRamo';

// #2881 — as ferramentas prontas de um agente pronto por ramo. Cada uma mostra QUANDO o agente usa: a frase "Use
// quando…" já vem escrita para o ramo (ex.: no seguro garantia, o CNPJ é o da empresa que contrata), e o dono pode
// alterar. É a frase que vai junto quando a ferramenta entra no agente, no "Começar": o agente decide pelo sentido da
// conversa. Nada de lista de palavras.
// ferramentas ("Já vem com") e tambem ("Também combina"): [{ fonte, usar_quando }], com a chave do catálogo da
// vitrine. Cada mudança sai daqui como o "Já vem com" inteiro novo (`mudar`); quem chama grava e devolve as duas
// listas do servidor (a ferramenta tirada volta no "Também combina").
// pagas: chaves das consultas pagas que combinam. Só sugestão: quem inclui é a pessoa, na vitrine.
// `podeMudar` falso (a pessoa não cuida das ferramentas dos agentes): as ferramentas e as frases aparecem, sem botões.
const props = defineProps({
  nome: { type: String, required: true },
  ferramentas: { type: Array, required: true },
  tambem: { type: Array, default: () => [] },
  pagas: { type: Array, default: () => [] },
  linkDaVitrine: { type: String, default: '' },
  podeMudar: { type: Boolean, default: false },
  gravando: { type: Boolean, default: false },
});

const emit = defineEmits(['mudar']);

const { t, locale } = useI18n();
const NS = 'AGENTS.JORNADA.RAMOS.CONFIRA';

const nomeDa = fonte =>
  t(`AGENTS.VITRINE.FERRAMENTAS.${chaveDoTexto(fonte)}.NOME`);
const iconeDa = fonte => ferramentaPorId(fonte)?.icone || 'i-lucide-wrench';
const emFrase = fontes =>
  new Intl.ListFormat(String(locale.value).replace('_', '-'), {
    type: 'conjunction',
  }).format(fontes.map(nomeDa));
const nomesDoTambem = () => emFrase(props.tambem.map(item => item.fonte));

const alterando = ref(null);
const rascunho = ref('');
const lista = ref(null);

const alterar = item => {
  alterando.value = item.fonte;
  rascunho.value = item.usar_quando;
};
const salvar = () => {
  const frase = rascunho.value.trim();
  if (!frase) return;
  emit(
    'mudar',
    props.ferramentas.map(item =>
      item.fonte === alterando.value ? { ...item, usar_quando: frase } : item
    )
  );
  alterando.value = null;
};
const tirar = fonte =>
  emit(
    'mudar',
    props.ferramentas.filter(item => item.fonte !== fonte)
  );
const incluirTambem = () =>
  emit('mudar', [...props.ferramentas, ...props.tambem]);

// O "também combina" some quando as ferramentas entram: o foco vai para a lista, e não para o vazio.
watch(
  () => props.tambem.length,
  async (agora, antes) => {
    if (!antes || agora) return;
    await nextTick();
    lista.value?.focus();
  }
);
</script>

<template>
  <div data-ferramentas-do-ramo class="flex flex-col gap-4">
    <p class="m-0 text-sm leading-relaxed text-n-slate-11">
      {{ t(`${NS}.FERRAMENTAS_NOTA`, { nome }) }}
      <span v-if="podeMudar" data-pode-alterar>
        {{ t(`${NS}.FERRAMENTAS_PODE_ALTERAR`) }}
      </span>
    </p>
    <ul
      ref="lista"
      tabindex="-1"
      :aria-label="t(`${NS}.FERRAMENTAS_TITULO`, { nome })"
      :aria-busy="gravando ? 'true' : undefined"
      class="flex flex-col gap-2 p-0 m-0 list-none focus:outline-none"
    >
      <li
        v-for="item in ferramentas"
        :key="item.fonte"
        :data-ferramenta="item.fonte"
        class="flex items-start gap-3 p-3 rounded-xl bg-n-solid-1 ring-1 ring-inset ring-n-weak"
      >
        <span
          aria-hidden="true"
          class="grid rounded-xl place-items-center size-10 shrink-0 bg-n-blue-3 text-n-blue-11"
        >
          <span class="size-5" :class="iconeDa(item.fonte)" />
        </span>
        <div class="flex flex-col flex-1 min-w-0 gap-1">
          <span class="text-base font-semibold text-n-slate-12">
            {{ nomeDa(item.fonte) }}
          </span>
          <div
            v-if="alterando === item.fonte"
            data-alterando
            class="flex flex-col gap-2"
          >
            <TextArea
              v-model="rascunho"
              auto-height
              autofocus
              :max-length="MAXIMO_DE_LETRAS_DO_QUANDO"
              show-character-count
            />
            <div class="flex flex-wrap gap-2">
              <AgenteBotao
                data-salvar-quando
                :inativo="!rascunho.trim() || gravando"
                @click="salvar"
              >
                {{ t(`${NS}.SALVAR`) }}
              </AgenteBotao>
              <AgenteBotao variante="fantasma" @click="alterando = null">
                {{ t(`${NS}.CANCELAR`) }}
              </AgenteBotao>
            </div>
          </div>
          <template v-else>
            <span data-quando class="text-sm leading-relaxed text-n-slate-11">
              {{ item.usar_quando }}
            </span>
            <div v-if="podeMudar" class="flex flex-wrap gap-1 -ms-3">
              <AgenteBotao
                data-alterar-quando
                variante="fantasma"
                :inativo="gravando"
                :aria-label="
                  t(`${NS}.ALTERAR_QUANDO_SR`, {
                    ferramenta: nomeDa(item.fonte),
                  })
                "
                @click="alterar(item)"
              >
                {{ t(`${NS}.ALTERAR_QUANDO`) }}
              </AgenteBotao>
              <AgenteBotao
                data-tirar-ferramenta
                variante="fantasma"
                :inativo="gravando"
                :aria-label="
                  t('AGENTS.VITRINE.JA_VEM.TIRAR_SR', {
                    ferramenta: nomeDa(item.fonte),
                  })
                "
                @click="tirar(item.fonte)"
              >
                {{ t('AGENTS.VITRINE.JA_VEM.TIRAR') }}
              </AgenteBotao>
            </div>
          </template>
        </div>
      </li>
    </ul>

    <div
      v-if="podeMudar && tambem.length"
      data-tambem-combina
      class="flex flex-wrap items-center justify-between gap-3 p-3 rounded-xl bg-n-solid-2"
    >
      <span class="flex-1 text-sm min-w-40 text-n-slate-11">
        {{
          t('AGENTS.VITRINE.JA_VEM.TAMBEM', { ferramentas: nomesDoTambem() })
        }}
      </span>
      <AgenteBotao
        data-incluir-tambem
        variante="contorno"
        icone="i-lucide-plus"
        :inativo="gravando"
        :aria-label="
          t('AGENTS.VITRINE.JA_VEM.INCLUIR_TAMBEM_SR', {
            ferramentas: nomesDoTambem(),
          })
        "
        @click="incluirTambem"
      >
        {{ t('AGENTS.VITRINE.JA_VEM.INCLUIR_TAMBEM') }}
      </AgenteBotao>
    </div>

    <a
      v-if="linkDaVitrine"
      data-ver-mais-ferramentas
      :href="linkDaVitrine"
      target="_blank"
      rel="noopener noreferrer"
      class="relative inline-flex items-center gap-2 text-sm font-semibold w-fit min-h-11 text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
    >
      <span class="i-lucide-plus size-4" aria-hidden="true" />
      {{ t(`${NS}.INCLUIR_FERRAMENTA`) }}
      <span class="sr-only">{{ t('AGENTS.JORNADA.COMUM.NOVA_ABA') }}</span>
    </a>

    <p
      v-if="linkDaVitrine && pagas.length"
      data-quer-tambem
      class="flex items-start gap-2 p-3 m-0 text-sm rounded-xl bg-n-amber-2 text-n-slate-12"
    >
      <span
        class="i-lucide-gem size-4 mt-0.5 shrink-0 text-n-amber-11"
        aria-hidden="true"
      />
      <span>
        {{ t(`${NS}.QUER_TAMBEM`, { pagas: emFrase(pagas) }) }}
        <a
          :href="linkDaVitrine"
          target="_blank"
          rel="noopener noreferrer"
          class="relative font-semibold underline text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
        >
          {{ t(`${NS}.VER_PAGAS`) }}
          <span class="sr-only">
            {{ t('AGENTS.JORNADA.COMUM.NOVA_ABA') }}
          </span>
        </a>
      </span>
    </p>
  </div>
</template>
