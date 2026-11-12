import { computed, ref } from 'vue';
import FerramentasProntasAPI from 'dashboard/api/autonomia/ferramentasProntas';

// #2858 F2 — o estado da vitrine de ferramentas prontas, compartilhado entre a vitrine e a gaveta de ferramentas do
// agente (um só estado por página: incluir na vitrine já aparece na gaveta). Tudo vem do servidor
// (FerramentasProntasController): o catálogo liberado para a conta (`fontes`) e as prontas de cada agente
// (`incluidas`). A lista é trocada inteira a cada mudança (nada de mutar o item). A chave interna da conta na fonte é
// da plataforma e nunca chega aqui.
//
// Erros em categorias que a tela sabe dizer (AGENTS.VITRINE.MOTIVOS.<MOTIVO>):
//   SEM_PERMISSAO (401/403), DESLIGADA (404 com o motivo "desligada": a vitrine saiu da conta; ou 422 "desligada"),
//   NAO_ENCONTRADO (outro 404: o agente ou a ferramenta não existe mais), COTACAO (a Lia),
//   NOME_EM_USO (o agente já tem uma ferramenta feita à mão com o mesmo nome), REDE (sem resposta) e GERAL.

const STATUS_SEM_PERMISSAO = [401, 403];
const STATUS_DESLIGADA = 404;
const MOTIVOS_DO_INCLUIR = {
  desligada: 'DESLIGADA',
  // A fonte que saiu da vitrine (Produtos das seguradoras): para quem está na tela, é o mesmo que desligada.
  fora_da_vitrine: 'DESLIGADA',
  agente_de_cotacao: 'COTACAO',
  nome_em_uso: 'NOME_EM_USO',
};

export const motivoDoErro = erro => {
  const resposta = erro?.response;
  if (!resposta) return 'REDE';
  if (STATUS_SEM_PERMISSAO.includes(resposta.status)) return 'SEM_PERMISSAO';
  if (resposta.status === STATUS_DESLIGADA) {
    return resposta.data?.motivo === 'desligada'
      ? 'DESLIGADA'
      : 'NAO_ENCONTRADO';
  }
  return MOTIVOS_DO_INCLUIR[resposta.data?.motivo] || 'GERAL';
};

const comMotivo = erro =>
  Object.assign(new Error(motivoDoErro(erro)), {
    motivo: motivoDoErro(erro),
  });

const fontes = ref([]);
// #2858 F5: chave da base baixada -> o dia em que a cópia que vale entrou ("2026-11-11"), ou null antes de baixar.
const atualizacoes = ref({});
const emPreparacao = ref([]);
// F7: { chave: { gratis, restantes, precos } } dos cards Premium liberados para a conta.
const premium = ref({});
const incluidas = ref([]);
const carregando = ref(false);
const carregada = ref(false);
const erro = ref('');
let pedido = null;
// Cada mudança (incluir, ligar, tirar) avança a versão: a lista que chega de um `carregar` pedido antes dela é velha.
// Ela não é usada (apagaria a mudança) e a lista é pedida de novo, já com a mudança.
let versao = 0;

// Lê de novo a cada abertura de tela (a conta pode ter mudado entre uma e outra); duas telas ao mesmo tempo dividem
// o mesmo pedido.
const carregar = () => {
  if (pedido) return pedido;
  carregando.value = true;
  erro.value = '';
  const versaoDoPedido = versao;
  let velha = false;
  pedido = FerramentasProntasAPI.listar()
    .then(({ data }) => {
      velha = versaoDoPedido !== versao;
      if (velha) return;
      fontes.value = (data?.fontes || []).map(item => item.chave);
      atualizacoes.value = Object.fromEntries(
        (data?.fontes || [])
          .filter(item => 'atualizado_em' in item)
          .map(item => [item.chave, item.atualizado_em || null])
      );
      emPreparacao.value = (data?.fontes || [])
        .filter(item => item.em_preparacao)
        .map(item => item.chave);
      premium.value = Object.fromEntries(
        (data?.fontes || [])
          .filter(item => item.premium)
          .map(item => [item.chave, item.premium])
      );
      incluidas.value = data?.incluidas || [];
      carregada.value = true;
    })
    .catch(falha => {
      erro.value = motivoDoErro(falha);
    })
    .finally(() => {
      carregando.value = false;
      pedido = null;
    })
    .then(() => (velha ? carregar() : undefined));
  return pedido;
};

// O preço e as grátis que restam de um card Premium; null nos grátis.
const premiumDe = fonte => premium.value[fonte] || null;

const doAgente = agenteId =>
  incluidas.value.filter(item => item.agente_id === Number(agenteId));

const tem = (agenteId, fonte) =>
  doAgente(agenteId).some(item => item.fonte === fonte);

const trocar = pronta => {
  versao += 1;
  const existe = incluidas.value.some(item => item.id === pronta.id);
  incluidas.value = existe
    ? incluidas.value.map(item => (item.id === pronta.id ? pronta : item))
    : [...incluidas.value, pronta];
  return pronta;
};

