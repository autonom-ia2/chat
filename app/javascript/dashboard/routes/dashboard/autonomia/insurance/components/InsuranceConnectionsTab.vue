<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import AutonomiaInsuranceAPI from 'dashboard/api/autonomiaInsurance';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import InsuranceStatusBadge from './InsuranceStatusBadge.vue';
import {
  CONNECTION_STATES,
  asksBrokerAction,
  buildConnection,
  failureMessageKey,
  formatVerifiedAt,
  isConnectedState,
  isTransientState,
  layerRows,
} from '../insuranceContract';

// Aba Conexões (PRD §9) ligada à API real: GET/POST/DELETE /autonomia/insurance/connection.
// A senha sai deste componente uma única vez (no POST) e é zerada na sequência; o backend nunca a
// devolve — a tela só conhece `username_hint`.
// `te` = "translation exists". Necessário porque o segundo argumento de `t()` não funciona como
// valor padrão: com a chave ausente, o vue-i18n devolve a própria chave.
const { t, te } = useI18n();

const connection = ref(buildConnection());
const isLoading = ref(true);
const isBusy = ref(false);
const hasLoadError = ref(false);
const form = ref({ username: '', password: '' });
const formError = ref('');

const status = computed(() => connection.value.status);
const isConnected = computed(() => isConnectedState(status.value));
const showForm = computed(
  () => status.value === CONNECTION_STATES.NOT_CONFIGURED
);
const encryptionUnavailable = computed(
  () => connection.value.encryption_available !== true
);
// Só o que a corretora consegue cotar. O portal devolve ramos que ela não tem habilitados (e às
// vezes sem nome — até 06/09/2026 o ramo 100 chegava como `ramo_100`, e a descoberta leu no portal
// que é Celular), que não ajudam ninguém na tela. Ficam no `capabilities` gravado,
// para diagnóstico e para o dia em que forem habilitados.
// `capabilities` É O QUARTO CAMINHO CRU, e o menos protegido dos quatro: `connections/sync.rb`
// grava o mapa como veio, sem passar nem pelo `sanitize_deep` que trata `failure`, `evidence` e
// `layers`. Tudo o que a lista de produtos lê vem daí.
//
// Três coisas que o dado cru já causou ou causaria, e que esta normalização fecha de uma vez:
//   1. produto sem `insurers` derrubava a ABA INTEIRA (`insurers.some` em `undefined`) — uma chave
//      ausente no adapter apagava a tela do corretor;
//   2. `enabled` e `integrationStatus` podiam discordar, e o denominador contava por um enquanto o
//      aviso nomeava pelo outro: "2 seguradoras" acima de "uma seguradora a menos";
//   3. slug sem `label` escrevia `ramo_100` na tela — o caso real de 06/09.
//
// A regra é a mesma das outras três portas: normalizar na entrada, uma vez, e o resto do
// componente trabalhar com dado que já obedece ao contrato.
// O PAYLOAD ERA MISTO, e passou a ser snake_case inteiro. A tradução do adapter no Rails era uma
// tabela de 13 chaves: o que estava nela chegava em snake_case, o que faltava passava batido em
// camelCase — e este componente foi escrito contra a mistura, lendo `integrationStatus` aqui e
// `insurer_auth` mais abaixo.
//
// AS DUAS FORMAS SÃO ACEITAS PORQUE `capabilities` FICA GRAVADO em jsonb: conexão sincronizada
// antes desta mudança tem a forma antiga no banco até o próximo scan. Ler só a nova apagaria da
// tela o que já está guardado.
const normalizarSeguradora = seg => ({
  ...seg,
  // `enabled` manda. `integrationStatus` só qualifica POR QUE está fora, e não pode desmentir.
  enabled: seg?.enabled === true,
  integrationStatus:
    seg?.integration_status ?? seg?.integrationStatus ?? 'unknown',
  name: seg?.name || seg?.code || '—',
});

const normalizarProduto = item => ({
  ...item,
  // Estes dois vinham direto do payload no template — o asterisco de rótulo inferido e o código do
  // ramo que o corretor lê para o suporte. Passam pela mesma porta que o resto.
  labelConfidence: item?.label_confidence ?? item?.labelConfidence,
  platformRef: item?.platform_ref ?? item?.platformRef,
  insurers: (Array.isArray(item?.insurers) ? item.insurers : []).map(
    normalizarSeguradora
  ),
});

const products = computed(() =>
  (connection.value.capabilities?.products ?? [])
    .filter(item => item?.enabled)
    .map(normalizarProduto)
);
const hiddenProductCount = computed(
  () =>
    (connection.value.capabilities?.products ?? []).length -
    products.value.length
);

const apply = payload => {
  connection.value = { ...buildConnection(), ...payload };
};

// ACOMPANHA ATÉ ASSENTAR.
//
// A descoberta virou trabalho de fundo porque levava ~25 s e o proxy cortava a requisição. Só que
// sem acompanhar, a tela mostraria "Descobrindo produtos" e ficaria parada nisso até o corretor
// recarregar a página sozinho — trocaríamos um erro visível por um travamento silencioso, que é
// pior.
//
// Consulta de 3 em 3 segundos enquanto o estado for de passagem, com teto. O teto existe porque um
// laço sem fim numa aba esquecida bate no servidor a noite toda; passado ele, a rede de segurança
// do healthcheck é quem resolve.
const INTERVALO_MS = 3000;
const MAXIMO_DE_CONSULTAS = 20;
let acompanhamento = null;

const pararAcompanhamento = () => {
  if (acompanhamento) clearTimeout(acompanhamento);
  acompanhamento = null;
};

const acompanharAteAssentar = (restantes = MAXIMO_DE_CONSULTAS) => {
  pararAcompanhamento();
  if (restantes <= 0 || !isTransientState(connection.value.status)) return;
  acompanhamento = setTimeout(async () => {
    try {
      const { data } = await AutonomiaInsuranceAPI.getConnection();
      apply(data.payload);
    } catch (error) {
      return; // falha de rede não pode virar laço; a próxima ação do corretor reconsulta
    }
    acompanharAteAssentar(restantes - 1);
  }, INTERVALO_MS);
};

