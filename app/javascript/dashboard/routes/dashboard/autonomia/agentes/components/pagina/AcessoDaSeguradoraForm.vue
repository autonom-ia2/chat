<script setup>
import { computed, nextTick, onBeforeUnmount, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAdmin } from 'dashboard/composables/useAdmin';
import ContratadosAPI from 'dashboard/api/autonomia/contratados';
import AgenteGaveta from '../AgenteGaveta.vue';
import AgenteBotao from '../AgenteBotao.vue';
import AgenteErro from '../AgenteErro.vue';
import CampoErro from '../CampoErro.vue';
import { erroDoContratado } from '../../utils/contratado';
import { CLASSE_DO_CAMPO, anelDoCampo } from '../../utils/campo';

// #3211 (Tarefa 28) — o passo 2 do agente contratado: o login e a senha do portal da Universal (mockup aprovado,
// estados 05 a 11 e 16). Monta a própria gaveta, porque o botão do rodapé muda com o estado: "Conferir acesso" com
// os campos; "Escolher o canal" depois de conferido, enquanto o agente ainda está sendo montado (`emConfiguracao`).
// - Gravar o acesso é só do administrador (Tarefa 21: credencial não se delega por função). Quem gerencia sem ser
//   administrador lê o estado, sem os campos.
// - O servidor nunca devolve o login nem a senha, só `login_dica`, `estado`, `motivo` e `so_cotacao`. A Universal fora
//   do prazo volta 200 com `nao_conferido`/`indisponivel`, nunca erro.
// - A senha só existe no campo enquanto a pessoa digita: sai do estado logo depois do POST (deu certo ou não), não vai
//   para log nem para o aviso de erro.
const props = defineProps({
  agente: { type: Object, required: true },
  nome: { type: String, required: true },
  // O agente ainda em rascunho: "Passo 2 de 3", o aviso de criado e o caminho para o canal.
  emConfiguracao: { type: Boolean, default: false },
});

const emit = defineEmits(['fechar', 'escolherCanal', 'conferido']);

const { t } = useI18n();
const { isAdmin } = useAdmin();
const base = `acesso-${useId()}`;

const acesso = ref(props.agente.contratado?.acesso || null);
const editando = ref(false);
const login = ref('');
const senha = ref('');
const mostrarSenha = ref(false);
// A pessoa já começou a digitar a senha nova depois de uma recusa: o anel vermelho sai.
const senhaNova = ref(false);
const conferindo = ref(false);
// Os campos que estavam vazios no último envio; saem quando a pessoa escreve neles.
const faltando = ref([]);
// A recusa do próprio envio (422 ou sem resposta): { campo, texto }.
const erroDoEnvio = ref(null);
const campoLogin = ref(null);
const campoSenha = ref(null);

const conferido = computed(() => acesso.value?.estado === 'ok');
const soCota = computed(
  () => conferido.value && acesso.value?.so_cotacao === true
);
const mostraConferido = computed(() => conferido.value && !editando.value);
const recemCriado = computed(() => props.emConfiguracao && !acesso.value);

// O que a última conferência gravada diz quando não deu certo: o login recusado (a Universal julgou), a Universal
// fora do ar ou o pedido que ela não aceitou (não julgou o login).
const FALHA_DO_MOTIVO = {
  indisponivel: () => ({
    titulo: t('AGENTS.CONTRATADOS.ACESSO.INDISPONIVEL.TITULO'),
    garantia: t('AGENTS.CONTRATADOS.ACESSO.INDISPONIVEL.GARANTIA'),
  }),
  pedido_invalido: () => ({
    titulo: t('AGENTS.CONTRATADOS.ACESSO.PEDIDO_INVALIDO.TITULO'),
    garantia: t('AGENTS.CONTRATADOS.ACESSO.PEDIDO_INVALIDO.GARANTIA'),
  }),
};
const recusado = computed(() => acesso.value?.estado === 'recusado');
const falha = computed(() => {
  if (erroDoEnvio.value && !erroDoEnvio.value.campo) {
    return { titulo: erroDoEnvio.value.texto, garantia: '' };
  }
  if (!acesso.value || conferido.value) return null;
  if (recusado.value) {
    return {
      titulo: t('AGENTS.CONTRATADOS.ACESSO.RECUSADO.TITULO'),
      garantia: t('AGENTS.CONTRATADOS.ACESSO.RECUSADO.GARANTIA'),
    };
  }
  return FALHA_DO_MOTIVO[acesso.value.motivo]?.() || null;
});

