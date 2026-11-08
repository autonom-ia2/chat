<script setup>
// #2211 — a lista vira o resultado da busca, em três seções: Conversas (uma por pessoa, com o card
// da lista e "Resolvida" quando for o caso), Mensagens (trecho com destaque) e Pessoas sem conversa.
// Telefone que ninguém tem: "Começar conversa com +55 …". Quem só lê conversas (#1800) não
// vê "Escrever" nem a oferta do telefone.
import { computed, provide } from 'vue';
import { I18nT, useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { usePodeComecarConversa } from 'dashboard/components-next/NovaConversa/usePodeComecarConversa';
import ConversationItem from 'dashboard/components/ConversationItem.vue';
import ItemDaMensagem from './ItemDaMensagem.vue';
import ItemDaPessoa from './ItemDaPessoa.vue';
import { telefoneLegivel } from 'dashboard/components-next/conversa-canal/mais/telefoneDoPais';

const props = defineProps({
  resultado: { type: Object, required: true },
  buscado: { type: String, default: '' },
  texto: { type: String, default: '' },
  carregando: { type: Boolean, default: false },
  erro: { type: Boolean, default: false },
});
const emit = defineEmits(['tentar']);

// O card da lista marca "Resolvida" só aqui, na busca.
provide('cardNaBusca', true);

const { t } = useI18n();
const router = useRouter();
const contaId = useMapGetter('getCurrentAccountId');
const podeComecar = usePodeComecarConversa();

const { conversas, mensagens, pessoas, telefoneNovo, emailNovo } =
  Object.fromEntries(
    ['conversas', 'mensagens', 'pessoas', 'telefoneNovo', 'emailNovo'].map(
      chave => [chave, computed(() => props.resultado[chave])]
    )
  );

// As caixas em que dá para começar conversa com o telefone ou o e-mail novo (caixas_para_comecar,
// o InboxPolicy#show? do servidor). Sem nenhuma, a oferta não aparece: o envio gravaria o contato e
// falharia na conversa.
const caixasParaComecar = computed(
  () => props.resultado.caixasParaComecar || []
);
const podeOferecer = computed(
  () => podeComecar.value && caixasParaComecar.value.length > 0
);
const ofereceTelefone = computed(() =>
  Boolean(telefoneNovo.value && podeOferecer.value)
);
const ofereceEmail = computed(() =>
  Boolean(emailNovo.value && podeOferecer.value)
);

const vazio = computed(
  () =>
    !conversas.value.length &&
    !mensagens.value.length &&
    !pessoas.value.length &&
    !ofereceTelefone.value &&
    !ofereceEmail.value &&
    !props.resultado.parcial
);
const respondeuAoTexto = computed(
  () => props.buscado && props.buscado === props.texto.trim()
);

// "Escrever": a área da direita vira a conversa vazia com a pessoa (ConversaVazia).
const abrirConversaVazia = query => {
  router.push({ name: 'home', params: { accountId: contaId.value }, query });
};
const comecarCom = contatoId => abrirConversaVazia({ comecar: contatoId });
// Telefone novo: o contato só nasce ao enviar, na conversa vazia.
// As caixas em que o número já pode receber texto livre (#2257) vão junto: a conversa vazia começa no
// tipo certo (texto livre ou modelo). As caixas em que dá para começar vão junto (?caixas=).
const caixas = () => caixasParaComecar.value.join(',');
const comecarComTelefone = () => {
  const livres = props.resultado.textoLivreNasCaixas || [];
  abrirConversaVazia({
    telefone: telefoneNovo.value,
    ...(livres.length ? { livre: livres.join(',') } : {}),
    caixas: caixas(),
  });
};
// E-mail novo (#2211): o servidor diz que é e-mail; o contato só nasce ao enviar.
const comecarComEmail = () =>
  abrirConversaVazia({ email: emailNovo.value, caixas: caixas() });

// O que o leitor de tela ouve, numa região à parte: buscando, quantos achou ou nada.
const total = computed(
  () =>
    conversas.value.length +
    mensagens.value.length +
    pessoas.value.length +
    (ofereceTelefone.value ? 1 : 0) +
    (ofereceEmail.value ? 1 : 0)
);
const anuncio = computed(() => {
  if (props.erro) return t('LISTA_DE_CONVERSAS.BUSCA.ERRO');
  if (props.carregando || !respondeuAoTexto.value)
    return t('LISTA_DE_CONVERSAS.BUSCA.BUSCANDO');
  if (vazio.value)
    return t('LISTA_DE_CONVERSAS.BUSCA.NADA', { texto: props.buscado });
  return t(
    'LISTA_DE_CONVERSAS.BUSCA.RESULTADOS',
    { count: total.value },
    total.value
  );
});
</script>

<template>
  <div
    class="flex-1 min-h-0 pb-20 overflow-y-auto md:pb-0"
    data-resultado-da-busca
  >
    <p role="status" class="sr-only" data-anuncio-da-busca>{{ anuncio }}</p>
    <p
      v-if="erro"
      class="px-4 py-6 m-0 text-sm text-center text-n-slate-11"
      data-erro-da-busca
    >
      {{ t('LISTA_DE_CONVERSAS.BUSCA.ERRO') }}
      <button
        type="button"
        class="p-0 font-medium bg-transparent border-0 text-n-blue-11 min-h-11"
        @click="emit('tentar')"
      >
        {{ t('LISTA_DE_CONVERSAS.BUSCA.TENTAR') }}
      </button>
    </p>
    <p
      v-else-if="!respondeuAoTexto && vazio"
      class="px-4 py-6 m-0 text-sm text-center text-n-slate-11"
      data-buscando
    >
      {{ t('LISTA_DE_CONVERSAS.BUSCA.BUSCANDO') }}
    </p>
    <p
      v-else-if="vazio"
      class="px-4 py-6 m-0 text-sm text-center text-n-slate-11"
      data-nada-achado
    >
      {{ t('LISTA_DE_CONVERSAS.BUSCA.NADA', { texto: buscado }) }}
    </p>
    <template v-else>
      <p
        v-if="resultado.parcial"
        class="px-4 py-2 m-0 text-xs border-b text-n-slate-11 border-n-weak"
        data-busca-parcial
      >
        {{ t('LISTA_DE_CONVERSAS.BUSCA.PARCIAL') }}
      </p>
      <button
        v-if="ofereceTelefone"
        type="button"
        data-comecar-com-telefone
        class="flex items-center w-full gap-3 px-4 py-3 bg-transparent border-0 border-b text-start border-n-weak hover:bg-n-alpha-1"
        @click="comecarComTelefone"
      >
        <span
          class="flex items-center justify-center flex-shrink-0 rounded-full size-9 bg-n-brand/10 text-n-brand"
          aria-hidden="true"
        >
          <span class="i-lucide-message-circle-plus size-5" />
        </span>
        <span class="flex flex-col min-w-0">
          <I18nT
            keypath="LISTA_DE_CONVERSAS.BUSCA.COMECAR_COM_TELEFONE"
            tag="span"
            class="text-sm font-medium text-n-slate-12"
          >
            <template #telefone>
              <span class="whitespace-nowrap">
                {{ telefoneLegivel(telefoneNovo) }}
              </span>
            </template>
          </I18nT>
          <span class="text-xs text-n-slate-11">
            {{ t('LISTA_DE_CONVERSAS.BUSCA.COMECAR_COM_TELEFONE_AJUDA') }}
          </span>
        </span>
      </button>
      <button
        v-if="ofereceEmail"
        type="button"
        data-comecar-com-email
        class="flex items-center w-full gap-3 px-4 py-3 bg-transparent border-0 border-b text-start border-n-weak hover:bg-n-alpha-1"
        @click="comecarComEmail"
      >
        <span
          class="flex items-center justify-center flex-shrink-0 rounded-full size-9 bg-n-brand/10 text-n-brand"
          aria-hidden="true"
        >
          <span class="i-lucide-mail-plus size-5" />
        </span>
        <span class="flex flex-col min-w-0">
          <span class="text-sm font-medium break-all text-n-slate-12">
            {{
              t('LISTA_DE_CONVERSAS.BUSCA.ESCREVER_PARA_EMAIL', {
                email: emailNovo,
              })
            }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{ t('LISTA_DE_CONVERSAS.BUSCA.ESCREVER_PARA_EMAIL_AJUDA') }}
          </span>
        </span>
      </button>
      <section v-if="conversas.length" data-secao="conversas">
        <h2
          class="px-4 pt-3 pb-1 m-0 text-xs font-semibold tracking-wide uppercase text-n-slate-11"
        >
          {{ t('LISTA_DE_CONVERSAS.BUSCA.SECOES.CONVERSAS') }}
        </h2>
        <div data-conversas-achadas>
          <ConversationItem
            v-for="conversa in conversas"
            :key="conversa.id"
            :source="conversa"
            show-assignee
          />
        </div>
      </section>
      <section v-if="mensagens.length" data-secao="mensagens">
        <h2
          class="px-4 pt-3 pb-1 m-0 text-xs font-semibold tracking-wide uppercase text-n-slate-11"
        >
          {{ t('LISTA_DE_CONVERSAS.BUSCA.SECOES.MENSAGENS') }}
        </h2>
        <ItemDaMensagem
          v-for="mensagem in mensagens"
          :key="mensagem.id"
          :mensagem="mensagem"
          :busca="buscado"
        />
      </section>
      <section v-if="pessoas.length" data-secao="pessoas">
        <h2
          class="px-4 pt-3 pb-1 m-0 text-xs font-semibold tracking-wide uppercase text-n-slate-11"
        >
          {{ t('LISTA_DE_CONVERSAS.BUSCA.SECOES.PESSOAS') }}
        </h2>
        <ItemDaPessoa
          v-for="pessoa in pessoas"
          :key="pessoa.id"
          :pessoa="pessoa"
          :pode-escrever="podeComecar"
          @comecar="comecarCom(pessoa.id)"
        />
      </section>
    </template>
  </div>
</template>