const load = async () => {
  isLoading.value = true;
  hasLoadError.value = false;
  try {
    const { data } = await AutonomiaInsuranceAPI.getConnection();
    apply(data.payload);
    // Uma conexão pode estar em estado de passagem quando a tela abre — descoberta disparada de
    // outra aba, ou por alguém do time.
    acompanharAteAssentar();
  } catch (error) {
    hasLoadError.value = true;
  } finally {
    isLoading.value = false;
  }
};

const run = async (request, successKey) => {
  isBusy.value = true;
  try {
    const { data } = await request();
    apply(data.payload);
    acompanharAteAssentar();
    if (successKey) useAlert(t(successKey));
  } catch (error) {
    const message =
      error?.response?.data?.error || t('INSURANCE.CONNECTION.ERRORS.GENERIC');
    useAlert(message);
  } finally {
    isBusy.value = false;
  }
};

const onConnect = async () => {
  formError.value = '';
  const username = form.value.username.trim();
  const password = form.value.password;
  if (!username || !password) {
    formError.value = t('INSURANCE.CONNECTION.FORM.REQUIRED');
    return;
  }
  form.value = { username: '', password: '' };
  await run(
    () => AutonomiaInsuranceAPI.connect({ username, password }),
    'INSURANCE.CONNECTION.ALERTS.CONNECTED'
  );
};

const onReconnect = () =>
  run(
    () => AutonomiaInsuranceAPI.reconnect(),
    'INSURANCE.CONNECTION.ALERTS.RECONNECTED'
  );
const onRescan = () =>
  run(
    () => AutonomiaInsuranceAPI.rescan(),
    'INSURANCE.CONNECTION.ALERTS.RESCANNED'
  );
const onDisconnect = () =>
  run(
    () => AutonomiaInsuranceAPI.removeConnection(),
    'INSURANCE.CONNECTION.ALERTS.DISCONNECTED'
  );

// CRITÉRIO 1.6 — a verificação diz QUANDO e COM QUE evidência.
//
// Isto era `formatRelative`, que mostrava "há 3 minutos". Dois defeitos: o corretor não consegue
// cruzar um tempo relativo com o que ele mesmo viu no portal, e o número cresce sozinho na tela sem
// que nada tenha sido reverificado — a tela envelhece a informação e continua afirmando.
const verifiedLabel = (iso, evidence) => {
  const at = formatVerifiedAt(iso);
  if (!at) return t('INSURANCE.CONNECTION.NOT_VERIFIED');
  // `check` vem do adapter e chega SEM normalização (`connections/sync.rb`). Um valor novo do lado
  // de lá não pode virar `INSURANCE.CONNECTION.EVIDENCE.ALGUMA_COISA` na cara do corretor — e o
  // segundo argumento de `t()` NÃO serve de default aqui: string vazia faz o vue-i18n devolver a
  // própria chave. Sem tradução conhecida, a tela diz só quando foi verificado.
  // SEM `evidence` NÃO SE AFIRMA NADA sobre o que foi consultado. O `?? 'none'` daqui virava
  // "sem consulta ao portal" — uma AFIRMAÇÃO — e `evidence` é nulo em toda conexão cujo adapter
  // não emite o campo (`connection.rb`, `metadata['last_evidence'].presence`). A tela dizia "em
  // 07/09 10:00, sem consulta ao portal" e, três linhas abaixo, "Login aceito pelo portal em 07/09
  // 10:00": o mesmo minuto, duas afirmações contrárias, e a segunda é a verdadeira.
  //
  // Campo ausente e campo com valor desconhecido caem no mesmo lugar: dizer só quando, sem inventar
  // o quê.
  if (!evidence?.check) {
    return t('INSURANCE.CONNECTION.VERIFIED_AT_PLAIN', { at });
  }
  const check = `INSURANCE.CONNECTION.EVIDENCE.${String(
    evidence.check
  ).toUpperCase()}`;
  return te(check)
    ? t('INSURANCE.CONNECTION.VERIFIED_AT', { at, check: t(check) })
    : t('INSURANCE.CONNECTION.VERIFIED_AT_PLAIN', { at });
};

const failure = computed(() => connection.value.failure ?? null);
// Só a causa `credential_rejected` chega aqui com `actor: 'broker'`. É a única que pode virar
// pedido de senha — ver o comentário em insuranceContract.js.
const needsBrokerAction = computed(() => asksBrokerAction(failure.value));
// Estados em que a tela DEVE explicar o que houve. `ready` sem falha não explica nada, e estado
// transitório também não — dizer "não identificado" enquanto ainda está autenticando seria alarme
// falso. Uma linha gravada por uma versão anterior chega sem `failure`, e cai no texto genérico:
// nunca no pedido de senha, porque naquela versão `auth_required` também significava sessão morta.
const UNHEALTHY_STATES = [
  CONNECTION_STATES.DEGRADED,
  CONNECTION_STATES.AUTH_REQUIRED,
  CONNECTION_STATES.HUMAN_REQUIRED,
  CONNECTION_STATES.OFFLINE,
];
const failureText = computed(() => {
  if (!failure.value && !UNHEALTHY_STATES.includes(status.value)) return '';
  return t(failureMessageKey(failure.value));
});
const pendingInsurers = computed(
  () => connection.value.insurers_pending_auth ?? null
);
// CRITÉRIO 1.5 — avisar, não bloquear. Quem sabe distinguir "sou eu de outra aba" de "tem cotação
// de teste rodando na minha conta" é o corretor, não nós.
const accountInUse = computed(
  () => connection.value.account_already_active ?? null
);

