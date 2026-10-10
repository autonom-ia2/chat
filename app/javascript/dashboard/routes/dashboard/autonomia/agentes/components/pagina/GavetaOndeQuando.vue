<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import AutonomiaChannelsAPI from 'dashboard/api/autonomia/channels';
import AgenteGaveta from '../AgenteGaveta.vue';
import AgenteBotao from '../AgenteBotao.vue';
import AgenteErro from '../AgenteErro.vue';
import EscolhaRadio from '../EscolhaRadio.vue';
import OndeQuandoEscolha from '../OndeQuandoEscolha.vue';
import DialogoAcao from './DialogoAcao.vue';
import NotaQuemRecebe from './NotaQuemRecebe.vue';
import {
  MOTIVO,
  useComecarAAtender,
} from '../../composables/useComecarAAtender';
import { usePermissoesDaJornada } from '../../composables/usePermissoesDaJornada';
import { trocaNoCanal } from '../../utils/canais';
import { QUANDO, quandoDoAgente } from '../../utils/pagina';

// #1181 PR3 (protótipo T10 e "Voltar a atender") — onde e quando o agente responde.
// - modo 'alterar', atendendo: escolher a caixa (livre ou ocupada, com troca) e o "quando". Trocar de
//   caixa usa o useComecarAAtender (mesma sequência do Começar a atender) e depois tira o agente da
//   caixa antiga; só o "quando" mudou = PATCH {id, config:{response_window}}.
// - modo 'alterar', parado (t10-parado): a caixa fica só para ler, com "Voltar a atender"; o
//   "quando" continua editável.
// - modo 'voltar' (T15 voltar): a mesma confirmação de canal do Começar a atender, com a caixa atual
//   marcada. Se ela continua ligada ao agente, só o PATCH active; senão a sequência completa.
// Sem canal conectado na conta (t10-semcanal): o link para conectar, só para quem pode; o "quando"
// e a nota de Atribuição continuam (salvar grava só a janela). Enquanto as caixas chegam, um
// carregando; se a leitura falhou, o erro padrão com "Tentar de novo" (`reler`), nunca o "não
// conectou nenhum canal". A caixa atual entra marcada quando chega, se a pessoa ainda não escolheu.
const props = defineProps({
  agente: { type: Object, required: true },
  nome: { type: String, required: true },
  modo: {
    type: String,
    default: 'alterar',
    validator: v => ['alterar', 'voltar'].includes(v),
  },
  atendendo: { type: Boolean, default: false },
  canais: { type: Array, required: true },
  // Estado da leitura das caixas (useCanaisDoAgente): 'carregando' | 'pronto' | 'erro'.
  estadoCanais: { type: String, default: 'pronto' },
  atuais: { type: Array, default: () => [] },
  semLeitura: { type: Boolean, default: false },
  horarios: { type: Object, default: () => ({}) },
});

const emit = defineEmits(['fechar', 'pronto', 'voltarAAtender', 'reler']);

const { t } = useI18n();
const store = useStore();
const router = useRouter();
const { podeConectarCanal } = usePermissoesDaJornada();
const { comecar, comecando } = useComecarAAtender();
const NS = 'AGENTS.JORNADA.PAGINA.ONDE';

const inboxAtual = computed(() => props.atuais[0]?.inbox_id ?? null);
const onde = ref(inboxAtual.value);
const escolheu = ref(false);
watch(inboxAtual, atual => {
  if (!escolheu.value) onde.value = atual;
});
const escolherOnde = inboxId => {
  escolheu.value = true;
  onde.value = inboxId;
};
const quando = ref(quandoDoAgente(props.agente));
const salvando = ref(false);
const erro = ref(null);
const dialogoNaoAtender = ref(null);

const voltar = computed(() => props.modo === 'voltar');
const somenteLeitura = computed(() => !voltar.value && !props.atendendo);
const ocupado = computed(() => salvando.value || comecando.value);
const carregandoCanais = computed(
  () => props.estadoCanais === 'carregando' && !props.canais.length
);
const erroCanais = computed(() => props.estadoCanais === 'erro');
const semCanal = computed(
  () => props.estadoCanais === 'pronto' && !props.canais.length
);
const semLista = computed(() => carregandoCanais.value || erroCanais.value);
const troca = computed(() =>
  trocaNoCanal(props.canais, onde.value, props.agente.id)
);
const nomeDoCanal = inboxId =>
  props.canais.find(canal => canal.inbox_id === inboxId)?.name || '';

