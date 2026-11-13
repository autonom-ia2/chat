<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import SeloDeEstado from '../comum/SeloDeEstado.vue';
import { formatarMes } from '../../ficha/formatos';
import { formatarTelefone } from '../../lista/telefone';
import { useIdioma } from '../../ficha/idioma';
import BotaoCopiar from './BotaoCopiar.vue';
import MenuMais from './MenuMais.vue';

// #2894 — o cabeçalho da ficha da pessoa: quem é, desde quando é cliente, como
// falar com ela, e as ações. Só "Conversar" é preenchido. Quem só pode ver o
// contato (`podeEditar` falso) não tem "Marcar como cliente", "Não é mais
// cliente" nem "Alterar informações"; quem não pode criar card
// (`podeCriarCards` falso) não tem "Novo card".
// #2970 — o que ainda não é de verdade não aparece: "Conversar" só existe com
// `podeConversar` (a página liga quando há conversa para abrir, ou na
// demonstração). Sem ele nenhum botão é preenchido: as outras ações seguem
// discretas, na mesma ordem. "Lembrete" e, no "⋯", Juntar, Bloquear e Apagar
// ainda só avisam: só existem com `naDemonstracao`. Fora dela sobra o que é de
// quem pode editar: de quem é cliente, o "⋯" com "Alterar informações" e "Não
// é mais cliente"; de quem não é, só o botão "Alterar informações", sem menu.
// Quem só pode ver não tem nenhum dos dois; sem ação nenhuma, o grupo de ações
// não é desenhado.
const props = defineProps({
  pessoa: { type: Object, required: true },
  marcandoCliente: { type: Boolean, default: false },
  podeEditar: { type: Boolean, default: true },
  podeCriarCards: { type: Boolean, default: true },
  podeConversar: { type: Boolean, default: false },
  naDemonstracao: { type: Boolean, default: false },
});
const emit = defineEmits([
  'conversar',
  'novoCard',
  'lembrete',
  'marcarCliente',
  'abrirEmpresa',
  'maisAcao',
]);

const { t } = useI18n();
const idioma = useIdioma();

const ehCliente = computed(() => props.pessoa.contact_type === 'customer');
const clienteDesde = computed(() =>
  props.pessoa.customer_since
    ? t('RELACIONAMENTOS_FICHA.CABECALHO.CLIENTE_DESDE', {
        data: formatarMes(props.pessoa.customer_since, idioma.value),
      })
    : t('RELACIONAMENTOS.COMUM.SELO_CLIENTE')
);
const empresa = computed(
  () => props.pessoa.additional_attributes?.company_name || ''
);

// O "⋯" só é menu com dois itens ou mais: o desenho todo, na demonstração, ou
// "Alterar informações" e "Não é mais cliente", de quem é cliente. Com um item
// só, "Alterar informações" é um botão: ninguém abre menu para uma escolha.
const temMais = computed(
  () => props.naDemonstracao || (props.podeEditar && ehCliente.value)
);
const alteraDireto = computed(() => props.podeEditar && !temMais.value);
const temSecundarias = computed(
  () => props.podeCriarCards || props.podeEditar || props.naDemonstracao
);
// Celular, com o "⋯": os botões com rótulo ao lado dele (Novo card, Lembrete)
// dividem a linha e ele fica na ponta; sozinho, continua na ponta. Sem o "⋯",
// cada botão ocupa a linha toda: "Alterar informações" não cabe ao lado de
// outro.
const GRADE_COM_MAIS = [
  'grid-cols-1 justify-items-end',
  'grid-cols-[1fr_auto]',
  'grid-cols-[1fr_1fr_auto]',
];
const botoesAoLadoDoMais = computed(
  () => [props.podeCriarCards, props.naDemonstracao].filter(Boolean).length
);
const grade = computed(() =>
  temMais.value ? GRADE_COM_MAIS[botoesAoLadoDoMais.value] : 'grid-cols-1'
);
</script>

