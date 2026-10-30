<script setup>
import { computed } from 'vue';
import { useI18n, I18nT } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import CustomerBadge from 'dashboard/components-next/customer-badge/CustomerBadge.vue';
import CardCartao from './CardCartao.vue';
import CardMaisDetalhes from './CardMaisDetalhes.vue';
import { atrasado } from './proximoPasso';
import { formatClientPhone } from '../../helpers/meetingDay';
import { promessaDoCard } from './useCardNegocio';
import { textoDoFechamento } from './sugestaoDeFechar';

// #1423 — o card em quatro frases, sempre na mesma ordem: Cliente, Negócio,
// Agenda e Conversa. Cada coisa aparece num lugar só da tela: o que já está no
// Próximo passo (a reunião de hoje, o retorno atrasado, a sugestão, o cliente
// esperando) não se repete aqui. O resto — de onde veio, o que já aconteceu,
// mais do negócio e arquivar — fica recolhido em "Mais detalhes".
const props = defineProps({
  card: { type: Object, required: true },
  etapas: { type: Array, default: () => [] },
  passos: { type: Object, required: true },
  reuniao: { type: Object, default: null },
  retornos: { type: Array, default: () => [] },
  sugestao: { type: Object, default: null },
  conversas: { type: Array, default: () => [] },
  conversao: { type: Object, default: null },
  resumo: { type: Object, default: () => ({ texto: '', quando: '' }) },
  ia: { type: Boolean, default: false },
  formato: { type: Object, required: true },
  nome: { type: String, required: true },
  podeGerenciar: { type: Boolean, default: false },
  podeArquivar: { type: Boolean, default: false },
  // Mexer na pessoa e na empresa (Trocar com o card; Editar com os registros).
  podeRegistros: { type: Boolean, default: false },
  // A conta usa empresas (feature companies).
  empresas: { type: Boolean, default: false },
  // Sem ver contatos (#1849): a pessoa só para ver e sem a empresa.
  podeVerContatos: { type: Boolean, default: true },
  arquivando: { type: Boolean, default: false },
  // #1498 — Negócio (Vender) ou Assunto (Atender), e Cobrança.
  jeito: { type: Object, required: true },
});

defineEmits(['abrir', 'arquivar', 'conversa', 'cliente']);

const { t } = useI18n();
const R = 'CRM_CARD.RESUMO';
const URGENCIA = {
  low: 'LOW',
  medium: 'MEDIUM',
  high: 'HIGH',
  urgent: 'URGENT',
};
const MAX_AGENDA = 2;

// ——— O que o Próximo passo já mostra ———
const noPasso = computed(() => [
  props.passos.principal,
  ...(props.passos.depois || []),
]);
const tiposNoPasso = computed(() => noPasso.value.map(passo => passo.tipo));
const retornosNoPasso = computed(() =>
  noPasso.value.map(passo => passo.retorno?.id).filter(Boolean)
);
const reuniaoNoPasso = computed(() =>
  tiposNoPasso.value.some(tipo => tipo.startsWith('reuniao'))
);
const respondeNoPasso = computed(
  () => props.passos.principal.tipo === 'espera'
);

// ——— Contato e empresa: duas coisas diferentes, cada uma com o seu Alterar.
// "Cliente" é só o status de quem já comprou (selo da base de clientes).
const contato = computed(() => props.card.contact || null);
const ehCliente = computed(() => contato.value?.contact_type === 'customer');
const empresa = computed(() => props.card.company?.name || '');
const mostraEmpresa = computed(
  () => props.podeVerContatos && (props.empresas || Boolean(empresa.value))
);

// ——— Negócio ———
const posicao = computed(() =>
  props.etapas.findIndex(etapa => etapa.id === props.card.stage_id)
);
const etapaAtual = computed(
  () => props.etapas[posicao.value]?.name || props.card.stage?.name || ''
);
// F3: a sugestão de fechar o card diz o que acabou, e não a etapa.
const textoDaSugestao = computed(() => {
  const fechar = textoDoFechamento(props.sugestao);
  if (!fechar)
    return t(`${R}.SUGESTAO`, { etapa: props.sugestao?.to_stage_name });
  return t(fechar.frase, { motivo: fechar.motivo ? t(fechar.motivo) : '' });
});
const sugestaoNaLinha = computed(
  () =>
    props.ia &&
    props.sugestao?.to_stage_name &&
    !tiposNoPasso.value.includes('sugestao')
);