const ERRO_LOCAL = {
  login: () => t('AGENTS.CONTRATADOS.ACESSO.LOGIN.ERRO'),
  senha: () => t('AGENTS.CONTRATADOS.ACESSO.SENHA.ERRO'),
};
const erroDe = campo => {
  if (faltando.value.includes(campo)) return ERRO_LOCAL[campo]();
  if (erroDoEnvio.value?.campo === campo) return erroDoEnvio.value.texto;
  return '';
};
const loginInvalido = computed(() => Boolean(erroDe('login')));
const senhaInvalida = computed(
  () =>
    Boolean(erroDe('senha')) ||
    (recusado.value && !erroDoEnvio.value && !senhaNova.value)
);

const descricao = (campo, ajuda) =>
  [erroDe(campo) ? `${base}-${campo}-erro` : '', ajuda]
    .filter(Boolean)
    .join(' ');

const mexeu = campo => {
  if (campo === 'senha') senhaNova.value = true;
  faltando.value = faltando.value.filter(item => item !== campo);
  if (erroDoEnvio.value?.campo === campo) erroDoEnvio.value = null;
};

const focar = campo =>
  (campo === 'login' ? campoLogin : campoSenha).value?.focus();

const alterar = async () => {
  editando.value = true;
  login.value = '';
  senha.value = '';
  mostrarSenha.value = false;
  senhaNova.value = false;
  faltando.value = [];
  erroDoEnvio.value = null;
  await nextTick();
  focar('login');
};

const depoisDoEnvio = async resposta => {
  acesso.value = resposta;
  editando.value = false;
  emit('conferido', resposta);
  if (resposta?.estado === 'ok') {
    login.value = '';
    return;
  }
  await nextTick();
  focar(resposta?.estado === 'recusado' ? 'senha' : 'login');
};

const conferir = async () => {
  if (conferindo.value) return;
  const pedido = { login: login.value.trim(), senha: senha.value };
  faltando.value = ['login', 'senha'].filter(campo => !pedido[campo].trim());
  if (faltando.value.length) {
    focar(faltando.value[0]);
    return;
  }
  erroDoEnvio.value = null;
  conferindo.value = true;
  try {
    const { data } = await ContratadosAPI.conferirAcesso(
      props.agente.id,
      pedido
    );
    await depoisDoEnvio(data);
  } catch (erro) {
    erroDoEnvio.value = erroDoContratado(t, erro);
  } finally {
    // Depois de qualquer resposta (ou da falta dela): a senha sai do estado e o campo volta a esconder o que se digita.
    senha.value = '';
    senhaNova.value = false;
    mostrarSenha.value = false;
    conferindo.value = false;
  }
};

onBeforeUnmount(() => {
  senha.value = '';
});

// Esc e o clique fora não fecham com o que a pessoa digitou, nem durante a conferência (o X continua fechando).
const podeFechar = () => !conferindo.value && !login.value && !senha.value;

const temRodape = computed(() =>
  mostraConferido.value ? props.emConfiguracao : isAdmin.value
);

const CAMPO = CLASSE_DO_CAMPO;
const anel = anelDoCampo;
</script>