// O NOME QUE O PORTAL USA vence o nosso mapa. O ramo 46 provou por quê: o portal o chama de
// "Aluguel", o nosso slug diz `fianca_locaticia`, e fiança locatícia é OUTRO produto (id 23) — o
// corretor lia na tela um produto que não era o que ia cotar. O slug já viajou para o banco e não
// muda; o rótulo passa a vir do adapter, que lê o portal.
//
// O i18n continua como rede para conexão gravada por versão anterior do adapter, que não manda
// `label`. Sem ela, produto antigo apareceria como slug cru.
const productLabel = item => {
  if (item.label) return item.label;
  const chave = `INSURANCE.PRODUCTS.${String(item.product).toUpperCase()}`;
  if (te(chave)) return t(chave);
  // Último recurso: slug sem `label` e sem tradução. Escrever `ramo_100` na tela foi o defeito real
  // de 06/09 — o corretor lia um identificador nosso onde esperava o nome do produto. "Ramo 100"
  // ao menos se lê como o que é: um ramo que ainda não sabemos nomear. O código já aparece no chip
  // ao lado, então o número não é novidade para quem olha a linha.
  const ramo = String(item.product ?? '');
  return ramo.startsWith('ramo_')
    ? t('INSURANCE.CAPABILITIES.UNNAMED_BRANCH', { ramo: ramo.slice(5) })
    : ramo;
};
// QUEM COTA É QUEM ESTÁ `enabled`, E QUEM NÃO COTA É TODO O RESTO.
//
// `pending` era `integrationStatus === 'auth_required'` — o CASO, não a classe. Seguradora com
// qualquer outro motivo de estar fora (`enabled: false` com status novo do adapter) sumia do
// denominador: a linha dizia "2 seguradoras" em vez de "1 de 2", o ponto ficava verde e a camada
// escrevia "As 2 foram conferidas uma a uma no portal e passaram" sobre uma que o dado marca como
// fora. `enabled` é a classe, e é o único campo que decide se cota.
//
// `auth_required` continua importando, mas só para NOMEAR quem o corretor consegue destravar
// sozinho (`refusedInsurers`) — não para contar.
const insurerSummary = item => {
  const ready = item.insurers.filter(i => i.enabled).length;
  return {
    ready,
    pending: item.insurers.length - ready,
    total: item.insurers.length,
  };
};
// Quem recusou, pelo nome. O adapter sempre soube — `integrationStatus: 'auth_required'` vem por
// seguradora desde o primeiro scan — e a tela só dizia "1 aguardando credencial". Um número não
// diz ao corretor em qual portal ele precisa entrar.
const refusedInsurers = item =>
  item.insurers
    .filter(i => i.integrationStatus === 'auth_required')
    .map(i => i.name);

// O VEREDITO: a primeira coisa que a tela responde, antes de qualquer detalhe.
//
// Antes o topo dizia só "Conectado", e conectado não é a pergunta do corretor — ele quer saber se
// dá para cotar, e quanto. Estado de passagem não afirma nem nega: durante a descoberta a contagem
// é do scan anterior, e apresentá-la como atual seria a tela envelhecendo o dado sozinha.
// COTAR EXIGE SEGURADORA. Produto habilitado no AGGER com ZERO seguradoras respondendo não cota
// nada, e contá-lo no veredito fazia a tela dizer "Pronta para cotar 1 produto" logo acima de
// "0 de 1 seguradora". A lista continua mostrando o produto — ele existe e o corretor precisa ver
// que está parado — mas o veredito conta só o que produz preço.
const quotableProducts = computed(() =>
  products.value.filter(item => item.insurers.some(i => i.enabled))
);

const verdict = computed(() => {
  if (isTransientState(status.value)) {
    return { key: 'INSURANCE.CONNECTION.VERDICT.WORKING', tone: 'working' };
  }
  if (!isConnected.value || !quotableProducts.value.length) {
    return { key: 'INSURANCE.CONNECTION.VERDICT.NOT_READY', tone: 'stopped' };
  }
  return {
    key:
      quotableProducts.value.length === 1
        ? 'INSURANCE.CONNECTION.VERDICT.READY_ONE'
        : 'INSURANCE.CONNECTION.VERDICT.READY',
    count: quotableProducts.value.length,
    tone: 'ready',
  };
});

// A CAMADA DE CREDENCIAIS SABIA, E DIZIA "não verificado".
//
// `layers.insurer_auth` vem do HEALTHCHECK, que de fato não verifica credencial de seguradora —
// tecnicamente correto. Só que o SCAN verifica, uma seguradora por vez, e o resultado está em
// `capabilities`. A tela mostrava "não verificado" e, três linhas abaixo, "1 aguardando
// credencial": o dado existia e a camada o ignorava.
//
// Aqui a camada passa a responder pelo scan QUANDO há scan, e carimbada com a data DELE — nunca a
// do healthcheck. O critério 1.2 existe para não confundir "não sei" com "falhou", e usar a data
// errada faria a tela afirmar que verificou agora o que verificou ontem.
// O detalhe de cada camada: a frase que diz COMO aquela linha foi verificada. Só para camada que
// passou — dizer "login aceito às 13h" numa linha que falhou seria a tela se contradizendo.
const layerDetail = row => {
  if (row.state !== 'ok') return null;
  if (row.key === 'runtime') {
    return t('INSURANCE.CONNECTION.LAYERS.RUNTIME_DETAIL');
  }
  if (row.key === 'platform_auth' && connection.value.last_authenticated_at) {
    return t('INSURANCE.CONNECTION.LAYERS.PLATFORM_AUTH_DETAIL', {
      at: formatVerifiedAt(connection.value.last_authenticated_at),
    });
  }
  return null;
};