// ——— Assunto (#1498): prioridade e há quanto tempo está aberto; na
// Cobrança, também o valor a receber, o vencimento e a promessa.
const atender = computed(() => props.jeito.atender.value);
const cobranca = computed(() => props.jeito.cobranca.value);
const prioridade = computed(() =>
  t(`CRM_CARD.URGENCIA.${URGENCIA[props.card.priority] || 'MEDIUM'}`)
);
const tempoAberto = computed(() =>
  props.card.created_at ? props.jeito.tempoAberto(props.card.created_at) : ''
);
// "2026-10-20" é um dia, não um instante: lido na hora local.
const diaLocal = texto => {
  const [ano, mes, dia] = texto.slice(0, 10).split('-').map(Number);
  return new Date(ano, mes - 1, dia);
};
const DIA_MS = 86400000;
const diasDaqui = data => {
  const hoje = new Date();
  const a = new Date(data.getFullYear(), data.getMonth(), data.getDate());
  const b = new Date(hoje.getFullYear(), hoje.getMonth(), hoje.getDate());
  return Math.round((a - b) / DIA_MS);
};
// "hoje", "amanhã", "ontem" ou "em 9 de outubro".
const diaFalado = data =>
  Math.abs(diasDaqui(data)) <= 1
    ? props.formato.dia(data)
    : t(`${R}.EM_DIA`, { dia: props.formato.diaCurto(data) });
// O vencimento é um dia (o campo não tem hora): lido pela data, não como
// instante, para não cair no dia anterior no fuso da conta.
const vencimento = computed(() =>
  props.card.expected_close_at
    ? diaLocal(String(props.card.expected_close_at))
    : null
);
const promessa = computed(() => {
  const dia = promessaDoCard(props.card);
  return dia ? diaFalado(diaLocal(dia)) : '';
});
// #2075 — valor que a pessoa não vê (sem a chave de valores): a frase diz isso, nunca "R$ 0".
const valorOculto = computed(() => Boolean(props.card.value_hidden));
const fraseNegocio = computed(() => {
  if (valorOculto.value) return `${R}.NEGOCIO_VALOR_OCULTO`;
  return props.card.value_cents
    ? `${R}.NEGOCIO_FRASE`
    : `${R}.NEGOCIO_SEM_VALOR`;
});
const fraseCobranca = computed(() => {
  if (!vencimento.value) return `${R}.COBRANCA_SEM_DATA`;
  return diasDaqui(vencimento.value) < 0
    ? `${R}.COBRANCA_VENCEU`
    : `${R}.COBRANCA_FRASE`;
});
const cartaoNegocio = computed(() => {
  if (cobranca.value)
    return { icone: 'i-lucide-receipt', titulo: t(`${R}.ASSUNTO`) };
  if (atender.value)
    return {
      icone: 'i-lucide-message-square-text',
      titulo: t(`${R}.ASSUNTO`),
    };
  return { icone: 'i-lucide-briefcase-business', titulo: t(`${R}.NEGOCIO`) };
});

// ——— Agenda: reunião e retornos juntos, por data ———
const ABERTOS = ['pending', 'overdue'];
const agora = new Date();
const agenda = computed(() => {
  const itens = props.retornos
    .filter(item => ABERTOS.includes(item.status))
    .map(item => ({
      chave: `r${item.id}`,
      quando: new Date(item.due_at),
      titulo: item.title,
      atrasado: atrasado(item, agora),
      mostrado: retornosNoPasso.value.includes(item.id),
    }));
  if (props.reuniao)
    itens.push({
      chave: 'reuniao',
      quando: new Date(props.reuniao.starts_at),
      titulo: props.reuniao.title || t(`${R}.REUNIAO`),
      reuniao: true,
      mostrado: reuniaoNoPasso.value,
    });
  return itens.sort((a, b) => a.quando - b.quando);
});
const agendaVisivel = computed(() =>
  agenda.value.filter(item => !item.mostrado)
);
const agendaLinhas = computed(() =>
  agendaVisivel.value.slice(0, MAX_AGENDA).map(item => ({
    ...item,
    chaveFrase: item.atrasado
      ? 'AGENDA_ATRASADO'
      : `AGENDA_${item.reuniao ? 'REUNIAO' : 'RETORNO'}`,
    texto: props.formato.quando(item.quando),
  }))
);
const agendaResto = computed(
  () => agendaVisivel.value.length - agendaLinhas.value.length
);
const agendaVazia = computed(() =>
  agenda.value.length ? `${R}.AGENDA_NADA_MAIS` : `${R}.AGENDA_NADA`
);
const acaoAgenda = computed(() => {
  if (!props.podeGerenciar) return 'ver';
  return agenda.value.length ? 'alterar' : 'marcar';
});