<template>
  <AgenteGaveta
    :titulo="t('AGENTS.CONTRATADOS.ACESSO.TITULO')"
    :pode-fechar="podeFechar"
    @fechar="emit('fechar')"
  >
    <div
      class="flex flex-col gap-5"
      :aria-busy="conferindo ? 'true' : undefined"
    >
      <p
        v-if="recemCriado"
        data-acesso-criada
        role="status"
        class="flex items-start gap-3 p-4 m-0 text-sm rounded-2xl bg-n-teal-2 ring-1 ring-inset ring-n-teal-6 text-n-slate-12"
      >
        <span
          class="i-lucide-circle-check size-5 shrink-0 text-n-teal-11"
          aria-hidden="true"
        />
        {{ t('AGENTS.CONTRATADOS.ACESSO.CRIADA', { nome }) }}
      </p>
      <p
        v-if="emConfiguracao"
        data-passo
        class="m-0 text-base font-semibold text-n-blue-11"
      >
        {{ t('AGENTS.CONTRATADOS.ACESSO.PASSO') }}
      </p>

      <!-- Conferido: o resultado e a dica do login; a senha nunca volta para a tela. -->
      <template v-if="mostraConferido">
        <div
          v-if="soCota"
          data-acesso-so-cota
          role="status"
          class="flex items-start gap-3 p-4 rounded-2xl bg-n-amber-2 ring-1 ring-inset ring-n-amber-6"
        >
          <span
            class="i-lucide-triangle-alert size-6 shrink-0 text-n-amber-11"
            aria-hidden="true"
          />
          <div class="flex flex-col gap-1">
            <p class="m-0 text-base font-semibold text-n-slate-12">
              {{ t('AGENTS.CONTRATADOS.ACESSO.SO_COTA.TITULO') }}
            </p>
            <p class="m-0 text-sm text-n-slate-12">
              {{ t('AGENTS.CONTRATADOS.ACESSO.SO_COTA.TEXTO', { nome }) }}
            </p>
          </div>
        </div>
        <div
          v-else
          data-acesso-conferido
          role="status"
          class="flex items-start gap-3 p-4 rounded-2xl bg-n-teal-2 ring-1 ring-inset ring-n-teal-6"
        >
          <span
            class="i-lucide-circle-check size-6 shrink-0 text-n-teal-11"
            aria-hidden="true"
          />
          <div class="flex flex-col gap-1">
            <p class="m-0 text-base font-semibold text-n-slate-12">
              {{ t('AGENTS.CONTRATADOS.ACESSO.CONFERIDO.TITULO') }}
            </p>
            <p class="m-0 text-sm text-n-slate-12">
              {{ t('AGENTS.CONTRATADOS.ACESSO.CONFERIDO.TEXTO', { nome }) }}
            </p>
          </div>
        </div>
        <div
          class="flex items-center justify-between gap-3 p-4 rounded-2xl bg-n-solid-2 ring-1 ring-inset ring-n-weak"
        >
          <div class="flex flex-col min-w-0 gap-0.5">
            <span class="text-sm text-n-slate-11">
              {{ t('AGENTS.CONTRATADOS.ACESSO.LOGIN.ROTULO') }}
            </span>
            <span
              data-login-dica
              class="text-base font-medium truncate text-n-slate-12"
            >
              {{ acesso.login_dica }}
            </span>
            <span class="text-sm text-n-slate-11">
              {{ t('AGENTS.CONTRATADOS.ACESSO.SENHA.GUARDADA') }}
            </span>
          </div>
          <AgenteBotao
            v-if="isAdmin"
            data-alterar-acesso
            variante="contorno"
            :aria-label="t('AGENTS.CONTRATADOS.ACESSO.ALTERAR_ARIA')"
            @click="alterar"
          >
            {{ t('AGENTS.CONTRATADOS.ACESSO.ALTERAR') }}
          </AgenteBotao>
        </div>
      </template>

      <template v-else>
        <AgenteErro
          v-if="falha"
          data-acesso-erro
          :titulo="falha.titulo"
          :garantia="falha.garantia"
        />
        <p v-else class="m-0 text-base text-n-slate-12">
          {{ t('AGENTS.CONTRATADOS.ACESSO.EXPLICA', { nome }) }}
        </p>

        <template v-if="isAdmin">
          <div class="flex flex-col gap-1">
            <label
              :for="`${base}-login`"
              class="text-sm font-medium text-n-slate-12"
            >
              {{ t('AGENTS.CONTRATADOS.ACESSO.LOGIN.ROTULO') }}
            </label>
            <input
              :id="`${base}-login`"
              ref="campoLogin"
              v-model="login"
              data-acesso-login
              autocomplete="off"
              autocapitalize="none"
              autocorrect="off"
              spellcheck="false"
              :disabled="conferindo"
              :aria-invalid="loginInvalido ? 'true' : 'false'"
              :aria-describedby="descricao('login', `${base}-login-ajuda`)"
              :class="[CAMPO, anel(loginInvalido)]"
              @input="mexeu('login')"
            />
            <CampoErro
              v-if="erroDe('login')"
              :id="`${base}-login-erro`"
              :texto="erroDe('login')"
            />
            <p :id="`${base}-login-ajuda`" class="m-0 text-sm text-n-slate-11">
              {{ t('AGENTS.CONTRATADOS.ACESSO.LOGIN.AJUDA') }}
            </p>
          </div>

          <div class="flex flex-col gap-1">
            <label
              :for="`${base}-senha`"
              class="text-sm font-medium text-n-slate-12"
            >
              {{ t('AGENTS.CONTRATADOS.ACESSO.SENHA.ROTULO') }}
            </label>
            <div class="relative">
              <input
                :id="`${base}-senha`"
                ref="campoSenha"
                v-model="senha"
                data-acesso-senha
                :type="mostrarSenha ? 'text' : 'password'"
                autocomplete="off"
                autocapitalize="none"
                autocorrect="off"
                spellcheck="false"
                class="pe-12"
                :disabled="conferindo"
                :aria-invalid="senhaInvalida ? 'true' : 'false'"
                :aria-describedby="descricao('senha', `${base}-senha-ajuda`)"
                :class="[CAMPO, anel(senhaInvalida)]"
                @input="mexeu('senha')"
              />
              <button
                type="button"
                data-mostrar-senha
                :aria-label="
                  mostrarSenha
                    ? t('AGENTS.CONTRATADOS.ACESSO.SENHA.ESCONDER')
                    : t('AGENTS.CONTRATADOS.ACESSO.SENHA.MOSTRAR')
                "
                :aria-pressed="mostrarSenha ? 'true' : 'false'"
                :aria-controls="`${base}-senha`"
                :disabled="conferindo"
                class="absolute inset-y-0 grid p-0 end-0 w-11 place-items-center rounded-e-xl text-n-slate-11 hover:text-n-slate-12 disabled:opacity-60 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
                @click="mostrarSenha = !mostrarSenha"
              >
                <span
                  class="size-5"
                  :class="mostrarSenha ? 'i-lucide-eye-off' : 'i-lucide-eye'"
                  aria-hidden="true"
                />
              </button>
            </div>
            <CampoErro
              v-if="erroDe('senha')"
              :id="`${base}-senha-erro`"
              :texto="erroDe('senha')"
            />
            <p :id="`${base}-senha-ajuda`" class="m-0 text-sm text-n-slate-11">
              {{
                recusado
                  ? t('AGENTS.CONTRATADOS.ACESSO.SENHA.ESQUECEU')
                  : t('AGENTS.CONTRATADOS.ACESSO.SENHA.AJUDA')
              }}
            </p>
          </div>
        </template>
        <p
          v-else
          data-so-admin
          class="flex items-start gap-3 p-4 m-0 text-sm rounded-2xl bg-n-blue-2 ring-1 ring-inset ring-n-blue-6 text-n-slate-12"
        >
          <span
            class="i-lucide-lock size-5 shrink-0 text-n-blue-11"
            aria-hidden="true"
          />
          {{ t('AGENTS.CONTRATADOS.ACESSO.SO_ADMIN') }}
        </p>
      </template>
    </div>

    <template v-if="temRodape" #rodape>
      <template v-if="mostraConferido">
        <AgenteBotao
          data-ir-para-o-canal
          tamanho="xl"
          bloco
          icone-direita="i-lucide-arrow-right"
          :aria-describedby="`${base}-ultimo-passo`"
          @click="emit('escolherCanal')"
        >
          {{ t('AGENTS.CONTRATADOS.ACESSO.ESCOLHER_CANAL') }}
        </AgenteBotao>
        <p
          :id="`${base}-ultimo-passo`"
          class="m-0 text-sm text-center text-n-slate-11"
        >
          {{ t('AGENTS.CONTRATADOS.ACESSO.ULTIMO_PASSO', { nome }) }}
        </p>
      </template>
      <AgenteBotao
        v-else
        data-conferir
        tamanho="xl"
        bloco
        :carregando="conferindo"
        :rotulo-carregando="t('AGENTS.CONTRATADOS.ACESSO.CONFERINDO')"
        @click="conferir"
      >
        {{ t('AGENTS.CONTRATADOS.ACESSO.CONFERIR') }}
      </AgenteBotao>
    </template>
  </AgenteGaveta>
</template>