const linkConectar = computed(
  () => router.resolve({ name: 'settings_inbox_new' }).href
);

// Quando, para o agente parado (sem a escolha de caixa): mesmas opções do OndeQuandoEscolha.
const horarioAtual = computed(() =>
  inboxAtual.value in props.horarios
    ? props.horarios[inboxAtual.value]
    : undefined
);
const ROTULO_QUANDO = {
  always: 'SEMPRE',
  business_hours: 'DENTRO',
  outside_business_hours: 'FORA',
};
const opcoesQuando = computed(() =>
  QUANDO.map(valor => {
    const chave = ROTULO_QUANDO[valor];
    let texto = '';
    if (valor === 'always') {
      texto = t('AGENTS.JORNADA.ONDE_QUANDO.SEMPRE_TEXTO');
    } else if (horarioAtual.value) {
      texto = t(`AGENTS.JORNADA.ONDE_QUANDO.${chave}_TEXTO`, {
        horario: horarioAtual.value,
      });
    }
    return {
      valor,
      titulo: t(`AGENTS.JORNADA.ONDE_QUANDO.${chave}`),
      texto,
      desabilitada: valor !== 'always' && horarioAtual.value === null,
    };
  })
);

const ERRO_DO_MOTIVO = {
  [MOTIVO.CANAL]: () => ({
    titulo: t('AGENTS.JORNADA.ERRO.CANAL'),
    garantia: t('AGENTS.JORNADA.ERRO.CANAL_GARANTIA'),
    acao: t('AGENTS.JORNADA.ERRO.CANAL_ACAO'),
    escolherOutro: true,
  }),
  [MOTIVO.TROCA_SEM_AGENTE]: resultado => ({
    titulo: t('AGENTS.JORNADA.ERRO.TROCA_SEM_AGENTE', { nome: props.nome }),
    garantia: t('AGENTS.JORNADA.ERRO.TROCA_SEM_AGENTE_GARANTIA', {
      canal: resultado.troca?.canal,
    }),
  }),
  [MOTIVO.OFFLINE]: () => ({
    titulo: t('AGENTS.JORNADA.ERRO.OFFLINE'),
    garantia: t('AGENTS.JORNADA.ERRO.OFFLINE_GARANTIA'),
    ambar: true,
  }),
};

const erroDeComecar = resultado => {
  const doMotivo = ERRO_DO_MOTIVO[resultado.motivo];
  if (doMotivo) return doMotivo(resultado);
  if (!voltar.value) {
    return { titulo: t(`${NS}.ERRO`), garantia: t(`${NS}.ERRO_GARANTIA`) };
  }
  return {
    titulo: t('AGENTS.JORNADA.ERRO.COMECAR_ATENDER'),
    garantia: t('AGENTS.JORNADA.ERRO.COMECAR_ATENDER_GARANTIA', {
      nome: props.nome,
    }),
  };
};

const erroDeSalvar = () => ({
  titulo: t(`${NS}.ERRO`),
  garantia: t(`${NS}.ERRO_GARANTIA`),
});

const terminar = mensagem => {
  useAlert(mensagem);
  emit('pronto');
  emit('fechar');
};

const atualizar = dados =>
  store.dispatch('autonomiaAgents/update', { id: props.agente.id, ...dados });

const janelaMudou = () => quando.value !== quandoDoAgente(props.agente);

// Sai das caixas antigas depois de entrar na nova. Se não conseguir, avisa que ficou nas duas.
const sairDasAntigas = async () => {
  const antigas = props.atuais.filter(canal => canal.inbox_id !== onde.value);
  try {
    await Promise.all(
      antigas.map(canal =>
        AutonomiaChannelsAPI.disconnect(props.agente.id, canal.inbox_id)
      )
    );
    return true;
  } catch {
    useAlert(
      t(`${NS}.CONTINUA_NO_ANTIGO`, {
        nome: props.nome,
        novo: nomeDoCanal(onde.value),
        antigo: antigas.map(canal => canal.name).join(', '),
      })
    );
    return false;
  }
};

const entrarNaCaixa = async () => {
  const resultado = await comecar({
    agente: props.agente,
    inboxId: onde.value,
    troca: troca.value,
    janela: quando.value,
  });
  if (!resultado.ok) erro.value = erroDeComecar(resultado);
  return resultado.ok;
};

