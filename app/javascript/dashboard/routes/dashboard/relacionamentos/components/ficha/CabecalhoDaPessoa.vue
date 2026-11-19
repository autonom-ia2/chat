<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import SeloDeEstado from '../comum/SeloDeEstado.vue';
import { formatarMes } from '../../ficha/formatos';
import { formatarTelefone } from '../../lista/telefone';
import { useIdioma } from '../../ficha/idioma';
import VoiceCallButton from 'dashboard/components-next/Contacts/VoiceCallButton.vue';
import BotaoCopiar from './BotaoCopiar.vue';
import MenuMais from './MenuMais.vue';

// #2894 — o cabeçalho da ficha da pessoa: quem é, desde quando é cliente, como
// falar com ela, e as ações. Só "Conversar" é preenchido. Quem só pode ver o
// contato (`podeEditar` falso) não tem "Marcar como cliente", "Não é mais
// cliente" nem "Alterar informações"; quem não pode criar card
// (`podeCriarCards` falso) não tem "Novo card".
// #3071 — todas as ações da ficha antiga, de verdade:
//  - "Conversar" aparece sempre: com conversa abre a mais recente; sem, a página
//    abre a "Nova conversa" já com a pessoa. "Ligar" fica ao lado dele: é o
//    VoiceCallButton da casa, que só aparece quando a conta tem caixa com voz e
//    a pessoa tem telefone, e escolhe a caixa e liga. `podeLigar` falso só na
//    demonstração, onde as pessoas são inventadas;
//  - "Lembrete" com `podeLembrete` (a regra do "Novo lembrete" da ficha antiga);
//  - as etiquetas, com a cor de cada uma (o Label da casa; `coresDasEtiquetas`
//    vem das etiquetas da conta), ganham "Pôr etiqueta" / "Mudar etiquetas"
//    (`podeEditar`), numa linha própria, alinhado com os ícones do contato;
//  - o "⋯" tem Alterar informações, Não é mais cliente, Não quer receber
//    mensagens, Juntar, Bloquear ou Desbloquear (de quem pode editar) e Apagar
//    (`podeApagar`). Com dois itens ou mais é menu; com um só, é um botão:
//    ninguém abre menu para uma escolha. Sem nenhum, não há botão.
const props = defineProps({
  pessoa: { type: Object, required: true },
  marcandoCliente: { type: Boolean, default: false },
  podeEditar: { type: Boolean, default: true },
  podeApagar: { type: Boolean, default: false },
  podeCriarCards: { type: Boolean, default: true },
  podeLembrete: { type: Boolean, default: false },
  podeLigar: { type: Boolean, default: false },
  // { [nome]: '#cor' }: as etiquetas da conta.
  coresDasEtiquetas: { type: Object, default: () => ({}) },
});
const emit = defineEmits([
  'conversar',
  'novoCard',
  'lembrete',
  'marcarCliente',
  'abrirEmpresa',
  'maisAcao',
  'etiquetas',
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

const ITEM = {
  alterar: { chave: 'ALTERAR_INFORMACOES', icone: 'i-lucide-pencil' },
  desmarcar: { chave: 'DESMARCAR_CLIENTE', icone: 'i-lucide-user-minus' },
  naoQuer: { chave: 'NAO_QUER', icone: 'i-lucide-bell-off' },
  juntar: { chave: 'JUNTAR', icone: 'i-lucide-combine' },
  bloquear: { chave: 'BLOQUEAR', icone: 'i-lucide-ban' },
  desbloquear: { chave: 'DESBLOQUEAR', icone: 'i-lucide-shield-check' },
  apagar: { chave: 'APAGAR', icone: 'i-lucide-trash-2', perigo: true },
};
const itensDoMais = computed(() => {
  const edita = props.podeEditar;
  return [
    edita && 'alterar',
    edita && ehCliente.value && 'desmarcar',
    edita && !props.pessoa.opted_out_at && 'naoQuer',
    edita && 'juntar',
    edita && (props.pessoa.blocked ? 'desbloquear' : 'bloquear'),
    props.podeApagar && 'apagar',
  ]
    .filter(Boolean)
    .map(evento => ({ evento, ...ITEM[evento] }));
});
const temMais = computed(() => itensDoMais.value.length > 1);
const unico = computed(() =>
  itensDoMais.value.length === 1 ? itensDoMais.value[0] : null
);
const temSecundarias = computed(
  () =>
    props.podeCriarCards || props.podeLembrete || itensDoMais.value.length > 0
);
// Celular, com o "⋯": os botões com rótulo ao lado dele (Novo card, Lembrete)
// dividem a linha e ele fica na ponta; sozinho, continua na ponta. Sem o "⋯",
// cada botão ocupa a linha toda.
const GRADE_COM_MAIS = [
  'grid-cols-1 justify-items-end',
  'grid-cols-[1fr_auto]',
  'grid-cols-[1fr_1fr_auto]',
];
const botoesAoLadoDoMais = computed(
  () => [props.podeCriarCards, props.podeLembrete].filter(Boolean).length
);
const grade = computed(() =>
  temMais.value ? GRADE_COM_MAIS[botoesAoLadoDoMais.value] : 'grid-cols-1'
);
const etiquetas = computed(() =>
  (props.pessoa.labels ?? []).map(nome => ({
    title: nome,
    color: props.coresDasEtiquetas[nome] ?? null,
  }))
);
const rotuloDasEtiquetas = computed(() =>
  t(
    `RELACIONAMENTOS_FICHA.ACOES.${props.pessoa.labels?.length ? 'MUDAR_ETIQUETAS' : 'POR_ETIQUETA'}`
  )
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
        <div
          v-if="pessoa.labels?.length || podeEditar"
          data-relacionamentos="etiquetas-da-pessoa"
          class="flex flex-col items-start min-w-0 gap-1"
        >
          <ul
            v-if="etiquetas.length"
            :aria-label="t('RELACIONAMENTOS_FICHA.CABECALHO.ETIQUETAS')"
            class="flex flex-wrap gap-2 p-0 m-0 list-none"
          >
            <li
              v-for="etiqueta in etiquetas"
              :key="etiqueta.title"
              :data-etiqueta-da-pessoa="etiqueta.title"
            >
              <Label :label="etiqueta" compact />
            </li>
          </ul>
          <Button
            v-if="podeEditar"
            data-relacionamentos="mudar-etiquetas"
            slate
            ghost
            icon="i-lucide-tag"
            class="!h-11 -ms-3 whitespace-nowrap"
            :label="rotuloDasEtiquetas"
            @click="emit('etiquetas')"
          />
        </div>
      </div>
    </div>
    <div
      role="group"
      :aria-label="
        t('RELACIONAMENTOS_FICHA.CABECALHO.ACOES', { nome: pessoa.name })
      "
      class="flex flex-col w-full min-w-0 gap-3 lg:w-auto lg:flex-row lg:items-center lg:shrink-0"
    >
      <div class="flex items-center min-w-0 gap-3 lg:shrink-0">
        <Button
          data-relacionamentos="conversar"
          size="lg"
          class="flex-1 min-w-0 lg:flex-none whitespace-nowrap"
          icon="i-lucide-message-circle"
          :label="t('RELACIONAMENTOS.COMUM.CONVERSAR')"
          @click="emit('conversar')"
        />
        <VoiceCallButton
          v-if="podeLigar"
          data-relacionamentos="ligar"
          :phone="pessoa.phone_number"
          :contact-id="pessoa.id"
          :label="t('RELACIONAMENTOS_FICHA.ACOES.LIGAR')"
          icon="i-lucide-phone"
          size="lg"
          slate
          faded
          class="whitespace-nowrap shrink-0"
        />
      </div>
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
          v-if="podeLembrete"
          data-relacionamentos="lembrete"
          slate
          faded
          size="lg"
          icon="i-lucide-bell-plus"
          class="w-full whitespace-nowrap shrink-0 lg:w-auto"
          :label="t('RELACIONAMENTOS_FICHA.ACOES.LEMBRETE')"
          @click="emit('lembrete')"
        />
        <Button
          v-if="unico"
          :data-relacionamentos="
            unico.evento === 'alterar'
              ? 'alterar-informacoes'
              : `mais-${unico.evento}`
          "
          slate
          faded
          size="lg"
          class="w-full whitespace-nowrap shrink-0 lg:w-auto"
          :class="{ '!text-n-ruby-11': unico.perigo }"
          :label="t(`RELACIONAMENTOS_FICHA.ACOES.${unico.chave}`)"
          @click="emit('maisAcao', unico.evento)"
        />
        <MenuMais
          v-if="temMais"
          :itens="itensDoMais"
          @acao="escolha => emit('maisAcao', escolha)"
        />
      </div>
    </div>
  </header>
</template>
