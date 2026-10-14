<script setup>
import { computed, inject, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import CampoQuando from '../CampoQuando.vue';
import CampoIdioma from '../campos/CampoIdioma.vue';
import { atalhosDeData } from '../atalhosDeData';
import CampoRepetir from '../../lembrete/CampoRepetir.vue';
import CampoQuemRecebe from '../../lembrete/CampoQuemRecebe.vue';

// #1423 — marcar um retorno, numa tela só: primeiro o nome (vazio, com
// exemplos), depois o que fazer (três cartões), quando
// (atalhos, calendário e hora, sem o campo nativo) e, se for mensagem, o texto
// e a mensagem pronta quando o WhatsApp exigir. O estado mora na gaveta
// (useCardRetorno), para o rascunho sobreviver e a prévia ver o mesmo.
defineProps({
  funil: { type: String, default: '' },
  // #1461: sem card só existe "Me lembrar"; os cartões somem.
  soLembrete: { type: Boolean, default: false },
});
const r = inject('cardRetorno');
const { t } = useI18n();
const N = 'CRM_CARD.RETORNO';

const MODO = {
  reminder_only: { chave: 'LEMBRETE', icone: 'i-lucide-bell-ring' },
  snooze_conversation: { chave: 'ESCONDER', icone: 'i-lucide-moon' },
  auto_send_message: { chave: 'MENSAGEM', icone: 'i-lucide-send' },
};

const atalhos = computed(() => atalhosDeData(t));

// #1462: "Me lembrar" só quando o aviso é para quem marca. Para outras
// pessoas, o cartão diz para quem vai.
const souEu = computed(() => {
  const { tipo } = r.form.quemRecebe;
  const { dono, eu } = r.contexto;
  return tipo === 'eu' || (tipo === 'dono' && dono.value?.id === eu.value?.id);
});
const avisaOutros = computed(
  () =>
    r.lembretesV2.value && !souEu.value && Boolean(r.previa.value.quemRecebe)
);
const tituloDoModo = modo =>
  modo === 'reminder_only' && avisaOutros.value
    ? t('CRM_LEMBRETE.MODO_OUTROS.TITULO')
    : t(`${N}.MODO.${MODO[modo].chave}.TITULO`);
const textoDoModo = modo =>
  modo === 'reminder_only' && avisaOutros.value
    ? t('CRM_LEMBRETE.MODO_OUTROS.TEXTO', { nomes: r.previa.value.quemRecebe })
    : t(`${N}.MODO.${MODO[modo].chave}.TEXTO`);
const soEstaVez = computed(() => r.edicao.value?.qual === 'esta');

const envia = computed(() => r.form.automationMode === 'auto_send_message');
const avisoJanela = computed(() => {
  if (!r.form.dueAt) return { tom: 'neutro', chave: 'JANELA.ESCOLHA_DIA' };
  if (r.carregandoJanela.value)
    return { tom: 'neutro', chave: 'JANELA.CONFERINDO' };
  if (r.textoLivreForaDas24h.value)
    return { tom: 'ok', chave: 'JANELA.LIVRE_OFICIAL' };
  // Na outra caixa não há lista: a pessoa escreve o nome da mensagem pronta.
  if (r.prontaDigitada.value)
    return { tom: 'atencao', chave: 'JANELA.SO_PRONTA_DIGITAR' };
  if (r.foraDas24h.value) return { tom: 'atencao', chave: 'JANELA.SO_PRONTA' };
  return { tom: 'ok', chave: 'JANELA.DENTRO' };
});
// Aviso de campo vazio só depois que a pessoa escreveu algo e apagou: antes
// disso, o botão Marcar retorno desligado já basta.
const mexeu = ref({ mensagem: false, titulo: false });
watch(
  () => r.form.messageBody,
  texto => {
    if (texto.trim()) mexeu.value = { ...mexeu.value, mensagem: true };
  }
);
watch(
  () => r.form.title,
  (texto, antes) => {
    if (texto !== antes) mexeu.value = { ...mexeu.value, titulo: true };
  }
);
const faltaMensagem = computed(
  () => mexeu.value.mensagem && !r.form.messageBody.trim()
);
const faltaTitulo = computed(() => mexeu.value.titulo && !r.form.title.trim());
const TOM = {
  neutro: 'border-n-weak bg-n-alpha-2 text-n-slate-12',
  ok: 'border-n-teal-6 bg-n-teal-2 text-n-teal-11',
  atencao: 'border-n-amber-7 bg-n-amber-2 text-n-amber-11',
};
</script>

<template>
  <section class="flex flex-col gap-6" data-tela="retorno-novo">
    <Input
      v-model="r.form.title"
      data-retorno-nome
      :label="t(`${N}.NOME`)"
      :placeholder="t(`${N}.TITULO_EXEMPLO`)"
      :message="faltaTitulo ? t(`${N}.TITULO_FALTA`) : t(`${N}.TITULO_DICA`)"
      :message-type="faltaTitulo ? 'error' : 'info'"
    />
    <fieldset v-if="!soLembrete" class="m-0 flex flex-col gap-2 border-0 p-0">
      <legend class="mb-1 p-0 text-base font-semibold text-n-slate-12">
        {{ t(`${N}.O_QUE`) }}
      </legend>
      <div class="grid gap-2 sm:grid-cols-3">
        <button
          v-for="modo in r.modos.value"
          :key="modo.valor"
          type="button"
          :data-modo="modo.valor"
          :aria-pressed="r.form.automationMode === modo.valor"
          :disabled="modo.desligado"
          class="flex min-h-11 flex-col items-start gap-1.5 rounded-2xl p-4 ring-1 ring-inset text-start transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9 disabled:cursor-not-allowed disabled:opacity-60"
          :class="
            r.form.automationMode === modo.valor
              ? 'bg-n-blue-2 ring-2 ring-n-blue-8'
              : 'ring-n-weak bg-n-solid-1 hover:ring-n-slate-7'
          "
          @click="r.form.automationMode = modo.valor"
        >
          <span
            class="size-5 text-n-blue-11"
            :class="MODO[modo.valor].icone"
            aria-hidden="true"
          />
          <span class="text-[0.9375rem] font-semibold text-n-slate-12">
            {{ tituloDoModo(modo.valor) }}
          </span>
          <span class="text-sm text-n-slate-11">
            {{
              modo.desligado
                ? t(`${N}.PRECISA_CONVERSA`)
                : textoDoModo(modo.valor)
            }}
          </span>
        </button>
      </div>
    </fieldset>

    <CampoQuando
      v-model="r.form.dueAt"
      data-retorno-quando
      :rotulo="t(`${N}.QUANDO`)"
      :atalhos="atalhos"
    />
    <p
      v-if="r.lembretesV2.value"
      class="-mt-4 mb-0 text-xs text-n-slate-11"
      data-retorno-fuso
    >
      {{
        t('CRM_LEMBRETE.FUSO_DA_CONTA', { fuso: r.contexto.fusoRotulo.value })
      }}
    </p>

    <!-- #1460: repetir. -->
    <CampoRepetir
      v-if="
        r.lembretesV2.value &&
        !soEstaVez &&
        r.form.automationMode === 'reminder_only'
      "
      v-model="r.form.repetir"
      :inicio="r.form.dueAt"
      :sem-uma-vez="r.edicao.value?.qual === 'proximas'"
      :fuso="r.contexto.fusoRotulo.value"
    />
    <!-- #1462: quem recebe o aviso. -->
    <CampoQuemRecebe
      v-if="r.lembretesV2.value"
      v-model="r.form.quemRecebe"
      :dono="r.contexto.dono.value"
      :eu="r.contexto.eu.value"
      :agentes="r.contexto.agentes.value"
      :barrados="r.contexto.barrados.value"
      :funil="funil"
      :times="r.contexto.times.value"
      :membros="r.contexto.membros.value"
    />

    <section v-if="envia" class="flex flex-col gap-4" data-retorno-mensagem>
      <p
        role="status"
        :data-janela="avisoJanela.chave"
        class="mb-0 rounded-xl border p-3 text-[0.9375rem]"
        :class="TOM[avisoJanela.tom]"
      >
        {{ t(`${N}.${avisoJanela.chave}`) }}
      </p>
      <TextArea
        v-model="r.form.messageBody"
        :label="
          t(
            r.prontaObrigatoria.value
              ? `${N}.SEU_TEXTO_SE_RESPONDER`
              : `${N}.SEU_TEXTO`
          )
        "
        :placeholder="t(`${N}.SEU_TEXTO_EXEMPLO`)"
        :max-length="4000"
        auto-height
        min-height="5rem"
        :message="faltaMensagem ? t(`${N}.SEU_TEXTO_FALTA`) : ''"
        :message-type="faltaMensagem ? 'error' : 'info'"
      />

      <fieldset
        v-if="r.foraDas24h.value && !r.prontaDigitada.value"
        class="m-0 flex flex-col gap-2 border-0 p-0"
      >
        <legend class="mb-1 p-0 text-sm font-medium text-n-slate-12">
          {{
            t(
              r.prontaObrigatoria.value ? `${N}.PRONTA` : `${N}.PRONTA_OPCIONAL`
            )
          }}
        </legend>
        <p
          v-if="r.carregandoModelos.value"
          role="status"
          class="mb-0 text-sm text-n-slate-11"
        >
          {{ t('CRM_CARD.CARREGANDO') }}
        </p>
        <button
          v-if="!r.prontaObrigatoria.value"
          type="button"
          :aria-pressed="!r.prontaEscolhida.value"
          class="min-h-11 rounded-2xl p-4 ring-1 ring-inset text-start text-[0.9375rem] transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
          :class="
            !r.prontaEscolhida.value
              ? 'ring-n-blue-8 bg-n-blue-2'
              : 'ring-n-weak bg-n-solid-1'
          "
          @click="r.escolherPronta('')"
        >
          {{ t(`${N}.SEM_PRONTA`) }}
        </button>
        <button
          v-for="pronta in r.prontas.value"
          :key="pronta.chave"
          type="button"
          :data-pronta="pronta.nome"
          :aria-pressed="r.prontaEscolhida.value?.chave === pronta.chave"
          class="flex min-h-11 flex-col gap-1 rounded-2xl p-4 ring-1 ring-inset text-start transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
          :class="
            r.prontaEscolhida.value?.chave === pronta.chave
              ? 'bg-n-blue-2 ring-2 ring-n-blue-8'
              : 'ring-n-weak bg-n-solid-1 hover:ring-n-slate-7'
          "
          @click="r.escolherPronta(pronta.chave)"
        >
          <span class="text-[0.9375rem] text-n-slate-12">
            {{ pronta.texto ? `“${pronta.texto}”` : pronta.nome }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{
              pronta.idioma ? `${pronta.nome} · ${pronta.idioma}` : pronta.nome
            }}
          </span>
        </button>
        <p
          v-if="!r.prontas.value.length && !r.carregandoModelos.value"
          class="mb-0 rounded-xl bg-n-alpha-2 p-3 text-sm text-n-slate-11"
        >
          {{ t(`${N}.NENHUMA_PRONTA`) }}
        </p>
      </fieldset>
      <div v-else-if="r.prontaDigitada.value" class="grid gap-3 sm:grid-cols-2">
        <Input
          v-model="r.form.templateName"
          :label="t(`${N}.PRONTA_NOME`)"
          :placeholder="t(`${N}.PRONTA_NOME_EXEMPLO`)"
          :message="t(`${N}.PRONTA_NOME_DICA`)"
        />
        <CampoIdioma
          v-model="r.form.templateLanguage"
          :rotulo="t(`${N}.PRONTA_IDIOMA`)"
        />
      </div>
    </section>

    <TextArea
      v-model="r.form.description"
      :label="t(`${N}.ANOTACAO`)"
      :placeholder="t(`${N}.ANOTACAO_EXEMPLO`)"
      :max-length="2000"
      auto-height
      min-height="4rem"
    />
  </section>
</template>