<template>
  <header
    data-relacionamentos="cabecalho"
    class="flex flex-col w-full min-w-0 gap-6 p-5 border shadow-sm rounded-2xl border-n-weak bg-n-solid-1 md:p-8 lg:flex-row lg:items-start lg:justify-between"
  >
    <!-- Celular: avatar e nome na primeira faixa; contato e etiquetas descem,
         na largura toda. Desktop: tudo ao lado do avatar. -->
    <div
      class="grid w-full min-w-0 grid-cols-[auto_1fr] items-center gap-x-4 gap-y-4 md:items-start md:gap-x-6 lg:flex-1"
    >
      <Avatar
        :name="pessoa.name"
        :src="pessoa.thumbnail"
        :size="56"
        rounded-full
        class="shrink-0 md:hidden"
      />
      <Avatar
        :name="pessoa.name"
        :src="pessoa.thumbnail"
        :size="88"
        rounded-full
        class="hidden shrink-0 md:row-span-2 md:inline-flex"
      />
      <div class="flex flex-col items-start min-w-0 gap-2">
        <h1
          class="m-0 text-2xl font-bold leading-tight tracking-tight break-words md:text-4xl text-n-slate-12"
        >
          {{ pessoa.name }}
        </h1>
        <SeloDeEstado v-if="ehCliente" tom="cliente">
          {{ clienteDesde }}
        </SeloDeEstado>
        <Button
          v-else-if="podeEditar"
          data-relacionamentos="marcar-cliente"
          slate
          faded
          icon="i-lucide-badge-check"
          class="whitespace-nowrap shrink-0"
          :is-loading="marcandoCliente"
          :label="t('RELACIONAMENTOS_FICHA.CABECALHO.MARCAR_CLIENTE')"
          @click="emit('marcarCliente')"
        />
      </div>
      <div
        data-relacionamentos="contato-e-etiquetas"
        class="flex flex-col min-w-0 col-span-2 gap-3 md:col-span-1 md:col-start-2"
      >
        <div class="flex flex-col min-w-0 gap-1">
          <div
            v-if="pessoa.phone_number"
            data-contato="telefone"
            class="flex items-center min-w-0 gap-2 text-base text-n-slate-12"
          >
            <span
              class="i-lucide-phone size-4 shrink-0 text-n-slate-10"
              aria-hidden="true"
            />
            <span class="tabular-nums whitespace-nowrap">
              {{ formatarTelefone(pessoa.phone_number) }}
            </span>
            <BotaoCopiar
              class="-my-2"
              :valor="pessoa.phone_number"
              :item="t('RELACIONAMENTOS_FICHA.CABECALHO.ITEM_TELEFONE')"
            />
          </div>
          <div
            v-if="pessoa.email"
            data-contato="email"
            class="flex items-center min-w-0 gap-2 text-base text-n-slate-11"
          >
            <span
              class="i-lucide-mail size-4 shrink-0 text-n-slate-10"
              aria-hidden="true"
            />
            <span class="min-w-0 break-words" :title="pessoa.email">
              {{ pessoa.email }}
            </span>
          </div>
          <div
            v-if="empresa"
            data-contato="empresa"
            class="flex items-center min-w-0 gap-2 text-base text-n-slate-11"
          >
            <span
              class="i-lucide-building-2 size-4 shrink-0 text-n-slate-10"
              aria-hidden="true"
            />
            <button
              v-if="pessoa.company_id"
              type="button"
              data-relacionamentos="empresa-da-pessoa"
              class="p-0 -my-2 font-medium bg-transparent border-0 min-w-0 text-start text-n-blue-11 hover:underline min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
              @click="emit('abrirEmpresa', pessoa.company_id)"
            >
              {{ empresa }}
            </button>
            <span v-else class="min-w-0 break-words">{{ empresa }}</span>
          </div>
        </div>
        <ul
          v-if="pessoa.labels?.length"
          :aria-label="t('RELACIONAMENTOS_FICHA.CABECALHO.ETIQUETAS')"
          class="flex flex-wrap gap-2 p-0 m-0 list-none"
        >
          <li
            v-for="etiqueta in pessoa.labels"
            :key="etiqueta"
            class="px-2.5 py-0.5 text-xs font-medium rounded-full bg-n-iris-3 text-n-iris-11"
          >
            {{ etiqueta }}
          </li>
        </ul>
      </div>
    </div>
    <div
      v-if="podeConversar || temSecundarias"
      role="group"
      :aria-label="
        t('RELACIONAMENTOS_FICHA.CABECALHO.ACOES', { nome: pessoa.name })
      "
      class="flex flex-col w-full min-w-0 gap-3 lg:w-auto lg:flex-row lg:items-center lg:shrink-0"
    >
      <Button
        v-if="podeConversar"
        data-relacionamentos="conversar"
        size="lg"
        class="w-full lg:w-auto whitespace-nowrap shrink-0"
        icon="i-lucide-message-circle"
        :label="t('RELACIONAMENTOS.COMUM.CONVERSAR')"
        @click="emit('conversar')"
      />
      <div
        v-if="temSecundarias"
        data-relacionamentos="acoes-secundarias"
        class="grid items-center gap-3 lg:flex lg:shrink-0"
        :class="grade"
      >
        <Button
          v-if="podeCriarCards"
          data-relacionamentos="novo-card"
          slate
          faded
          size="lg"
          class="w-full whitespace-nowrap shrink-0 lg:w-auto"
          :label="t('RELACIONAMENTOS_FICHA.ACOES.NOVO_CARD')"
          @click="emit('novoCard')"
        />
        <Button
          v-if="naDemonstracao"
          slate
          faded
          size="lg"
          class="w-full whitespace-nowrap shrink-0 lg:w-auto"
          :label="t('RELACIONAMENTOS_FICHA.ACOES.LEMBRETE')"
          @click="emit('lembrete')"
        />
        <Button
          v-if="alteraDireto"
          data-relacionamentos="alterar-informacoes"
          slate
          faded
          size="lg"
          class="w-full whitespace-nowrap shrink-0 lg:w-auto"
          :label="t('RELACIONAMENTOS_FICHA.ACOES.ALTERAR_INFORMACOES')"
          @click="emit('maisAcao', 'alterar')"
        />
        <MenuMais
          v-if="temMais"
          :pode-alterar="podeEditar"
          :eh-cliente="ehCliente"
          :na-demonstracao="naDemonstracao"
          @acao="escolha => emit('maisAcao', escolha)"
        />
      </div>
    </div>
  </header>
</template>
