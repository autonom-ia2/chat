<script setup>
import { computed } from 'vue';
import { useFormatoDoPainel } from '../../../composables/useFormatoDoPainel';
import CabecalhoDeSecao from '../comum/CabecalhoDeSecao.vue';
import CartaoDoPainel from '../comum/CartaoDoPainel.vue';
import Ressalva from '../comum/Ressalva.vue';

// #2226 v2 (§2.12) — como ler o painel, o que estes números não provam (frases fixas da ESPEC 2.10,
// a ressalva do negócio e os avisos do período) e quanto confiar: a conferência feita lendo a
// conversa inteira, campo a campo, com a leitura firme ou otimista.
const props = defineProps({
  painel: { type: Object, required: true },
});

const fmt = useFormatoDoPainel();
const NS = 'AGENTS.DESEMPENHO2.A.COMO_LER';
const NAO_PROVAM = [
  'ASSUNTO',
  'FORA_DA_CONVERSA',
  'ANUNCIO',
  'AUDIO',
  'ANDAMENTO',
  'JUNTOS',
];
const AVISOS = [
  'dia_parcial',
  'so_periodo_todo',
  'pouco_dado',
  'instrucao_mudou',
  'lido_por_amostra',
  'sem_anuncio',
];
const COR_DA_LEITURA = {
  firme: 'text-n-teal-11',
  otimista: 'text-n-amber-11',
  fraca: 'text-n-ruby-11',
};
const BARRA_DA_LEITURA = {
  firme: 'fill-n-teal-9',
  otimista: 'fill-n-amber-9',
  fraca: 'fill-n-ruby-9',
};

const meta = computed(() => props.painel.meta);
const confianca = computed(() => props.painel.confianca);

const textoDoAviso = aviso => {
  const valores = { ...(aviso.valores || {}) };
  if (valores.dia) valores.dia = fmt.data(valores.dia);
  if (valores.data) valores.data = fmt.data(valores.data);
  // Os nomes das partes (nunca o id cru), numa lista com o "e" do idioma.
  if (Array.isArray(valores.secoes)) {
    valores.secoes = fmt.lista(
      valores.secoes.map(secao =>
        fmt.tSeTiver(
          `${NS}.SECAO.${String(secao).toUpperCase()}`,
          fmt.t('AGENTS.DESEMPENHO2.A.COMUM.SEM_NOME')
        )
      )
    );
  }
  return fmt.tSeTiver(`${NS}.AVISO.${aviso.id.toUpperCase()}`, '', valores);
};
const avisos = computed(() =>
  (props.painel.avisos || []).filter(aviso => AVISOS.includes(aviso.id))
);
</script>