const chamar = async chamada => {
  try {
    return await chamada();
  } catch (falha) {
    throw comMotivo(falha);
  }
};

// Incluir de novo a mesma fonte no mesmo agente não duplica: o servidor atualiza a frase e religa.
const incluir = async ({ fonte, agenteId, usarQuando }) => {
  const { data } = await chamar(() =>
    FerramentasProntasAPI.incluir({
      fonte,
      agenteId: Number(agenteId),
      usarQuando,
    })
  );
  return trocar(data);
};

const mudarLigada = async (id, ligada) => {
  const { data } = await chamar(() =>
    FerramentasProntasAPI.mudarLigada(id, ligada)
  );
  return trocar(data);
};

const tirar = async id => {
  await chamar(() => FerramentasProntasAPI.tirar(id));
  versao += 1;
  incluidas.value = incluidas.value.filter(item => item.id !== id);
};

// F7 (revisor, 12/11): a consulta do card Premium roda em segundo plano. O servidor responde "consultando" com o id do
// pedido, e aqui se pergunta pelo id, com intervalo crescente, até o resultado ou até o prazo (~80 s, mais que a
// consulta mais lenta da BigDataCorp). No prazo, ou com o pedido sumido (404), a situação é "sem_confirmacao". A falha
// de rede numa pergunta não para: a próxima tenta de novo.
const ESPERAS_DO_PEDIDO_MS = [1000, 2000, 3000, 5000, 8000, 10000];
const PRAZO_DO_PEDIDO_MS = 80000;
const CONSULTANDO = 'consultando';
const SEM_CONFIRMACAO = 'sem_confirmacao';

const esperar = ms =>
  new Promise(resolve => {
    setTimeout(resolve, ms);
  });

const perguntar = async idDoPedido => {
  try {
    const { data } = await FerramentasProntasAPI.acompanhar(idDoPedido);
    return data?.situacao && data.situacao !== CONSULTANDO ? data : null;
  } catch (falha) {
    return falha?.response?.status === STATUS_DESLIGADA
      ? { situacao: SEM_CONFIRMACAO }
      : null;
  }
};

const acompanhar = async (idDoPedido, vez = 0, passado = 0) => {
  if (passado >= PRAZO_DO_PEDIDO_MS) return { situacao: SEM_CONFIRMACAO };
  const espera = Math.min(
    ESPERAS_DO_PEDIDO_MS[Math.min(vez, ESPERAS_DO_PEDIDO_MS.length - 1)],
    PRAZO_DO_PEDIDO_MS - passado
  );
  await esperar(espera);
  const resposta = await perguntar(idDoPedido);
  return resposta || acompanhar(idDoPedido, vez + 1, passado + espera);
};

// O "Experimente" responde sempre uma situação: a falha da chamada vira "sem_permissao" ou "nao_consegui_consultar",
// para a tela dizer uma frase só.
// `confirmouPreco` (F7): o clique no botão com o preço, quando as grátis do card Premium acabaram. A resposta do
// Premium traz o contador novo do card, que a tela mostra sem recarregar a lista. Sem resposta, o card Premium lê a
// lista de novo: a consulta pode ter saído e contado antes de a chamada falhar.
const experimentar = async (fonte, valor, confirmouPreco = false) => {
  try {
    const { data: inicio } = await FerramentasProntasAPI.experimentar(
      fonte,
      valor,
      confirmouPreco
    );
    const data =
      inicio?.situacao === CONSULTANDO && inicio.pedido
        ? await acompanhar(inicio.pedido)
        : inicio;
    if (data?.premium) {
      premium.value = { ...premium.value, [fonte]: data.premium };
    }
    if (data?.situacao === SEM_CONFIRMACAO) await carregar();
    return data?.situacao ? data : { situacao: 'nao_consegui_consultar' };
  } catch (falha) {
    if (premium.value[fonte]) await carregar();
    const motivo = motivoDoErro(falha);
    if (motivo === 'SEM_PERMISSAO') return { situacao: 'sem_permissao' };
    if (motivo === 'DESLIGADA') return { situacao: 'desligada' };
    return { situacao: 'nao_consegui_consultar' };
  }
};

// Medida da busca (não é ação da pessoa): falhar aqui não muda nada na tela, e a próxima busca tenta de novo.
const registrarBuscaSemResultado = async termo => {
  try {
    await FerramentasProntasAPI.buscaSemResultado(termo);
    return true;
  } catch {
    return false;
  }
};

// O dia da cópia de uma base baixada; null antes de baixar; undefined para quem não é base.
const atualizadoEm = fonte => atualizacoes.value[fonte];
const estaEmPreparacao = fonte => emPreparacao.value.includes(fonte);

export const useVitrine = () => ({
  carregar,
  fontes: computed(() => fontes.value),
  atualizadoEm,
  estaEmPreparacao,
  incluidas: computed(() => incluidas.value),
  carregando: computed(() => carregando.value),
  carregada: computed(() => carregada.value),
  erro: computed(() => erro.value),
  premiumDe,
  doAgente,
  tem,
  incluir,
  mudarLigada,
  tirar,
  experimentar,
  registrarBuscaSemResultado,
});
