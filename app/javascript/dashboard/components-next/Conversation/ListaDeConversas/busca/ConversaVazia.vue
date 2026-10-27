<script setup>
// #2211 (decisão do Rodrigo, rodada 4) — "Escrever" na busca abre a própria tela da conversa,
// vazia: cabeçalho com o nome e o telefone, o fundo da conversa sem mensagens e a caixa de
// resposta embaixo. Uma caixa possível: já pronta para escrever. Mais de uma: a gaveta
// "Por onde mandar?" abre primeiro, e a caixa escolhida fica no cabeçalho com "Trocar".
//
// As regras são as da Nova conversa (#1459), pelos mesmos composables: as caixas do contato
// (useNovaConversaContato), continuar a conversa que já existe e a oculta (#1505,
// useContinuarConversa), tipo de mensagem, janela de 24 h, modelo, Híbrido e e-mail
// (useNovaConversa). Quem só lê conversas (#1800) nem chega aqui (usePodeComecarConversa).
//
// Telefone novo: o contato só nasce ao enviar. Até lá, a tela mostra o número como nome e as
// caixas que mandam para telefone; no envio, cria o contato e o servidor confirma a caixa.
// Enviou: a tela vira a conversa criada.
import { computed, nextTick, onMounted, ref, useTemplateRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import camelcaseKeys from 'camelcase-keys';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { conversationUrl, frontendURL } from 'dashboard/helper/URLHelper';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';
import ContactAPI from 'dashboard/api/contacts';
import { emitter } from 'shared/helpers/mitt';
import {
  fetchContactableInboxes,
  mergeInboxDetails,
} from 'dashboard/components-next/NewConversation/helpers/composeConversationHelper';
import { useNovaConversaContato } from 'dashboard/components-next/NovaConversa/useNovaConversaContato';
import { useContinuarConversa } from 'dashboard/components-next/NovaConversa/useContinuarConversa';
import { useNovaConversa } from 'dashboard/components-next/NovaConversa/useNovaConversa';
import {
  PELES,
  fornecerPele,
  peleDaCaixa,
} from 'dashboard/components-next/conversa-canal/pele';
import {
  CAIXA_DE_RESPOSTA,
  FUNDO_DA_CONVERSA,
} from 'dashboard/components-next/conversa-canal/visualWhatsapp';
import {
  nomeOuTelefone,
  telefoneLegivel,
} from 'dashboard/components-next/conversa-canal/mais/telefoneDoPais';
import CabecalhoDaConversaVazia from './CabecalhoDaConversaVazia.vue';
import CaixaDaConversaVazia from './CaixaDaConversaVazia.vue';
import PorOndeMandar from './PorOndeMandar.vue';
import {
  caixaJaEscolhida,
  caixasParaTelefone,
  semInstagram,
  temInstagram,
} from './caixasDaConversaVazia';
import { BUSCA_DESATUALIZADA } from './buscaDaLista';

const props = defineProps({
  contatoId: { type: [String, Number], default: '' },
  telefone: { type: String, default: '' },
});
const emit = defineEmits(['voltar']);

const { t } = useI18n();
const store = useStore();
const router = useRouter();
const { isCloudFeatureEnabled } = useAccount();
const caixasDaConta = useMapGetter('inboxes/getInboxes');
const caixaPorId = useMapGetter('inboxes/getInbox');
const contaId = useMapGetter('getCurrentAccountId');

const doContato = useNovaConversaContato();
const peloTelefone = computed(() => Boolean(props.telefone));

// Telefone novo: um contato provisório até o envio; depois, o criado.
const PROVISORIO = 'telefone-novo';
const contatoDoTelefone = ref(null);
const contato = computed(() =>
  peloTelefone.value ? contatoDoTelefone.value : doContato.contato.value
);
const caixas = computed(() =>
  peloTelefone.value
    ? caixasParaTelefone(caixasDaConta.value)
    : semInstagram(doContato.canais.value)
);
const caixaId = ref(null);
// A caixa do envio do telefone novo, com o source_id do contato criado.
const caixaDoEnvio = ref(null);
const canal = computed(
  () =>
    caixaDoEnvio.value ||
    caixas.value.find(caixa => String(caixa.id) === String(caixaId.value)) ||
    null
);

const continuar = useContinuarConversa({ contato, canal });
const nova = useNovaConversa({
  contato,
  canal,
  continuar,
  donoDoRascunho: computed(() => props.telefone || contato.value?.id || null),
});
const { form } = nova;

const erroAoCarregar = ref(false);
const carregando = computed(
  () =>
    !peloTelefone.value &&
    !erroAoCarregar.value &&
    (!contato.value || doContato.carregandoCanais.value)
);
const gavetaAberta = ref(false);
const criandoContato = ref(false);
const caixaDeResposta = useTemplateRef('caixaDeResposta');

const nome = computed(() =>
  peloTelefone.value
    ? telefoneLegivel(props.telefone)
    : nomeOuTelefone(contato.value?.name, contato.value?.phoneNumber)
);
const comInstagram = computed(() => temInstagram(caixasDaConta.value));
const semCaixa = computed(
  () => !carregando.value && !erroAoCarregar.value && !caixas.value.length
);
// Sem caixa porque falta telefone e e-mail no contato: a tela diz isso e leva a completar o contato.
const semComoFalar = computed(
  () =>
    !peloTelefone.value && !contato.value?.phoneNumber && !contato.value?.email
);

// O fundo e o topo da conversa do WhatsApp, quando a conta usa a cara do canal (#1702).
const caraDoWhatsapp = computed(() =>
  Boolean(
    canal.value &&
      peleDaCaixa(
        caixaPorId.value(canal.value.id),
        isCloudFeatureEnabled(FEATURE_FLAGS.CONVERSA_CARA_DO_CANAL)
      )
  )
);
// A conversa vazia fornece a pele como a tela da conversa (usePeleDaConversa): a caixa de
// resposta e a barra de baixo leem dela.
fornecerPele(computed(() => (caraDoWhatsapp.value ? PELES.WHATSAPP : null)));
const caixaDaStore = computed(() =>
  canal.value ? caixaPorId.value(canal.value.id) || {} : {}
);
const para = computed(() =>
  contato.value ? { nome: nome.value, email: contato.value.email || '' } : null
);

const carregarContato = async () => {
  erroAoCarregar.value = false;
  try {
    const { data } = await ContactAPI.show(props.contatoId);
    await doContato.escolherContato(
      camelcaseKeys(data.payload, { deep: true })
    );
    if (doContato.erroNosCanais.value) erroAoCarregar.value = true;
  } catch {
    erroAoCarregar.value = true;
  }
};

const comecar = () => {
  caixaId.value = null;
  caixaDoEnvio.value = null;
  gavetaAberta.value = false;
  if (peloTelefone.value) {
    contatoDoTelefone.value = {
      id: PROVISORIO,
      name: telefoneLegivel(props.telefone),
      phoneNumber: props.telefone,
    };
    return;
  }
  carregarContato();
};

onMounted(() => {
  // Os modelos aprovados há pouco aparecem (mesmo pedido da Nova conversa).
  store.dispatch('inboxes/get');
});
watch(() => [props.contatoId, props.telefone], comecar, { immediate: true });

// As caixas chegaram: uma só já vem escolhida; mais de uma, a gaveta abre.
watch(
  () =>
    `${contato.value?.id ?? ''}|${caixas.value.map(caixa => caixa.id).join(',')}`,
  () => {
    if (caixaId.value) return;
    caixaId.value = caixaJaEscolhida(caixas.value);
    gavetaAberta.value = !caixaId.value && caixas.value.length > 1;
  },
  { immediate: true }
);

const escolherCaixa = id => {
  caixaId.value = id;
  gavetaAberta.value = false;
};

// Telefone novo: cria o contato e pede ao servidor a caixa escolhida para ele (com o
// source_id). O que foi escrito fica: o dono do rascunho é o número.
const criarContatoDoTelefone = async () => {
  criandoContato.value = true;
  try {
    const { data } = await ContactAPI.create({
      name: telefoneLegivel(props.telefone),
      phone_number: props.telefone,
    });
    const criado = camelcaseKeys(data.payload.contact, { deep: true });
    const alcancaveis = mergeInboxDetails(
      await fetchContactableInboxes(criado.id),
      caixasDaConta.value
    );
    const daCaixa = alcancaveis.find(
      caixa => String(caixa.id) === String(caixaId.value)
    );
    contatoDoTelefone.value = criado;
    if (!daCaixa) throw new Error('caixa');
    caixaDoEnvio.value = daCaixa;
    await nextTick();
    return true;
  } catch (falha) {
    // Erro do servidor (telefone já usado, inválido) com texto: ele; senão, o nosso.
    const doServidor = falha?.response ? parseAPIErrorResponse(falha) : '';
    useAlert(
      typeof doServidor === 'string' && doServidor
        ? doServidor
        : t('LISTA_DE_CONVERSAS.CONVERSA_VAZIA.ERRO_CONTATO')
    );
    return false;
  } finally {
    criandoContato.value = false;
  }
};

const mandar = async () => {
  if (nova.falta.value || nova.enviando.value || criandoContato.value) return;
  const precisaCriar =
    peloTelefone.value && contatoDoTelefone.value?.id === PROVISORIO;
  if (precisaCriar && !(await criarContatoDoTelefone())) return;
  nova.enviar(() => caixaDeResposta.value?.montar() ?? null);
};

// Enviou: a tela vira a conversa. A oculta (#1505) a pessoa não pode abrir: avisa e volta.
watch(nova.enviada, enviada => {
  if (!enviada) return;
  emitter.emit(BUSCA_DESATUALIZADA);
  if (enviada.oculta) {
    useAlert(t('LISTA_DE_CONVERSAS.CONVERSA_VAZIA.ENVIADA_OCULTA'));
    emit('voltar');
    return;
  }
  router.push({
    path: frontendURL(
      conversationUrl({ accountId: enviada.contaId, id: enviada.id })
    ),
  });
});

watch(nova.erro, erro => {
  if (erro) useAlert(erro);
});
</script>

<template>
  <section
    class="relative flex flex-col flex-1 min-w-0 h-full bg-n-surface-1"
    data-conversa-vazia
  >
    <CabecalhoDaConversaVazia
      :nome="nome"
      :foto="contato?.thumbnail || ''"
      :caixa="canal"
      :com-trocar="Boolean(canal) && caixas.length > 1"
      :cara-do-whatsapp="caraDoWhatsapp"
      @voltar="emit('voltar')"
      @trocar="gavetaAberta = true"
    />

    <div class="relative flex flex-col flex-1 min-h-0">
      <!-- Onde ficariam as mensagens: o fundo da conversa (com a pele, o papel do app). -->
      <div
        class="flex flex-col items-center justify-center flex-1 min-h-0 gap-3 p-6 text-center"
        :class="caraDoWhatsapp ? FUNDO_DA_CONVERSA : 'bg-n-surface-1'"
        data-fundo-da-conversa
      >
        <p v-if="carregando" class="m-0 text-sm text-n-slate-11">
          {{ t('LISTA_DE_CONVERSAS.CONVERSA_VAZIA.CARREGANDO') }}
        </p>
        <p v-else-if="erroAoCarregar" class="m-0 text-sm text-n-slate-11">
          {{ t('LISTA_DE_CONVERSAS.CONVERSA_VAZIA.ERRO') }}
          <button
            type="button"
            class="font-medium bg-transparent border-0 min-h-11 text-n-blue-11"
            @click="comecar"
          >
            {{ t('LISTA_DE_CONVERSAS.CONVERSA_VAZIA.TENTAR') }}
          </button>
        </p>
        <p
          v-else-if="semCaixa"
          class="flex flex-col items-center gap-1 m-0 text-sm text-n-slate-11"
          data-sem-caixa
        >
          {{
            semComoFalar
              ? t('LISTA_DE_CONVERSAS.CONVERSA_VAZIA.SEM_CAIXA', { nome })
              : t('LISTA_DE_CONVERSAS.CONVERSA_VAZIA.SEM_CAIXA_NA_CONTA', {
                  nome,
                })
          }}
          <RouterLink
            v-if="semComoFalar && contato?.id"
            :to="{
              name: 'contacts_edit',
              params: { accountId: contaId, contactId: contato.id },
            }"
            class="inline-flex items-center font-medium min-h-11 text-n-blue-11"
            data-completar-contato
          >
            {{ t('LISTA_DE_CONVERSAS.CONVERSA_VAZIA.COMPLETAR_CONTATO') }}
          </RouterLink>
        </p>
        <button
          v-else-if="!canal"
          type="button"
          data-escolher-caixa
          class="px-4 text-sm font-medium border-0 rounded-full shadow-sm min-h-11 bg-n-solid-1 text-n-blue-11"
          @click="gavetaAberta = true"
        >
          {{ t('LISTA_DE_CONVERSAS.CONVERSA_VAZIA.ESCOLHER_CAIXA') }}
        </button>
      </div>

      <!-- A barra da resposta, como na conversa (MessagesView): com a pele, a do app. -->
      <div
        v-if="canal && !continuar.esperando.value"
        class="relative flex flex-col bg-n-surface-1"
        :class="caraDoWhatsapp && CAIXA_DE_RESPOSTA.barra"
      >
        <CaixaDaConversaVazia
          ref="caixaDeResposta"
          :key="`${canal.id}-${nova.tipo.value}`"
          v-model:mensagem="form.mensagem"
          v-model:assunto="form.assunto"
          v-model:cc="form.cc"
          v-model:bcc="form.bcc"
          v-model:anexos="form.anexos"
          v-model:modelo="form.modelo"
          :canal="canal"
          :caixa="caixaDaStore"
          :para="para"
          :tipo="nova.tipo.value"
          :com-modelo="nova.comModelo.value"
          :caixa-do-whatsapp="nova.caixaDoWhatsapp.value"
          :so-texto="nova.soTexto.value"
          :assinatura="nova.assinatura.value || ''"
          :com-assinatura="nova.comAssinatura.value"
          :pode-enviar="!nova.falta.value"
          :enviando="nova.enviando.value || criandoContato"
          @enviar="mandar"
          @enviar-pronta="nova.enviarPronta"
          @update:campos-prontos="form.camposProntos = $event"
          @update:texto-do-modelo="form.textoDoModelo = $event"
        />
      </div>

      <PorOndeMandar
        v-if="gavetaAberta"
        :caixas="caixas"
        :escolhida="caixaId"
        :sem-instagram="comInstagram"
        @escolher="escolherCaixa"
        @fechar="gavetaAberta = false"
      />
    </div>
  </section>
</template>