const layers = computed(() => {
  const rows = layerRows(connection.value.layers).map(row => {
    const detail = layerDetail(row);
    return detail ? { ...row, detail } : row;
  });
  const scanAt = formatVerifiedAt(connection.value.last_capability_scan_at);
  if (!products.value.length || !scanAt) return rows;
  // Quem recusou, e EM QUE PRODUTO. A credencial é da integração, não do ramo, mas o corretor
  // procura pelo produto que parou de cotar — é assim que ele percebe o problema.
  const refusedBy = new Map();
  products.value.forEach(item => {
    refusedInsurers(item).forEach(name => {
      refusedBy.set(name, [...(refusedBy.get(name) ?? []), productLabel(item)]);
    });
  });
  const refused = [...refusedBy.keys()];
  // O UNIVERSO DA CONTAGEM É A CONTA, e a frase precisa dizer isso.
  //
  // A credencial é da INTEGRAÇÃO com a seguradora, não do ramo: uma Azul recusada está recusada
  // para tudo que ela cota. Contar as seguradoras distintas da conta é o número certo — mas a
  // versão anterior o colava numa frase que nomeava um produto ("recusou em Automóvel. As outras
  // 22 passaram"), enquanto a linha do produto logo abaixo dizia "17 de 18". Dois números sobre o
  // mesmo evento, na mesma tela, e nenhum errado isoladamente.
  //
  // Agora a camada fala só da conta, e o produto afetado aparece onde ele importa: no aviso de
  // dinheiro parado, dentro da própria linha do produto.
  // ESTA CAMADA SÓ FALA DO QUE FOI CONFERIDO NO PORTAL, e conferir credencial é o que produz
  // `ready` ou `auth_required`. Seguradora fora por qualquer outro motivo não passou nem recusou:
  // ela não entra na conta, porque dizer "conferidas uma a uma e passaram" sobre ela seria
  // afirmar uma verificação que não houve.
  const conferidas = new Map();
  products.value.forEach(item =>
    item.insurers.forEach(i => {
      if (
        i.integrationStatus === 'ready' ||
        i.integrationStatus === 'auth_required'
      ) {
        conferidas.set(i.code, i.integrationStatus);
      }
    })
  );
  const total = conferidas.size;
  // SEM NADA CONFERIDO NÃO HÁ O QUE AFIRMAR, e a camada precisa dizer isso em vez de promover o
  // vazio a aprovação. Sem esta guarda a tela escrevia "As 0 foram conferidas uma a uma no portal e
  // passaram", em verde e rotulada "verificado", ao lado de "Não está cotando" — que é exatamente o
  // que o critério 1.2 proíbe: confundir "não havia o que olhar" com "olhei e passou".
  if (!total) return rows;
  const rest = total - refused.length;
  return rows.map(row =>
    row.key === 'insurer_auth' && row.state === 'unknown'
      ? {
          ...row,
          state: refused.length ? 'pending' : 'ok',
          label: refused.length
            ? t(
                'INSURANCE.CONNECTION.LAYERS.INSURER_AUTH_COUNT',
                { count: refused.length },
                refused.length
              )
            : null,
          detail: refused.length
            ? `${t(
                'INSURANCE.CONNECTION.LAYERS.INSURER_AUTH_FAILED',
                { names: refused.join(', ') },
                refused.length
              )} ${t(
                'INSURANCE.CONNECTION.LAYERS.INSURER_AUTH_REST',
                { count: rest },
                rest
              )}`
            : t(
                'INSURANCE.CONNECTION.LAYERS.INSURER_AUTH_OK',
                { total },
                total
              ),
          source: t('INSURANCE.CONNECTION.LAYERS.FROM_SCAN', { at: scanAt }),
        }
      : row
  );
});

// O PONTO DA LINHA DO PRODUTO — três causas, três cores, cada uma com entrada na legenda.
//
// A ordem das perguntas importa e já errou duas vezes:
//
// 1. Alguma seguradora recusou? Então ÂMBAR, mesmo que a recusa derrube o produto inteiro. A
//    versão anterior perguntava "cota?" primeiro e dava CINZA ao produto de seguradora única
//    recusada — com a caixa âmbar "Azul está fora por credencial recusada" logo abaixo, na mesma
//    linha. O ponto contradizia o aviso que ele deveria resumir.
// 2. Cota alguma coisa? Então VERDE.
// 3. Sobrou: habilitado no AGGER e sem nenhuma seguradora cadastrada. CINZA, e a linha explica em
//    palavras — antes isto era VERDE, que a legenda define como "cotando".
//
// Devolve a chave da legenda junto da cor: é o que impede as duas de divergirem de novo. Cor sem
// entrada de legenda é cor que o corretor não sabe ler.
const productDot = item => {
  if (refusedInsurers(item).length) {
    return { cor: 'bg-n-amber-9', legenda: 'LEGEND_PENDING' };
  }
  if (insurerSummary(item).ready) {
    return { cor: 'bg-n-teal-9', legenda: 'LEGEND_QUOTING' };
  }
  return { cor: 'bg-n-slate-7', legenda: 'LEGEND_NONE' };
};

// A legenda lista as cores que ESTÃO na tela, e não uma lista fixa. Assim ela não descreve cor
// ausente nem deixa cor órfã — o defeito era exatamente esse: três cores, duas entradas.
const LEGEND_ORDER = ['LEGEND_QUOTING', 'LEGEND_PENDING', 'LEGEND_NONE'];
const DOT_BY_LEGEND = {
  LEGEND_QUOTING: 'bg-n-teal-9',
  LEGEND_PENDING: 'bg-n-amber-9',
  LEGEND_NONE: 'bg-n-slate-7',
};
const legend = computed(() => {
  const usadas = new Set(products.value.map(item => productDot(item).legenda));
  return LEGEND_ORDER.filter(key => usadas.has(key)).map(key => ({
    key,
    cor: DOT_BY_LEGEND[key],
  }));
});

// Mais seguradoras primeiro: é o que o corretor cota mais, e o que ele confere primeiro. A ordem
// crua do adapter é por código de ramo, que não significa nada para quem lê.
const sortedProducts = computed(() =>
  [...products.value].sort((a, b) => b.insurers.length - a.insurers.length)
);

onMounted(load);
onUnmounted(pararAcompanhamento);
</script>