const salvarAlteracao = async () => {
  if (!somenteLeitura.value && onde.value && onde.value !== inboxAtual.value) {
    if (!(await entrarNaCaixa())) return;
    const saiu = await sairDasAntigas();
    if (!saiu) {
      emit('pronto');
      emit('fechar');
      return;
    }
    terminar(t(`${NS}.PRONTO`));
    return;
  }
  if (janelaMudou()) {
    await atualizar({ config: { response_window: quando.value } });
  }
  terminar(t(`${NS}.PRONTO`));
};

const voltarAAtender = async () => {
  const jaLigado = props.atuais.some(canal => canal.inbox_id === onde.value);
  if (!jaLigado) {
    if (!(await entrarNaCaixa())) return;
  } else {
    const dados = { enabled: true, status: 'active' };
    if (janelaMudou()) dados.config = { response_window: quando.value };
    try {
      await atualizar(dados);
    } catch {
      erro.value = erroDeComecar({ motivo: MOTIVO.COMECAR });
      return;
    }
  }
  terminar(
    t(`${NS}.VOLTOU`, { canal: nomeDoCanal(onde.value), nome: props.nome })
  );
};

const confirmar = async () => {
  if (ocupado.value) return;
  erro.value = null;
  salvando.value = true;
  try {
    if (voltar.value) await voltarAAtender();
    else await salvarAlteracao();
  } catch {
    erro.value = erroDeSalvar();
  } finally {
    salvando.value = false;
  }
};

const acaoDoErro = () => {
  if (erro.value?.escolherOutro) {
    erro.value = null;
    onde.value = inboxAtual.value;
    return;
  }
  confirmar();
};

const naoAtender = async () => {
  await AutonomiaChannelsAPI.disconnect(props.agente.id, inboxAtual.value);
  onde.value = null;
  emit('pronto');
  useAlert(t(`${NS}.PRONTO`));
};

const titulo = computed(() =>
  voltar.value
    ? t('AGENTS.JORNADA.ONDE_QUANDO.TITULO', { nome: props.nome })
    : t(`${NS}.TITULO`, { nome: props.nome })
);
const rotuloVoltar = computed(() =>
  troca.value ? t(`${NS}.TROCAR`) : t(`${NS}.VOLTAR`)
);
</script>

