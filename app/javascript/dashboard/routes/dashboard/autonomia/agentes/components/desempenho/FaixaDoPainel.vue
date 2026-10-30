<script setup>
import { useFormatoDoPainel } from '../../composables/useFormatoDoPainel';
import AgenteAvatar from '../AgenteAvatar.vue';
import AgenteBotao from '../AgenteBotao.vue';

// #2226 v2 (§1) — a faixa compacta do topo (navy do produto, ~76px): migalha, foto, nome do agente,
// o período por extenso, "Dados até" e as ações Exportar PDF / Exportar Excel. Sem herói decorativo:
// a primeira tela é dos números. Botão sem arquivo fica desligado, com a dica embaixo.
const props = defineProps({
  nome: { type: String, required: true },
  foto: { type: String, default: '' },
  // [{ texto, destino?, href? }] — o último é a página atual.
  migalha: { type: Array, default: () => [] },
  periodo: { type: String, default: '' },
  dadosAte: { type: String, default: '' },
  // #2301 — com a leitura automática, até onde a IA leu: mostrado no lugar de "Dados até".
  lidoAte: { type: String, default: '' },
  // { pdf: { estado: 'verificando'|'pronto'|'sem_arquivo'|'baixando' }, xlsx: {…} }
  exportacao: { type: Object, default: () => ({}) },
  // #2251 — sem contact_export, a pessoa vê o painel mas não baixa o arquivo: os botões nem aparecem.
  podeExportar: { type: Boolean, default: true },
});

const emit = defineEmits(['migalha', 'exportar']);

const fmt = useFormatoDoPainel();
const NS = 'AGENTS.DESEMPENHO2.A.FAIXA';
const FORMATOS = [
  { id: 'pdf', icone: 'i-lucide-file-text' },
  { id: 'xlsx', icone: 'i-lucide-sheet' },
];

const estadoDe = formato =>
  props.exportacao?.[formato]?.estado || 'sem_arquivo';
const semArquivo = () =>
  FORMATOS.every(formato => estadoDe(formato.id) === 'sem_arquivo');

// Clique com Ctrl/Cmd/Shift (ou botão do meio) abre em outra aba pelo href; o resto navega no app.
const aoNavegar = (evento, item) => {
  if (evento.metaKey || evento.ctrlKey || evento.shiftKey || evento.button)
    return;
  evento.preventDefault();
  emit('migalha', item);
};
</script>

<template>
  <header
    data-faixa
    class="w-full px-4 py-3 text-white md:px-6 bg-n-heroi dark:bg-n-heroi-escuro"
  >
    <div
      class="flex flex-col w-full gap-2 mx-auto max-w-screen-2xl lg:flex-row lg:items-center lg:justify-between"
    >
      <div class="flex flex-col min-w-0 gap-0.5">
        <nav
          v-if="migalha.length"
          :aria-label="fmt.t('AGENTS.DESEMPENHO.MIGALHA.ROTULO')"
        >
          <ol
            class="flex flex-wrap items-center gap-0.5 p-0 m-0 text-xs list-none text-white/70"
          >
            <li
              v-for="(item, indice) in migalha"
              :key="`${indice}-${item.texto}`"
              class="flex items-center gap-0.5"
            >
              <span
                v-if="indice"
                class="i-lucide-chevron-right size-3.5 rtl:rotate-180 text-white/50"
                aria-hidden="true"
              />
              <a
                v-if="item.href"
                :href="item.href"
                data-migalha
                class="inline-flex items-center px-1 -my-3.5 rounded min-h-11 hover:text-white hover:underline underline-offset-4 focus-visible:outline focus-visible:outline-2 focus-visible:outline-white"
                @click="aoNavegar($event, item)"
              >
                {{ item.texto }}
              </a>
              <span v-else aria-current="page" class="px-1 text-white/90">
                {{ item.texto }}
              </span>
            </li>
          </ol>
        </nav>
        <div class="flex items-center min-w-0 gap-3">
          <AgenteAvatar
            class="!size-10 !text-base ring-2 ring-white/30 shrink-0"
            :nome="nome || '?'"
            :src="foto"
            tom="atendendo"
          />
          <div class="flex flex-col min-w-0">
            <h1
              id="desempenho-titulo"
              class="m-0 text-xl font-semibold leading-tight text-white truncate"
            >
              {{ nome }}
            </h1>
            <p
              data-periodo-extenso
              class="flex flex-wrap items-center m-0 text-sm gap-x-2 text-white/80 tabular-nums"
            >
              <span>{{ periodo }}</span>
              <template v-if="lidoAte">
                <span aria-hidden="true">{{
                  fmt.t('AGENTS.DESEMPENHO2.A.COMUM.SEPARADOR')
                }}</span>
                <span data-lido-ate>
                  {{
                    fmt.t(`${NS}.LIDO_ATE`, { quando: fmt.dataHora(lidoAte) })
                  }}
                </span>
              </template>
              <template v-else-if="dadosAte">
                <span aria-hidden="true">{{
                  fmt.t('AGENTS.DESEMPENHO2.A.COMUM.SEPARADOR')
                }}</span>
                <span data-dados-ate>
                  {{
                    fmt.t(`${NS}.DADOS_ATE`, { quando: fmt.dataHora(dadosAte) })
                  }}
                </span>
              </template>
            </p>
          </div>
        </div>
      </div>
      <div v-if="podeExportar" class="flex flex-col gap-1 lg:items-end">
        <div class="flex flex-wrap gap-2">
          <AgenteBotao
            v-for="formato in FORMATOS"
            :key="formato.id"
            :data-exportar="formato.id"
            variante="branco"
            :icone="formato.icone"
            :carregando="
              ['verificando', 'baixando'].includes(estadoDe(formato.id))
            "
            :rotulo-carregando="fmt.t(`${NS}.EXPORTANDO`)"
            :desabilitado="estadoDe(formato.id) === 'sem_arquivo'"
            @click="emit('exportar', formato.id)"
          >
            {{ fmt.t(`${NS}.EXPORTAR.${formato.id.toUpperCase()}`) }}
          </AgenteBotao>
        </div>
        <p
          v-if="semArquivo()"
          data-sem-exportacao
          class="m-0 text-xs text-white/70"
        >
          {{ fmt.t(`${NS}.SEM_EXPORTACAO`) }}
        </p>
      </div>
    </div>
  </header>
</template>
