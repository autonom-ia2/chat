<script setup>
import { computed, nextTick, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import CuidarLigado from './CuidarLigado.vue';
import CuidarDono from './CuidarDono.vue';
import { FOR_WHOM_LIMIT, MOTIVOS, useCuidado } from './useCuidado';
import { porRede } from './redes';

// Comentários que viram cliente (#2212): "Cuidar dos comentários" de um post (Seus posts, B1) ou de um anúncio (B2).
// Desligado, os três passos do dono (CuidarDono): a mensagem do privado, para quem, e como fica. Ligado ou pausado,
// o resultado, o que ficou com você e "Pausar" (CuidarLigado); "Mudar o que eu respondo" reabre os passos
// preenchidos. Os comentários que chegaram antes de ligar ficam com o dono: depois de ligar, a tela pergunta uma vez
// ("Ler e mandar" ou "Agora não"), e o botão continua no grupo deles. Nada automático.
// Os dados vêm do Painel do servidor (useCuidado). Sem `canManage`, a tela mostra o estado e esconde a escrita.
const props = defineProps({
  // { kind: 'post' | 'ad', id, perfil }
  target: { type: Object, required: true },
  // O cabeçalho: { image_url, text, network } do post ou do anúncio, quando a página já leu.
  post: { type: Object, default: null },
  // De onde a tela abriu: 'post' (o post em Seus posts) ou 'anuncio'.
  origin: { type: String, default: 'post' },
  canManage: { type: Boolean, default: false },
  // A caixa da rede, para "Ver na caixa".
  inboxPath: { type: String, default: '' },
  // No anúncio (B2), a caixa vem do servidor (Painel `inbox_id`): a página diz como vira endereço.
  inboxPathOf: { type: Function, default: null },
});

const emit = defineEmits(['back']);

const { t } = useI18n();
const router = useRouter();
const KEY = 'META_ADS_COMMENTS_AI';

const {
  painel,
  carregando,
  erro,
  motivo,
  salvando,
  falhaAoSalvar,
  carregar,
  salvar,
  pausar,
  voltar,
  previa,
  lerAntigos,
} = useCuidado(() => props.target);

const heading = ref(null);
const started = ref(null);
const oldDialog = ref(null);
const changing = ref(false);

const on = computed(() => ['on', 'paused'].includes(painel.value?.care));
const BACK_KEY = { anuncio: 'BACK_AD', post: 'BACK_POST' };
const network = computed(
  () => painel.value?.network || props.post?.network || 'instagram'
);
const NETWORK_ICON = {
  instagram: 'i-woot-instagram-color',
  facebook: 'i-ri-facebook-circle-fill text-n-blue-9',
  both: 'i-woot-instagram-color',
};
const fromKey = computed(() => {
  if (props.origin === 'anuncio') return porRede('FROM_AD', network.value);
  return network.value === 'facebook' ? 'FROM_PAGE' : 'FROM_POST';
});

// Por que não deu para ler: o código do servidor, no erro da leitura (motivo) ou no `status` do Painel que veio sem a
// lista (needs_login, meta_unavailable…). Com texto próprio quando a tela conhece o código; "Tentar de novo" só no que
// passa sozinho (a Meta fora do ar, a rede): o resto (sem post, sem caixa, sem login) não cura tentando.
const PASSAGEIROS = ['meta_unavailable'];
const genericError = computed(() =>
  t(`${KEY}.SCREEN.${props.origin === 'anuncio' ? 'ERROR_AD' : 'ERROR'}`)
);
const problemText = code =>
  MOTIVOS.includes(code)
    ? t(`${KEY}.SCREEN.PROBLEM.${code}`)
    : genericError.value;
const canRetry = code =>
  !code || !MOTIVOS.includes(code) || PASSAGEIROS.includes(code);
const painelStatus = computed(() =>
  painel.value?.status && painel.value.status !== 'ready'
    ? painel.value.status
    : null
);

const focusHeading = async () => {
  await nextTick();
  heading.value?.focus();
};

// Os comentários que chegaram antes de ligar: só quem pode mudar, com o privado liberado e nada lido ainda.
const canSendOld = computed(
  () =>
    props.canManage &&
    !changing.value &&
    painel.value?.private_available !== false &&
    !painel.value?.read_old &&
    painel.value?.unanswered > 0
);

// O aviso diz por que não gravou: sem acesso (403), o texto que o servidor recusou (422) ou o resto (rede, servidor).
const AVISO_DA_FALHA = {
  acesso: () => t(`${KEY}.SCREEN.NO_ACCESS`),
  invalid_message: () => t(`${KEY}.DONO.WHAT.TOO_LONG`),
  invalid_para_quem: () =>
    t(`${KEY}.DONO.WHO.TOO_LONG`, { max: FOR_WHOM_LIMIT }),
};
const avisarFalha = () => {
  const aviso = AVISO_DA_FALHA[falhaAoSalvar.value];
  useAlert(aviso ? aviso() : t(`${KEY}.SCREEN.SAVE_ERROR`));
};

// A frase escolhida no passo 3 vai primeiro; as outras do servidor seguem, sem repetir.
const phrasesWith = phrase => {
  const others = (painel.value?.phrases || []).filter(item => item !== phrase);
  return phrase ? [phrase, ...others] : others;
};

const finishDono = async ({ message, paraQuem, phrase }) => {
  const wasChanging = changing.value;
  // Pergunta dos antigos só depois de ligar, e só se havia o que perguntar antes de gravar.
  const askOld = canSendOld.value;
  const valeu = await salvar({
    message,
    paraQuem,
    phrases: phrasesWith(phrase),
    status: wasChanging ? undefined : 'on',
  });
  if (!valeu) {
    avisarFalha();
    return;
  }
  changing.value = false;
  focusHeading();
  if (wasChanging) {
    useAlert(t(`${KEY}.ON.SAVED`));
    return;
  }
  started.value = 'new';
  if (askOld) oldDialog.value?.open();
};

const change = () => {
  changing.value = true;
  started.value = null;
  focusHeading();
};
const leaveChanges = () => {
  changing.value = false;
  focusHeading();
};

const startOld = async () => {
  oldDialog.value?.close();
  const valeu = await lerAntigos();
  if (!valeu) {
    avisarFalha();
    return;
  }
  started.value = 'queued';
  focusHeading();
};

const pause = async () => {
  started.value = null;
  if (!(await pausar())) avisarFalha();
};
const resume = async () => {
  if (!(await voltar())) avisarFalha();
};

// Um item de "Esperando você" abre a conversa dele (conversation_path do servidor); "Ver na caixa", a caixa da rede.
const inboxDoPainel = computed(() =>
  props.inboxPathOf && painel.value?.inbox_id
    ? props.inboxPathOf(painel.value.inbox_id)
    : ''
);
const openInbox = path => {
  const destino = path || props.inboxPath || inboxDoPainel.value;
  if (destino) router.push(destino);
};
</script>

<template>
  <section
    data-ia-care-screen
    class="flex w-full max-w-3xl flex-col gap-5 pb-28 sm:pb-0"
  >
    <button
      type="button"
      data-ia-back
      class="inline-flex min-h-11 items-center gap-2 self-start rounded-xl border-0 bg-n-solid-1 px-4 text-sm font-medium text-n-slate-12 ring-1 ring-inset ring-n-weak transition hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
      @click="emit('back')"
    >
      <span class="i-lucide-arrow-left size-4" aria-hidden="true" />
      {{ $t(`${KEY}.SCREEN.${BACK_KEY[origin] || 'BACK_POSTS'}`) }}
    </button>

    <header class="flex items-center gap-4">
      <img
        v-if="post?.image_url"
        :src="post.image_url"
        alt=""
        class="size-16 shrink-0 rounded-xl object-cover"
      />
      <span
        v-else
        class="flex size-16 shrink-0 items-center justify-center rounded-xl bg-n-alpha-1"
        aria-hidden="true"
      >
        <span class="size-7" :class="NETWORK_ICON[network]" />
      </span>
      <div class="flex min-w-0 flex-col gap-1">
        <h2
          ref="heading"
          tabindex="-1"
          class="m-0 text-xl font-semibold text-n-slate-12 focus:outline-none"
        >
          {{ $t(`${KEY}.SCREEN.TITLE`) }}
        </h2>
        <p class="m-0 text-sm text-n-slate-11">
          {{ $t(`${KEY}.SCREEN.${fromKey}`) }}
        </p>
        <p v-if="post?.text" class="m-0 line-clamp-2 text-sm text-n-slate-12">
          {{ post.text }}
        </p>
      </div>
    </header>

    <div
      v-if="carregando && !painel"
      data-ia-reading
      role="status"
      aria-busy="true"
      class="flex flex-col gap-4 rounded-2xl bg-n-solid-1 p-6 ring-1 ring-inset ring-n-weak"
    >
      <p
        class="m-0 flex items-center gap-2 text-base font-medium text-n-slate-12"
      >
        <span
          class="i-lucide-sparkles size-5 animate-pulse text-n-violet-11"
          aria-hidden="true"
        />
        {{ $t(`${KEY}.SCREEN.READING`) }}
      </p>
      <div class="flex animate-pulse flex-col gap-3" aria-hidden="true">
        <div class="h-8 w-2/3 rounded-lg bg-n-alpha-2" />
        <div class="h-24 rounded-xl bg-n-alpha-2" />
        <div class="h-16 rounded-xl bg-n-alpha-2" />
      </div>
    </div>

    <div
      v-else-if="erro === 'acesso'"
      data-ia-no-access
      class="flex flex-col items-start gap-3 rounded-2xl bg-n-solid-1 p-6 ring-1 ring-inset ring-n-weak"
    >
      <p class="m-0 text-base font-semibold text-n-slate-12">
        {{ $t(`${KEY}.SCREEN.NO_ACCESS`) }}
      </p>
    </div>

    <div
      v-else-if="erro"
      role="alert"
      data-ia-error
      class="flex flex-col items-start gap-3 rounded-2xl bg-n-solid-1 p-6 ring-1 ring-inset ring-n-weak"
    >
      <p class="m-0 text-base font-semibold text-n-slate-12">
        {{ problemText(motivo) }}
      </p>
      <Button
        v-if="canRetry(motivo)"
        icon="i-lucide-refresh-cw"
        :label="$t(`${KEY}.SCREEN.RETRY`)"
        class="!min-h-11 !rounded-xl"
        @click="carregar"
      />
    </div>

    <template v-else-if="painel">
      <div
        v-if="painelStatus"
        role="status"
        data-ia-painel-problem
        :data-status="painelStatus"
        class="flex flex-col items-start gap-3 rounded-2xl bg-n-amber-2 p-5 ring-1 ring-inset ring-n-amber-6"
      >
        <p
          class="m-0 flex items-start gap-2 text-sm font-medium leading-6 text-n-amber-12"
        >
          <span
            class="i-lucide-triangle-alert mt-1 size-4 shrink-0"
            aria-hidden="true"
          />
          {{ problemText(painelStatus) }}
        </p>
        <Button
          v-if="canRetry(painelStatus)"
          icon="i-lucide-refresh-cw"
          :label="$t(`${KEY}.SCREEN.RETRY`)"
          :is-loading="carregando"
          class="!min-h-11 !rounded-xl"
          @click="carregar"
        />
      </div>
      <CuidarLigado
        v-if="on && !changing"
        :data="painel"
        :started="started"
        :can-manage="canManage"
        :busy="salvando"
        @pause="pause"
        @resume="resume"
        @reply="emit('back')"
        @read-old="oldDialog?.open()"
        @inbox="openInbox"
        @change="change"
      />

      <div
        v-else-if="!canManage"
        data-ia-off-readonly
        class="flex flex-col gap-2 rounded-2xl bg-n-solid-1 p-5 ring-1 ring-inset ring-n-weak sm:p-6"
      >
        <p class="m-0 text-base font-semibold leading-6 text-n-slate-12">
          {{ $t(`${KEY}.SCREEN.OFF_READONLY.TITLE`) }}
        </p>
        <p class="m-0 text-sm leading-6 text-n-slate-11">
          {{ $t(`${KEY}.SCREEN.OFF_READONLY.TEXT`) }}
        </p>
      </div>

      <CuidarDono
        v-else
        :key="`${target.id}-${changing}`"
        :data="painel"
        :preview="previa"
        :changing="changing"
        :can-send-old="canSendOld"
        :saving="salvando"
        @done="finishDono"
        @leave="leaveChanges"
      />
    </template>

    <Dialog
      v-if="painel && painel.unanswered > 0"
      ref="oldDialog"
      :title="
        $t(
          `${KEY}.DONO.OLD_DIALOG.TITLE`,
          { count: painel.unanswered },
          painel.unanswered
        )
      "
      :description="
        $t(
          `${KEY}.DONO.OLD_DIALOG.TEXT`,
          { count: painel.unanswered },
          painel.unanswered
        )
      "
    >
      <p
        v-if="painel.older"
        data-ia-old-older
        class="m-0 flex items-start gap-2 text-sm leading-6 text-n-slate-11"
      >
        <span class="i-lucide-clock mt-1 size-4 shrink-0" aria-hidden="true" />
        {{
          $t(
            porRede(`${KEY}.OLD_DIALOG.OLDER`, network),
            { count: painel.older },
            painel.older
          )
        }}
      </p>
      <!-- Rodapé próprio: no celular, "Ler e mandar" cabe inteiro em cima, e "Agora não" fica embaixo. -->
      <template #footer>
        <div class="flex w-full flex-col gap-3 sm:flex-row-reverse">
          <Button
            type="button"
            data-ia-old-confirm
            :label="
              $t(
                `${KEY}.DONO.OLD_DIALOG.CONFIRM`,
                { count: painel.unanswered },
                painel.unanswered
              )
            "
            :is-loading="salvando"
            class="!min-h-11 w-full !rounded-xl"
            @click="startOld"
          />
          <Button
            type="button"
            variant="faded"
            color="slate"
            :label="$t(`${KEY}.DONO.OLD_DIALOG.BACK`)"
            class="!min-h-11 w-full !rounded-xl"
            @click="oldDialog?.close()"
          />
        </div>
      </template>
    </Dialog>
  </section>
</template>