<template>
  <section
    id="como-ler"
    aria-labelledby="como-ler-titulo"
    class="flex flex-col gap-4 scroll-mt-28"
  >
    <CabecalhoDeSecao
      id="como-ler-titulo"
      :sobre="fmt.t(`${NS}.SOBRE`)"
      :titulo="fmt.t(`${NS}.TITULO`)"
      :descricao="fmt.t(`${NS}.DESCRICAO`)"
    />
    <div class="grid gap-4 xl:grid-cols-2">
      <CartaoDoPainel :titulo="fmt.t(`${NS}.COMO_LER`)">
        <dl class="flex flex-col gap-2 m-0">
          <div
            v-for="definicao in meta.definicoes || []"
            :key="definicao.id"
            class="flex flex-col"
          >
            <dt class="text-sm font-semibold text-n-slate-12">
              {{ definicao.termo }}
            </dt>
            <dd class="m-0 text-sm text-n-slate-11">{{ definicao.texto }}</dd>
          </div>
        </dl>
        <ul
          class="flex flex-col gap-1 p-0 m-0 text-xs list-none text-n-slate-11"
        >
          <li class="tabular-nums">
            {{ fmt.t(`${NS}.TESTES`, { n: fmt.n(meta.base?.procuras_teste) }) }}
          </li>
        </ul>
      </CartaoDoPainel>
      <CartaoDoPainel data-nao-provam :titulo="fmt.t(`${NS}.NAO_PROVAM`)">
        <ul
          class="flex flex-col gap-1.5 p-0 m-0 text-sm list-none text-n-slate-12"
        >
          <li v-if="meta.nomes.fechou_ressalva" class="flex gap-2">
            <span
              class="i-lucide-dot size-4 shrink-0 text-n-slate-10"
              aria-hidden="true"
            />
            {{ meta.nomes.fechou_ressalva }}
          </li>
          <li v-for="frase in NAO_PROVAM" :key="frase" class="flex gap-2">
            <span
              class="i-lucide-dot size-4 shrink-0 text-n-slate-10"
              aria-hidden="true"
            />
            {{ fmt.t(`${NS}.FRASE.${frase}`) }}
          </li>
        </ul>
        <ul v-if="avisos.length" class="flex flex-col gap-2 p-0 m-0 list-none">
          <li v-for="aviso in avisos" :key="aviso.id" :data-aviso="aviso.id">
            <Ressalva :texto="textoDoAviso(aviso)" />
          </li>
        </ul>
      </CartaoDoPainel>
    </div>
    <CartaoDoPainel
      v-if="confianca"
      data-confianca
      :titulo="fmt.t(`${NS}.CONFIAR`)"
      :descricao="`${fmt.t(`${NS}.CONFERIMOS`, { n: fmt.n(confianca.conferidas) })} ${confianca.metodo || ''}`"
    >
      <div class="overflow-x-auto">
        <table class="w-full text-sm border-collapse tabular-nums">
          <thead>
            <tr class="text-xs text-n-slate-11">
              <th scope="col" class="py-2 pr-2 font-semibold text-start">
                {{ fmt.t(`${NS}.COL.CAMPO`) }}
              </th>
              <th scope="col" class="px-2 py-2 font-semibold text-end">
                {{ fmt.t(`${NS}.COL.ACERTOS`) }}
              </th>
              <th scope="col" class="px-2 py-2 font-semibold text-end">
                {{ fmt.t(`${NS}.COL.PCT`) }}
              </th>
              <th
                scope="col"
                class="relative px-2 py-2 font-semibold text-start w-2/5"
              >
                <span class="sr-only">{{ fmt.t(`${NS}.COL.BARRA`) }}</span>
              </th>
              <th scope="col" class="py-2 pl-2 font-semibold text-start">
                {{ fmt.t(`${NS}.COL.LEITURA`) }}
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-n-weak">
            <tr
              v-for="campo in confianca.campos || []"
              :key="campo.id"
              :data-campo="campo.id"
            >
              <th
                scope="row"
                class="py-2 pr-2 font-normal text-start text-n-slate-12"
              >
                {{ campo.nome }}
              </th>
              <td class="px-2 py-2 text-end text-n-slate-12">
                {{
                  fmt.t(`${NS}.DE`, {
                    n: fmt.n(campo.certos),
                    m: fmt.n(campo.total),
                  })
                }}
              </td>
              <td class="px-2 py-2 font-semibold text-end text-n-slate-12">
                {{ fmt.pct(campo.acerto_pct) }}
              </td>
              <td class="px-2 py-2">
                <svg
                  viewBox="0 0 100 8"
                  preserveAspectRatio="none"
                  class="w-full h-2"
                  aria-hidden="true"
                >
                  <rect width="100" height="8" rx="4" class="fill-n-slate-3" />
                  <rect
                    :width="Math.max(0, Math.min(100, campo.acerto_pct || 0))"
                    height="8"
                    rx="4"
                    :class="BARRA_DA_LEITURA[campo.leitura] || 'fill-n-slate-9'"
                  />
                </svg>
              </td>
              <td
                class="py-2 pl-2 font-semibold"
                :class="COR_DA_LEITURA[campo.leitura] || 'text-n-slate-11'"
              >
                {{
                  fmt.tSeTiver(
                    `${NS}.LEITURA.${String(campo.leitura).toUpperCase()}`,
                    String(campo.leitura)
                  )
                }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <Ressalva
        v-if="confianca.leitura_geral"
        :destaque="confianca.leitura_geral"
      />
    </CartaoDoPainel>
  </section>
</template>