<template>
  <div class="flex flex-col gap-6 max-w-3xl">
    <div
      v-if="isLoading"
      class="flex items-center justify-center py-16 text-n-slate-11"
    >
      <Spinner :size="24" />
    </div>

    <template v-else>
      <div
        v-if="hasLoadError"
        class="flex items-start gap-3 px-4 py-3 rounded-lg bg-n-ruby-2 text-n-ruby-12 text-sm"
      >
        <span class="i-lucide-alert-triangle size-4 mt-0.5 shrink-0" />
        <p>{{ t('INSURANCE.CONNECTION.ERRORS.LOAD') }}</p>
        <NextButton
          ghost
          sm
          :label="t('INSURANCE.CONNECTION.ACTIONS.RETRY')"
          @click="load"
        />
      </div>

      <div
        v-if="encryptionUnavailable"
        class="flex items-start gap-3 px-4 py-3 rounded-lg bg-n-amber-2 text-n-amber-12 text-sm"
      >
        <span class="i-lucide-lock size-4 mt-0.5 shrink-0" />
        <p>{{ t('INSURANCE.CONNECTION.ENCRYPTION_UNAVAILABLE') }}</p>
      </div>

      <section
        class="rounded-xl border border-n-weak bg-n-solid-1 overflow-hidden"
      >
        <header
          class="flex items-center justify-between gap-4 px-5 py-4 border-b border-n-weak"
        >
          <div class="flex items-center gap-3 min-w-0">
            <span
              class="flex items-center justify-center rounded-lg shrink-0 size-9 bg-n-alpha-2 text-n-slate-12"
            >
              <span class="i-lucide-building-2 size-5" />
            </span>
            <div class="flex flex-col min-w-0">
              <!-- O VEREDITO PRIMEIRO. "Conectado" não é a pergunta do corretor: ele quer saber
                   se dá para cotar, e quanto. O nome do provedor vira a linha de apoio. -->
              <h2
                v-if="!showForm"
                class="text-base font-semibold truncate"
                :class="
                  verdict.tone === 'ready'
                    ? 'text-n-teal-11'
                    : verdict.tone === 'stopped'
                      ? 'text-n-amber-11'
                      : 'text-n-slate-12'
                "
              >
                {{ t(verdict.key, { count: verdict.count }) }}
              </h2>
              <h2 v-else class="text-sm font-medium text-n-slate-12">
                {{ t('INSURANCE.CONNECTION.PROVIDER_AGGER') }}
              </h2>
              <!-- QUEM é esta conta, junto do veredito. Corretora com mais de uma conta AGGER
                   precisa saber de qual a tela está falando antes de agir sobre ela.
                   Só aparece quando o veredito ocupa o `h2`: no formulário o próprio `h2` já é o
                   nome do provedor, e repeti-lo aqui rendia "AGGER · AggilizadorAGGER ·
                   Aggilizador" na primeira tela que o corretor vê. -->
              <p v-if="!showForm" class="text-xs truncate text-n-slate-11">
                {{ t('INSURANCE.CONNECTION.PROVIDER_AGGER') }}
                <template v-if="connection.external_account_label">
                  — {{ connection.external_account_label }}
                </template>
              </p>
            </div>
          </div>
          <!-- O badge existe para NOMEAR UM PROBLEMA que o veredito não nomeia: `auth_required`,
               `degraded`, `offline`, `not_configured`, e os de passagem.
               Com `status: ready` ele nunca aparece — nem quando a conta não está cotando. Ali o
               veredito já diz "Pronta para cotar 11 produtos" (e o badge repetiria), ou diz "Não
               está cotando", e um badge VERDE escrito "Conectado" ao lado disso lê como
               tranquilização: o corretor vê verde e para de procurar. A causa real aparece na
               linha de falha e na camada, que é onde ela cabe. -->
          <InsuranceStatusBadge
            v-if="status !== CONNECTION_STATES.READY"
            :state="status"
          />
        </header>

        <div v-if="showForm" class="flex flex-col gap-4 px-5 py-5">
          <p class="text-sm text-n-slate-11">
            {{ t('INSURANCE.CONNECTION.FORM.INTRO') }}
          </p>
          <div class="grid gap-4 sm:grid-cols-2">
            <Input
              id="insurance-agger-username"
              v-model="form.username"
              type="text"
              autocomplete="off"
              :label="t('INSURANCE.CONNECTION.FORM.USERNAME')"
              :placeholder="t('INSURANCE.CONNECTION.FORM.USERNAME_PLACEHOLDER')"
            />
            <Input
              id="insurance-agger-password"
              v-model="form.password"
              type="password"
              autocomplete="new-password"
              :label="t('INSURANCE.CONNECTION.FORM.PASSWORD')"
              :placeholder="t('INSURANCE.CONNECTION.FORM.PASSWORD_PLACEHOLDER')"
            />
          </div>
          <p v-if="formError" class="text-xs text-n-ruby-11">{{ formError }}</p>
          <p class="text-xs text-n-slate-11">
            {{ t('INSURANCE.CONNECTION.FORM.SECURITY_NOTE') }}
          </p>
          <div>
            <NextButton
              solid
              blue
              icon="i-lucide-plug-zap"
              :label="t('INSURANCE.CONNECTION.ACTIONS.CONNECT')"
              :disabled="isBusy || encryptionUnavailable"
              :is-loading="isBusy"
              @click="onConnect"
            />
          </div>
        </div>

        <div v-else class="flex flex-col gap-5 px-5 py-5">
          <!-- FRESCOR. O desenho aprovado trazia isto como uma linha só, com um ponto de saúde e
               duas datas. Ficou em grade porque são QUATRO informações e não duas — conta, sessão,
               última verificação e última descoberta — e espremer quatro numa linha obriga a
               abreviar justamente os rótulos que dizem o que cada data significa.
               O ponto de saúde do desenho está mantido no campo Sessão, que é o que ele resumia:
               responde "isto está de pé?" sem obrigar a ler data nenhuma. -->
          <dl class="grid gap-4 text-sm sm:grid-cols-2">
            <div class="flex flex-col gap-0.5">
              <dt class="text-xs text-n-slate-11">
                {{ t('INSURANCE.CONNECTION.FIELDS.ACCOUNT') }}
              </dt>
              <!-- Só o e-mail aqui. O nome da corretora já identifica a conta lá em cima, junto do
                   veredito; repetir os dois faz o leitor procurar a diferença entre eles. -->
              <dd class="text-xs text-n-slate-12">
                <span class="font-mono">{{
                  connection.username_hint || '—'
                }}</span>
              </dd>
            </div>
            <div class="flex flex-col gap-0.5">
              <dt class="text-xs text-n-slate-11">
                {{ t('INSURANCE.CONNECTION.FIELDS.SESSION') }}
              </dt>
              <dd class="flex items-center gap-2 text-n-slate-12">
                <span
                  class="rounded-full size-2 shrink-0"
                  :class="
                    connection.last_authenticated_at
                      ? 'bg-n-teal-9'
                      : 'bg-n-slate-7'
                  "
                />
                {{
                  connection.last_authenticated_at
                    ? t('INSURANCE.CONNECTION.SESSION_AUTHENTICATED')
                    : t('INSURANCE.CONNECTION.SESSION_PENDING')
                }}
              </dd>
            </div>
            <div class="flex flex-col gap-0.5">
              <dt class="text-xs text-n-slate-11">
                {{ t('INSURANCE.CONNECTION.FIELDS.LAST_HEALTHCHECK') }}
              </dt>
              <dd class="text-n-slate-12">
                {{
                  verifiedLabel(
                    connection.evidence?.at || connection.last_healthcheck_at,
                    connection.evidence
                  )
                }}
              </dd>
            </div>
            <div class="flex flex-col gap-0.5">
              <dt class="text-xs text-n-slate-11">
                {{ t('INSURANCE.CONNECTION.FIELDS.LAST_SCAN') }}
              </dt>
              <dd class="text-n-slate-12">
                {{
                  verifiedLabel(connection.last_capability_scan_at, {
                    check: 'capability_scan',
                  })
                }}
              </dd>
            </div>
          </dl>

          <div
            v-if="failureText"
            class="flex items-start gap-2 px-3 py-2 rounded-lg text-xs"
            :class="
              needsBrokerAction
                ? 'bg-n-amber-2 text-n-amber-12'
                : 'bg-n-alpha-2 text-n-slate-12'
            "
          >
            <span
              class="size-4 mt-0.5 shrink-0"
              :class="
                needsBrokerAction ? 'i-lucide-key-round' : 'i-lucide-info'
              "
            />
            <p>{{ failureText }}</p>
          </div>

          <!-- AQUI FICOU, POR ALGUMAS HORAS, O BOTÃO "Abrir o AGGER logado". Ele foi RETIRADO em
               08/09/2026, e o motivo é do portal — não do nosso código. Está escrito aqui para
               ninguém tentar de novo sem ler primeiro.

               O QUE FUNCIONA: o handoff (`/cotacao/:ramo/resultados/:id/:versao/:token`) abre uma
               cotação existente já autenticada, e não derruba a sessão do agente. Medido três
               vezes, inclusive com o botão real em produção.

               O QUE NÃO FUNCIONA, E ERA O OBJETIVO: cotar do zero. A autenticação do handoff vale
               SÓ para aquele componente. Medido em 08/09:
                 - recarregar a home                                  -> /login
                 - CLICAR em "Cotações" (navegação interna, sem reload) -> /login
               O segundo é o que fecha a questão: nem a memória da SPA sobrevive à troca de rota.

               POR QUÊ: o portal não persiste sessão em lugar nenhum. Varredura dos 4 MB de bundle
               achou SETE gravações em localStorage — `bannerDueDate`, `modalIntroTimestamp`,
               `notificacoesLidas`, `pathRefer`, `SIDEBAR_CLOSED_KEY` — e nenhuma de token, sessão
               ou credencial. Nem `sessionStorage`, nem cookie próprio (os que existem são de
               analytics). Vale também para o login normal pelo formulário.

               ISSO ELIMINA DUAS SAÍDAS: não há rota que persista a sessão a partir do token, e não
               há onde injetar sessão no navegador — não existe chave para escrever.

               O QUE DESTRAVA: SSO de verdade, pedido à AGGER. Eles já têm o link autenticado;
               falta ele deixar a sessão navegável em vez de válida para um componente só. Enquanto
               isso não existe, o botão prometeria o que a plataforma não entrega, e a decisão do
               Rodrigo foi não deixar meio-caminho na mão do corretor.

               O mecanismo continua vivo e utilizável pelo adapter:
               `agger portal link -q <cotacao> -o <arquivo>`. Ver autonom-ia2/chat#345 e
               autonom-ia2/autonomia-adapters#42. -->
          <div class="flex flex-wrap items-center gap-2">
            <NextButton
              faded
              slate
              sm
              icon="i-lucide-refresh-cw"
              :label="t('INSURANCE.CONNECTION.ACTIONS.RECONNECT')"
              :disabled="isBusy || isTransientState(status)"
              @click="onReconnect"
            />
            <NextButton
              faded
              slate
              sm
              icon="i-lucide-scan-search"
              :label="t('INSURANCE.CONNECTION.ACTIONS.RESCAN')"
              :disabled="isBusy || !isConnected"
              @click="onRescan"
            />
            <NextButton
              ghost
              ruby
              sm
              icon="i-lucide-unplug"
              :label="t('INSURANCE.CONNECTION.ACTIONS.DISCONNECT')"
              :disabled="isBusy"
              @click="onDisconnect"
            />
          </div>
        </div>
      </section>

      <!-- CRITÉRIO 1.5: a conta já estava em uso quando conectamos. Aviso, nunca bloqueio. -->
      <section
        v-if="accountInUse"
        class="flex items-start gap-3 px-4 py-3 rounded-lg bg-n-alpha-2 text-n-slate-12 text-sm"
      >
        <span class="i-lucide-users size-4 mt-0.5 shrink-0" />
        <p class="text-xs">
          {{
            t('INSURANCE.CONNECTION.ALREADY_ACTIVE', {
              at: formatVerifiedAt(accountInUse.session_started_at) || '—',
            })
          }}
        </p>
      </section>

      <!-- CRITÉRIO 4.5: o problema de credencial de seguradora aparece AQUI, e nunca na conversa
           com o cliente. -->
      <section
        v-if="pendingInsurers"
        class="flex items-start gap-3 px-4 py-3 rounded-lg bg-n-amber-2 text-n-amber-12 text-sm"
      >
        <span class="i-lucide-key-round size-4 mt-0.5 shrink-0" />
        <div class="flex flex-col gap-1">
          <p class="font-medium">
            {{ t('INSURANCE.CONNECTION.INSURERS_PENDING.TITLE') }}
          </p>
          <p class="text-xs">
            {{
              t(
                'INSURANCE.CONNECTION.INSURERS_PENDING.BODY',
                {
                  count: pendingInsurers.codes?.length ?? 0,
                  at: formatVerifiedAt(pendingInsurers.observed_at),
                },
                pendingInsurers.codes?.length ?? 0
              )
            }}
          </p>
          <p v-if="pendingInsurers.names?.length" class="text-xs font-mono">
            {{ pendingInsurers.names.join(', ') }}
          </p>
        </div>
      </section>

      <!-- CRITÉRIO 1.2: as cinco camadas separadas. `não verificado` é uma resposta, não um vazio.
           FECHADO por padrão: elas respondem "como você sabe disso?", que é pergunta de segunda
           ordem. Abertas, ocupavam um terço da tela antes de o corretor chegar nos produtos.

           SÃO CINCO, e o desenho aprovado mostrava três. As duas a mais — "ramo suportado pela
           integração" e "risco aceito pela seguradora" — existem porque o 1.2 as separa de
           propósito: cada uma pode reprovar uma cotação por motivo diferente, e juntá-las faria a
           tela dizer "falhou" sem dizer onde. O desenho mostrava três porque nesta conta só três
           tinham veredito; suprimir as outras faria "não verificado" virar invisível, que é
           exatamente o que o critério proíbe.

           Card PRÓPRIO, e não dentro do card do veredito: fechado, ele é uma linha só, e uma linha
           clicável dentro do bloco que carrega as ações principais compete com elas. -->
      <details
        v-if="connection.layers"
        class="rounded-xl border border-n-weak bg-n-solid-1 overflow-hidden group"
      >
        <summary
          class="flex items-center gap-2 px-5 py-3.5 cursor-pointer text-sm text-n-slate-11 hover:text-n-slate-12 list-none"
        >
          <span
            class="i-lucide-chevron-right size-4 shrink-0 transition-transform group-open:rotate-90"
          />
          {{ t('INSURANCE.CONNECTION.LAYERS.DISCLOSURE') }}
        </summary>
        <p class="px-5 pb-2 text-xs text-n-slate-11">
          {{ t('INSURANCE.CONNECTION.LAYERS.SUBTITLE') }}
        </p>
        <ul class="border-t divide-y divide-n-weak border-n-weak">
          <li
            v-for="row in layers"
            :key="row.key"
            class="flex items-start justify-between gap-4 px-5 py-2.5 text-sm"
          >
            <div class="flex items-start gap-2.5 min-w-0">
              <!-- O marcador de cor repete o veredito da linha em forma, e não só em palavra:
                   quem varre a lista de cima a baixo acha a camada travada sem ler. -->
              <span
                class="rounded-full size-2 mt-1.5 shrink-0"
                :class="{
                  'bg-n-teal-9': row.state === 'ok',
                  'bg-n-amber-9': row.state === 'pending',
                  'bg-n-ruby-9': row.state === 'failed',
                  'bg-n-slate-7': row.state === 'unknown',
                }"
              />
              <div class="flex flex-col gap-0.5 min-w-0">
                <span class="text-n-slate-12">
                  {{
                    row.label ||
                    t(`INSURANCE.CONNECTION.LAYERS.${row.key.toUpperCase()}`)
                  }}
                </span>
                <span v-if="row.detail" class="text-xs text-n-slate-11">
                  {{ row.detail }}
                  <span v-if="row.source"> · {{ row.source }}</span>
                </span>
              </div>
            </div>
            <!-- `pending` é âmbar, e não vermelho: credencial que a seguradora recusou é dinheiro
                 parado esperando ação do corretor, não uma falha da integração. A MESMA condição
                 já é âmbar na lista de produtos, e a tela precisa dizer a mesma coisa nos dois
                 lugares. -->
            <span
              class="text-xs shrink-0"
              :class="{
                'text-n-teal-11': row.state === 'ok',
                'text-n-amber-11': row.state === 'pending',
                'text-n-ruby-11': row.state === 'failed',
                'text-n-slate-11': row.state === 'unknown',
              }"
            >
              {{
                t(
                  `INSURANCE.CONNECTION.LAYERS.STATE.${row.state.toUpperCase()}`
                )
              }}
            </span>
          </li>
        </ul>
      </details>

      <section
        v-if="isConnected"
        class="overflow-hidden border rounded-xl border-n-weak bg-n-solid-1"
      >
        <header class="px-5 py-4 border-b border-n-weak">
          <h2 class="text-sm font-medium text-n-slate-12">
            {{ t('INSURANCE.CAPABILITIES.TITLE') }}
          </h2>
          <p class="text-xs text-n-slate-11">
            {{
              connection.last_capability_scan_at
                ? t('INSURANCE.CAPABILITIES.SUBTITLE', {
                    at: formatVerifiedAt(connection.last_capability_scan_at),
                  })
                : t('INSURANCE.CAPABILITIES.SUBTITLE_NO_SCAN')
            }}
          </p>
        </header>
        <!-- CONTA SEM PRODUTO NENHUM. O card inteiro sumia aqui, e com ele a linha dos ramos
             ocultos e o rodapé que responde "cadê meu produto" — que é a pergunta do corretor
             exatamente nesta tela. Some a lista, fica a explicação. -->
        <p v-if="!products.length" class="px-5 py-4 text-sm text-n-slate-11">
          {{ t('INSURANCE.CAPABILITIES.EMPTY') }}
        </p>
        <ul v-else class="divide-y divide-n-weak">
          <li
            v-for="item in sortedProducts"
            :key="item.product"
            class="flex flex-col gap-2 px-5 py-3 text-sm"
          >
            <div class="flex items-center justify-between gap-4">
              <div class="flex items-center gap-3 min-w-0">
                <span
                  class="rounded-full size-2 shrink-0"
                  :class="productDot(item).cor"
                />
                <span class="truncate text-n-slate-12">
                  {{ productLabel(item) }}
                  <span
                    v-if="item.labelConfidence === 'inferred'"
                    class="ml-1 text-xs text-n-slate-11"
                    :title="t('INSURANCE.CAPABILITIES.INFERRED_HINT')"
                  >
                    *
                  </span>
                </span>
                <!-- O código do ramo no portal. É por ele que o corretor acha o produto do outro
                     lado, e é o que ele lê ao telefone com o suporte da AGGER. -->
                <span
                  class="px-1.5 py-0.5 text-[11px] font-mono rounded shrink-0 bg-n-alpha-2 text-n-slate-11"
                >
                  {{ item.platformRef }}
                </span>
              </div>
              <!-- COM DENOMINADOR. "17 seguradoras disponíveis" esconde que são 18 no total; o
                   corretor precisa ver o que está faltando, não só o que tem. -->
              <!-- `font-medium` + tabular: os números ficam legíveis na varredura vertical e as
                   colunas de dígitos alinham entre as linhas, que é o que faz a lista ser
                   comparável de cima a baixo. -->
              <span
                class="text-xs shrink-0 text-n-slate-12 font-medium tabular-nums"
              >
                {{
                  insurerSummary(item).pending
                    ? t(
                        'INSURANCE.CAPABILITIES.INSURERS_OF_TOTAL',
                        {
                          ready: insurerSummary(item).ready,
                          total: insurerSummary(item).total,
                        },
                        insurerSummary(item).total
                      )
                    : t(
                        'INSURANCE.CAPABILITIES.INSURERS_ALL',
                        { total: insurerSummary(item).total },
                        insurerSummary(item).total
                      )
                }}
              </span>
            </div>
            <!-- DINHEIRO PARADO, com nome. O adapter sempre soube qual seguradora recusou; a tela
                 dizia "1 aguardando credencial" e o corretor não tinha como saber onde entrar.
                 O desenho aprovado tinha aqui um botão "Rever no AGGER". Ele depende do mesmo
                 handoff ausente do botão principal (ver comentário nas ações acima): mandar o
                 corretor para o portal sem sessão o faria digitar a senha de novo, que é
                 exatamente o atrito que o handoff existe para remover. -->
            <!-- Habilitado no AGGER e sem NENHUMA seguradora respondendo. A linha existe (o
                 corretor precisa ver que o produto está parado) mas não conta no veredito, e o
                 ponto fica cinza. Dizer isso em palavras evita que "0 de 1" pareça erro de tela. -->
            <!-- Só quando NÃO há recusa a explicar: com seguradora recusada, o aviso âmbar abaixo
                 já diz quem é e o que fazer, e empilhar as duas caixas na mesma linha faz o
                 corretor ler duas vezes a mesma parada. -->
            <div
              v-if="
                !insurerSummary(item).ready && !refusedInsurers(item).length
              "
              class="flex flex-wrap items-center gap-2 px-3 py-2 text-xs rounded-lg bg-n-alpha-2 text-n-slate-11"
            >
              <span class="i-lucide-info size-4 shrink-0" />
              <span class="min-w-0">
                {{ t('INSURANCE.CAPABILITIES.NO_INSURERS') }}
              </span>
            </div>
            <div
              v-if="refusedInsurers(item).length"
              class="flex flex-wrap items-center gap-2 px-3 py-2 text-xs rounded-lg bg-n-amber-2 text-n-amber-12"
            >
              <span class="i-lucide-key-round size-4 shrink-0" />
              <span class="min-w-0">
                {{
                  t(
                    'INSURANCE.CAPABILITIES.MONEY_LEFT',
                    {
                      names: refusedInsurers(item).join(', '),
                      product: productLabel(item),
                      count: refusedInsurers(item).length,
                    },
                    refusedInsurers(item).length
                  )
                }}
              </span>
            </div>
          </li>
        </ul>
        <!-- Sem produto não há ponto na tela, e legenda de cor que ninguém vê é ruído. -->
        <div
          v-if="legend.length"
          class="flex flex-wrap gap-4 px-5 py-2.5 text-xs border-t text-n-slate-11 border-n-weak"
        >
          <span
            v-for="entry in legend"
            :key="entry.key"
            class="flex items-center gap-1.5"
          >
            <span class="rounded-full size-2" :class="entry.cor" />
            {{ t(`INSURANCE.CAPABILITIES.${entry.key}`) }}
          </span>
        </div>
        <p
          v-if="hiddenProductCount"
          class="px-5 py-3 text-xs border-t text-n-slate-11 border-n-weak"
        >
          {{
            t(
              'INSURANCE.CAPABILITIES.HIDDEN_PRODUCTS',
              { count: hiddenProductCount },
              hiddenProductCount
            )
          }}
        </p>
        <p class="px-5 py-3 text-xs border-t text-n-slate-11 border-n-weak">
          {{ t('INSURANCE.CAPABILITIES.FOOTER') }}
        </p>
      </section>
    </template>
  </div>
</template>
