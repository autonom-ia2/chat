<script setup>
import { computed, onMounted, ref } from 'vue';
import { useRoute } from 'vue-router';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import IaDaContaHeroi from './components/IaDaContaHeroi.vue';
import CartaoChatgpt from './components/CartaoChatgpt.vue';
import CartaoChave from './components/CartaoChave.vue';
import JanelaDaChave from './components/JanelaDaChave.vue';
import { estadoDaIa } from './estadoDaIa';
import { fontesDeExemplo } from './fontesDeExemplo';

// #2472: uma tela para a IA da conta. Dois jeitos de ligar (login ChatGPT e
// chave da OpenAI); com os dois, o login vai primeiro e a chave assume quando
// ele acaba. F0: os dados vêm do adaptador de exemplo (`?demo=`).
const route = useRoute();
const fontes = ref(fontesDeExemplo(route.query.demo));

const estado = computed(() => estadoDaIa(fontes.value));
const chaveDeReserva = computed(
  () => fontes.value.chatgpt?.status === 'funcionando'
);

const janelaDaChave = ref(null);
const boasVindas = ref(null);

// No protótipo, o login volta conectado; na F2 é o retorno do callback que
// abre as boas-vindas (`?conectado=chatgpt`), só na primeira vez.
const entrarComChatgpt = () => {
  fontes.value = {
    ...fontes.value,
    chatgpt: { status: 'funcionando', email: 'dono@empresa.com.br' },
  };
  boasVindas.value?.open();
};

const desconectarChatgpt = () => {
  fontes.value = { ...fontes.value, chatgpt: null };
};

// Protótipo: chave com "semcredito" no texto simula a conta sem saldo e
// chave curta simula a recusada. Na F1 quem responde é o teste da OpenAI.
const conferirChave = ({ chave, responder }) => {
  setTimeout(() => {
    if (chave.includes('semcredito')) return responder('sem_credito');
    if (chave.length < 20) return responder('recusada');
    fontes.value = {
      ...fontes.value,
      chave: { status: 'funcionando', fim: chave.slice(-4) },
    };
    return responder('ok');
  }, 600);
};

const conferirCredito = () => {
  fontes.value = {
    ...fontes.value,
    chave: { ...fontes.value.chave, status: 'funcionando' },
  };
};

const removerChave = () => {
  fontes.value = { ...fontes.value, chave: null };
};

onMounted(() => {
  if (route.query.janela === 'chave') janelaDaChave.value?.abrir();
  if (route.query.janela === 'boas_vindas') boasVindas.value?.open();
});
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <div class="flex-1 overflow-y-auto">
      <div
        class="flex flex-col w-full gap-6 px-4 pt-8 mx-auto pb-28 max-w-5xl sm:px-8 sm:py-10"
      >
        <IaDaContaHeroi :estado="estado" />

        <div class="grid gap-6 md:grid-cols-2">
          <CartaoChatgpt
            :fonte="fontes.chatgpt"
            :disponivel="fontes.loginDisponivel"
            @entrar="entrarComChatgpt"
            @desconectar="desconectarChatgpt"
          />
          <CartaoChave
            :fonte="fontes.chave"
            :esperando-a-vez="chaveDeReserva"
            @colar="janelaDaChave?.abrir()"
            @conferir="conferirCredito"
            @remover="removerChave"
          />
        </div>
      </div>
    </div>

    <JanelaDaChave ref="janelaDaChave" @salvar="conferirChave" />

    <Dialog
      ref="boasVindas"
      :title="$t('IA_DA_CONTA.BOAS_VINDAS.TITULO')"
      :description="$t('IA_DA_CONTA.BOAS_VINDAS.TEXTO')"
      :confirm-button-label="$t('IA_DA_CONTA.BOAS_VINDAS.ENTENDI')"
      :show-cancel-button="false"
      width="md"
      @confirm="boasVindas?.close()"
    />
  </section>
</template>