<template>
  <AgenteGaveta :titulo="titulo" @fechar="emit('fechar')">
    <div class="flex flex-col gap-5" :aria-busy="ocupado ? 'true' : undefined">
      <AgenteErro
        v-if="erro"
        data-erro
        :tom="erro.ambar ? 'ambar' : 'rubi'"
        :titulo="erro.titulo"
        :garantia="erro.garantia"
        :acao="erro.acao || t('AGENTS.JORNADA.COMUM.TENTAR_DE_NOVO')"
        :carregando="ocupado"
        @acao="acaoDoErro"
      />

      <p
        v-if="carregandoCanais"
        data-carregando-canais
        role="status"
        class="flex items-center gap-2 p-4 m-0 text-sm rounded-2xl bg-n-slate-2 text-n-slate-11"
      >
        <span
          class="i-lucide-loader-circle size-4 shrink-0 motion-safe:animate-spin"
          aria-hidden="true"
        />
        {{ t(`${NS}.CARREGANDO_CANAIS`) }}
      </p>

      <AgenteErro
        v-else-if="erroCanais"
        data-erro-canais
        :titulo="t(`${NS}.LER_ERRO`)"
        :garantia="t(`${NS}.LER_ERRO_GARANTIA`)"
        :acao="t('AGENTS.JORNADA.COMUM.TENTAR_DE_NOVO')"
        @acao="emit('reler')"
      />

      <template v-else-if="semCanal || somenteLeitura">
        <section class="flex flex-col gap-2">
          <h3 class="m-0 text-sm font-semibold text-n-slate-12">
            {{ t(`${NS}.ONDE`) }}
          </h3>
          <div
            v-if="semCanal"
            data-sem-canal
            class="flex flex-col gap-2 p-4 text-sm rounded-2xl bg-n-amber-2 ring-1 ring-inset ring-n-amber-6 text-n-slate-12"
          >
            <p class="m-0">{{ t(`${NS}.SEM_CANAL`) }}</p>
            <a
              v-if="podeConectarCanal"
              data-conectar
              :href="linkConectar"
              target="_blank"
              rel="noopener noreferrer"
              class="inline-flex items-center gap-1 font-semibold underline min-h-11 w-fit text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
            >
              {{ t('AGENTS.JORNADA.HEROI.CONECTAR_CANAL') }}
              <span class="i-lucide-external-link size-4" aria-hidden="true" />
              <span class="sr-only">{{
                t('AGENTS.JORNADA.COMUM.NOVA_ABA')
              }}</span>
            </a>
            <p v-else class="m-0 text-n-slate-11">
              {{ t('AGENTS.JORNADA.HEROI.SEM_CANAL_SEM_PERMISSAO') }}
            </p>
          </div>
          <div v-else data-parado class="flex flex-col gap-2">
            <p class="m-0 text-sm font-medium text-n-slate-12">
              {{
                nomeDoCanal(inboxAtual) ||
                t('AGENTS.JORNADA.PAGINA.NENHUM_CANAL')
              }}
            </p>
            <p class="m-0 text-sm text-n-slate-11">
              {{ t(`${NS}.PARADO`, { nome }) }}
            </p>
            <AgenteBotao
              data-voltar
              class="self-start"
              icone="i-lucide-power"
              @click="emit('voltarAAtender')"
            >
              {{ t(`${NS}.VOLTAR`) }}
            </AgenteBotao>
          </div>
        </section>
        <section class="flex flex-col gap-2">
          <h3 class="m-0 text-sm font-semibold text-n-slate-12">
            {{ t(`${NS}.QUANDO`) }}
          </h3>
          <EscolhaRadio
            v-model="quando"
            :rotulo="t(`${NS}.QUANDO_ROTULO`)"
            :opcoes="opcoesQuando"
          />
        </section>
        <NotaQuemRecebe :nome="nome" />
      </template>

      <template v-else>
        <div v-if="!voltar && inboxAtual" class="flex justify-end">
          <AgenteBotao
            data-nao-atender
            variante="fantasma"
            icone="i-lucide-x"
            @click="dialogoNaoAtender?.abrir()"
          >
            {{ t(`${NS}.NAO_ATENDER`) }}
          </AgenteBotao>
        </div>
        <OndeQuandoEscolha
          v-model:quando="quando"
          :onde="onde"
          :canais="canais"
          :agente-id="agente.id"
          :nome="nome"
          :horarios="horarios"
          :sem-leitura="semLeitura"
          @update:onde="escolherOnde"
        />
      </template>
    </div>

    <template #rodape>
      <template v-if="voltar">
        <AgenteBotao
          data-confirmar
          tamanho="xl"
          bloco
          :carregando="ocupado"
          :rotulo-carregando="t('AGENTS.JORNADA.COMUM.COMECANDO')"
          :desabilitado="!onde || semCanal || semLista"
          aria-describedby="onde-voltar-texto"
          @click="confirmar"
        >
          {{ rotuloVoltar }}
        </AgenteBotao>
        <p
          id="onde-voltar-texto"
          class="m-0 text-sm text-center text-n-slate-11"
        >
          {{ t(`${NS}.VOLTAR_TEXTO`, { nome }) }}
        </p>
      </template>
      <div v-else class="flex flex-wrap justify-end gap-2">
        <AgenteBotao
          variante="contorno"
          tamanho="lg"
          :desabilitado="ocupado"
          @click="emit('fechar')"
        >
          {{ t('AGENTS.JORNADA.COMUM.CANCELAR') }}
        </AgenteBotao>
        <AgenteBotao
          data-confirmar
          tamanho="lg"
          :carregando="ocupado"
          :rotulo-carregando="t(`${NS}.SALVANDO`)"
          :desabilitado="semLista"
          @click="confirmar"
        >
          {{ t(`${NS}.SALVAR`) }}
        </AgenteBotao>
      </div>
    </template>

    <DialogoAcao
      ref="dialogoNaoAtender"
      :titulo="t(`${NS}.NAO_ATENDER_TITULO`)"
      :texto="
        t(`${NS}.NAO_ATENDER_TEXTO`, { nome, canal: nomeDoCanal(inboxAtual) })
      "
      :confirmar="t(`${NS}.NAO_ATENDER_CONFIRMAR`)"
      variante="perigo"
      :erro-titulo="t(`${NS}.ERRO`)"
      :erro-garantia="t(`${NS}.ERRO_GARANTIA`)"
      :executar="naoAtender"
    />
  </AgenteGaveta>
</template>