// ——— Conversa ———
const conversaPrincipal = computed(
  () =>
    props.conversas.find(item => item.is_primary) || props.conversas[0] || {}
);
const semCaixa = t('CRM_KANBAN.DRAWER.NO_INBOX');
const tituloConversa = computed(() =>
  props.conversas.length
    ? t(
        `${R}.CONVERSA_N`,
        { n: props.conversas.length },
        props.conversas.length
      )
    : t(`${R}.CONVERSA`)
);
const temConversa = computed(() =>
  Boolean(props.card.conversation?.display_id)
);
</script>

<template>
  <div class="flex flex-col gap-3">
    <div class="grid gap-3 xl:grid-cols-2">
      <CardCartao
        parte="contato"
        icone="i-lucide-contact-round"
        tom="bg-n-teal-3 text-n-teal-11"
        :titulo="t(`${R}.${podeVerContatos ? 'CONTATO_EMPRESA' : 'CONTATO'}`)"
        :acao="
          podeVerContatos && (podeGerenciar || podeRegistros)
            ? 'alterar'
            : 'ver'
        "
        :rotulo-acao="t(`${R}.CONTATO`)"
        @abrir="$emit('abrir', 'contato')"
      >
        <template #titulo>
          <span class="inline-flex flex-wrap items-center gap-2">
            {{ t(`${R}.${podeVerContatos ? 'CONTATO_EMPRESA' : 'CONTATO'}`) }}
            <CustomerBadge
              v-if="contato"
              :contact="contato"
              show-since
              data-resumo-cliente
            />
          </span>
        </template>
        <I18nT
          v-if="contato"
          :keypath="`${R}.CONTATO_FRASE`"
          tag="p"
          scope="global"
          class="mb-0"
        >
          <template #nome>
            <strong class="font-semibold">{{ contato.name || nome }}</strong>
          </template>
          <template #telefone>
            {{
              formatClientPhone(contato.phone_number) ||
              contato.email ||
              t(`${R}.SEM_TELEFONE`)
            }}
          </template>
        </I18nT>
        <p v-else class="mb-0">
          {{ t(atender ? `${R}.SEM_CONTATO_ATENDER` : `${R}.SEM_CONTATO`) }}
        </p>
        <template #extra>
          <div
            v-if="mostraEmpresa"
            data-resumo-empresa
            class="flex min-h-11 items-center gap-2 border-t border-n-weak pt-2 text-[0.9375rem] text-n-slate-12"
          >
            <span
              class="i-lucide-building-2 size-4 shrink-0 text-n-slate-11"
              aria-hidden="true"
            />
            <span class="min-w-0 flex-1">
              <template v-if="empresa">
                {{ t(`${R}.EMPRESA`) }}
                <strong class="font-semibold">{{ empresa }}</strong>
              </template>
              <span v-else class="text-n-slate-11">
                {{ t(`${R}.SEM_EMPRESA`) }}
              </span>
            </span>
            <Button
              data-card-abrir="empresa"
              :label="
                podeRegistros && contato
                  ? t('CRM_CARD.ALTERAR')
                  : t('CRM_CARD.VER')
              "
              :aria-label="
                t('CRM_CARD.ALTERAR_PARTE', { parte: t(`${R}.EMPRESA_PARTE`) })
              "
              slate
              ghost
              sm
              class="!min-h-11 shrink-0"
              @click="$emit('abrir', 'empresa')"
            />
          </div>
          <div
            v-if="contato && podeRegistros"
            data-resumo-cliente-acao
            class="-mt-1 flex flex-wrap items-center gap-2 text-sm text-n-slate-11"
          >
            <span v-if="ehCliente" class="min-w-0 flex-1">
              {{ t(`${R}.JA_COMPROU`) }}
            </span>
            <Button
              :label="
                ehCliente
                  ? t(`${R}.DESFAZER_CLIENTE`)
                  : t(`${R}.MARCAR_CLIENTE`)
              "
              :icon="ehCliente ? '' : 'i-lucide-badge-check'"
              :color="ehCliente ? 'slate' : 'teal'"
              variant="ghost"
              sm
              class="!min-h-11 shrink-0"
              :class="{ '-ms-3': !ehCliente }"
              @click="$emit('cliente', !ehCliente)"
            />
          </div>
        </template>
      </CardCartao>

      <CardCartao
        parte="negocio"
        :icone="cartaoNegocio.icone"
        tom="bg-n-iris-3 text-n-iris-11"
        :titulo="cartaoNegocio.titulo"
        :acao="podeGerenciar ? 'alterar' : 'ver'"
        @abrir="$emit('abrir', 'negocio')"
      >
        <p v-if="cobranca" class="mb-0" data-resumo-assunto>
          <I18nT :keypath="fraseCobranca" tag="span" scope="global">
            <template #titulo>
              <strong class="font-semibold">{{ card.title }}</strong>
            </template>
            <template #valor>
              <strong class="font-semibold">
                {{
                  valorOculto
                    ? t(`${R}.VALOR_OCULTO`)
                    : formato.dinheiro(card.value_cents, card.currency)
                }}
              </strong>
            </template>
            <template #vencimento>
              <strong class="font-semibold">
                {{ vencimento ? diaFalado(vencimento) : '' }}
              </strong>
            </template>
          </I18nT>
          <template v-if="promessa">
            {{ ' ' }}
            <I18nT :keypath="`${R}.PROMESSA`" tag="span" scope="global">
              <template #dia>
                <strong class="font-semibold">{{ promessa }}</strong>
              </template>
            </I18nT>
          </template>
        </p>
        <I18nT
          v-else-if="atender"
          :keypath="
            tempoAberto ? `${R}.ASSUNTO_FRASE` : `${R}.ASSUNTO_SEM_TEMPO`
          "
          tag="p"
          scope="global"
          class="mb-0"
          data-resumo-assunto
        >
          <template #titulo>
            <strong class="font-semibold">{{ card.title }}</strong>
          </template>
          <template #prioridade>
            <strong class="font-semibold">{{ prioridade }}</strong>
          </template>
          <template #tempo>
            <strong class="font-semibold">{{ tempoAberto }}</strong>
          </template>
        </I18nT>
        <I18nT
          v-else
          :keypath="fraseNegocio"
          tag="p"
          scope="global"
          class="mb-0"
        >
          <template #titulo>
            <strong class="font-semibold">{{ card.title }}</strong>
          </template>
          <template #valor>
            <strong class="font-semibold">
              {{ formato.dinheiro(card.value_cents, card.currency) }}
            </strong>
          </template>
          <template #urgencia>
            <strong class="font-semibold">
              {{
                t(`CRM_CARD.URGENCIA.${URGENCIA[card.priority] || 'MEDIUM'}`)
              }}
            </strong>
          </template>
        </I18nT>
        <template #extra>
          <button
            type="button"
            data-resumo-dono
            class="-ms-2 flex min-h-11 w-fit max-w-full items-center gap-2 rounded-xl px-2 text-start text-sm text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
            @click="$emit('abrir', 'dono')"
          >
            <span
              class="i-lucide-user-check size-4 shrink-0"
              aria-hidden="true"
            />
            <span class="min-w-0">
              {{
                card.owner?.name
                  ? t(`${R}.CUIDA`, { nome: card.owner.name })
                  : t(`${R}.NINGUEM_CUIDA`)
              }}
            </span>
            <span
              class="i-lucide-chevron-right size-4 shrink-0 rtl:rotate-180"
              aria-hidden="true"
            />
          </button>
          <button
            type="button"
            data-resumo-etapa
            class="-ms-2 flex min-h-11 w-fit max-w-full items-center gap-2 rounded-xl px-2 text-start text-sm text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
            @click="$emit('abrir', 'etapa')"
          >
            <span
              class="i-lucide-columns-3 size-4 shrink-0"
              aria-hidden="true"
            />
            <I18nT
              v-if="posicao >= 0"
              :keypath="`${R}.ETAPA_LINHA`"
              tag="span"
              scope="global"
              class="min-w-0"
            >
              <template #etapa>
                <strong class="font-semibold text-n-slate-12">
                  {{ etapaAtual }}
                </strong>
              </template>
              <template #posicao>{{ posicao + 1 }}</template>
              <template #total>{{ etapas.length }}</template>
            </I18nT>
            <span v-else class="min-w-0">{{ etapaAtual || '…' }}</span>
            <span
              class="i-lucide-chevron-right size-4 shrink-0 rtl:rotate-180"
              aria-hidden="true"
            />
          </button>
          <p
            v-if="sugestaoNaLinha"
            data-resumo-sugestao
            class="mb-0 flex items-start gap-2 text-sm text-n-iris-11"
          >
            <span
              class="i-lucide-sparkles mt-0.5 size-4 shrink-0"
              aria-hidden="true"
            />
            {{ textoDaSugestao }}
          </p>
        </template>
      </CardCartao>

      <CardCartao
        parte="agenda"
        icone="i-lucide-calendar-clock"
        tom="bg-n-amber-3 text-n-amber-11"
        :titulo="t(`${R}.AGENDA`)"
        :alerta="agendaLinhas.some(item => item.atrasado)"
        :acao="acaoAgenda"
        @abrir="$emit('abrir', 'agenda')"
      >
        <ul v-if="agendaLinhas.length" class="m-0 flex list-none flex-col p-0">
          <li
            v-for="item in agendaLinhas"
            :key="item.chave"
            :data-agenda-item="item.atrasado ? 'atrasado' : item.chave"
            class="first-letter:uppercase"
            :class="item.atrasado ? 'font-medium text-n-ruby-11' : ''"
          >
            {{
              t(`${R}.${item.chaveFrase}`, {
                quando: item.texto,
                titulo: item.titulo,
              })
            }}
          </li>
          <li v-if="agendaResto" class="text-sm text-n-slate-11">
            {{ t(`${R}.AGENDA_MAIS`, { n: agendaResto }, agendaResto) }}
          </li>
        </ul>
        <p v-else class="mb-0">{{ t(agendaVazia) }}</p>
      </CardCartao>

      <CardCartao
        parte="conversa"
        icone="i-lucide-messages-square"
        :titulo="tituloConversa"
        :acao="temConversa && !respondeNoPasso ? '' : 'ver'"
        @abrir="$emit('abrir', 'conversas')"
      >
        <template v-if="temConversa && !respondeNoPasso" #titulo>
          <button
            type="button"
            data-card-abrir="conversa"
            class="-ms-1 inline-flex min-h-11 items-center gap-1 whitespace-nowrap rounded-lg px-1 text-sm font-medium text-n-slate-11 hover:text-n-slate-12 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
            @click="$emit('abrir', 'conversas')"
          >
            {{ tituloConversa }}
            <span
              class="i-lucide-chevron-right size-4 rtl:rotate-180"
              aria-hidden="true"
            />
          </button>
        </template>
        <template v-if="temConversa && !respondeNoPasso" #botao>
          <Button
            data-resumo-abrir-conversa
            :label="t('CRM_CARD.ABRIR_CONVERSA')"
            slate
            faded
            class="!min-h-11 shrink-0"
            @click="$emit('conversa')"
          />
        </template>
        <p v-if="!conversas.length" class="mb-0">
          {{ t(`${R}.SEM_CONVERSA`) }}
        </p>
        <template v-else>
          <p
            v-if="ia && resumo.texto"
            data-resumo-conversa
            class="mb-0 line-clamp-2"
          >
            {{ resumo.texto }}
          </p>
          <p v-else class="mb-0">
            {{
              conversaPrincipal.assignee_name
                ? t(`${R}.CONVERSA_ATENDE`, {
                    caixa: conversaPrincipal.inbox_name || semCaixa,
                    quem: conversaPrincipal.assignee_name,
                  })
                : t(`${R}.CONVERSA_SEM_ATENDENTE`, {
                    caixa: conversaPrincipal.inbox_name || semCaixa,
                  })
            }}
          </p>
        </template>
      </CardCartao>
    </div>

    <CardMaisDetalhes
      :card="card"
      :conversao="conversao"
      :formato="formato"
      :pode-arquivar="podeArquivar"
      :arquivando="arquivando"
      :atender="atender"
      @abrir="$emit('abrir', $event)"
      @arquivar="$emit('arquivar')"
    />
  </div>
</template>
