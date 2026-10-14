import { computed, ref } from 'vue';
import * as Sentry from '@sentry/vue';
import { useAlert } from 'dashboard/composables';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { FUNIL, MODELOS, corDaPosicao, modelosDoTipo } from './funil';
import { copiarEtapa } from './funilForm';

// #1384 — os modelos de "Começar pronto" do funil novo: as etapas do modelo,
// a frase padrão de cada uma (vinda do servidor) e a troca de modelo, que pede
// confirmação quando a pessoa já mudou alguma etapa.
// #1498 — antes do modelo vem o tipo (Vender ou Atender). Sem tipo escolhido,
// o funil novo ainda não tem etapas.
export const useFunilModelo = ({ t, ia, form, editorSession }) => {
  const tipo = ref('');
  const modelo = ref('');
  const modeloPendente = ref('');
  // Frase padrão que o servidor deu para cada etapa, para saber se a pessoa
  // mudou a frase depois.
  const padroes = new WeakMap();

  const modeloAtual = computed(
    () => MODELOS.find(item => item.chave === modelo.value) || null
  );
  const modelosDisponiveis = computed(() => modelosDoTipo(tipo.value));
  const nomesDeModelo = computed(() =>
    MODELOS.map(item => t(`${FUNIL}.MODELOS.${item.chave}.NOME`))
  );

  // #1548 — `modeloPosicao`: a etapa E<n> do modelo. Acompanha a etapa mesmo
  // se ela mudar de lugar ou de nome; etapa criada pela pessoa não tem.
  const stagesDoModelo = item =>
    item.etapas.map((chave, index) => ({
      name: t(chave),
      color: corDaPosicao(index),
      categoria: item.categorias?.[index] || '',
      modeloPosicao: index + 1,
    }));
  const copiarEtapas = etapas =>
    etapas.map((etapa, index) => ({
      ...copiarEtapa(etapa, corDaPosicao(index)),
      categoria: etapa.categoria || '',
      ...(etapa.modeloPosicao ? { modeloPosicao: etapa.modeloPosicao } : {}),
    }));

  const guardarPadrao = (stage, frase) => {
    stage.aiCriteria = frase;
    padroes.set(stage, frase);
  };

  // O funil novo mostra a frase padrão de cada etapa, a mesma que o servidor
  // grava quando ela fica em branco (Crm::Ai::DefaultStageCriteria). Só
  // preenche etapa que a pessoa ainda não tocou e cujo nome não mudou.
  const loadDefaultCriteria = async () => {
    if (!ia.value) return;
    const session = editorSession.value;
    const requested = form.stages.map(stage => ({ stage, name: stage.name }));
    try {
      // #1548: com o modelo e a posição, o servidor acha a frase mesmo com o
      // nome da etapa trocado; sem eles, acha pelo nome.
      const { data } = await CrmKanbanAPI.getStageCriteriaDefaults(
        requested.map(item => item.name),
        {
          atender: !form.countsAsSale,
          template: modelo.value,
          positions: requested.map(item => item.stage.modeloPosicao || 0),
        }
      );
      if (session !== editorSession.value) return;
      (data.payload || []).forEach((item, index) => {
        const { stage, name } = requested[index] || {};
        if (!stage || stage.name !== name || stage.aiCriteria !== undefined)
          return;
        if (item.criteria) guardarPadrao(stage, item.criteria);
      });
    } catch (error) {
      // A tela segue sem as frases prontas e o servidor ainda grava o padrão
      // ao salvar; a pessoa fica sabendo e o erro vai para o Sentry.
      Sentry.captureException(error);
      useAlert(t(`${FUNIL}.ETAPAS.PADRAO_ERRO`));
    }
  };

  // Nome do desfecho de sucesso que o modelo traz (Cobrança: "Pago"). Só
  // troca o que a pessoa não escreveu.
  const sucessoDo = item =>
    item?.sucesso ? t(`${FUNIL}.MODELOS.${item.chave}.SUCESSO`) : '';

  // O modelo também traz pronto o "Quando usar este funil" (a primeira ideia).
  const quandoUsarDo = item =>
    item ? t(`${FUNIL}.SOBRE.IDEIAS.${item.ideias[0]}`) : '';

  // A pessoa mudou alguma etapa do modelo: quantidade, nome, cor ou frase.
  const etapasMudaram = () => {
    if (!modeloAtual.value) return false;
    const doModelo = stagesDoModelo(modeloAtual.value);
    if (form.stages.length !== doModelo.length) return true;
    return form.stages.some((stage, index) => {
      const original = doModelo[index];
      const frase = stage.aiCriteria;
      return (
        stage.name !== original.name ||
        stage.color !== original.color ||
        (frase !== undefined && frase !== padroes.get(stage))
      );
    });
  };

  const trocarModelo = item => {
    const quandoUsarAntigo = quandoUsarDo(modeloAtual.value);
    const sucessoAntigo = sucessoDo(modeloAtual.value);
    tipo.value = item.tipo;
    modelo.value = item.chave;
    modeloPendente.value = '';
    editorSession.value += 1;
    if (!form.name.trim() || nomesDeModelo.value.includes(form.name.trim()))
      form.name = t(`${FUNIL}.MODELOS.${item.chave}.NOME`);
    if (!form.whenToUse.trim() || form.whenToUse === quandoUsarAntigo)
      form.whenToUse = quandoUsarDo(item);
    form.countsAsSale = item.venda;
    if (form.outcomeLabels.success.trim() === sucessoAntigo)
      form.outcomeLabels = { ...form.outcomeLabels, success: sucessoDo(item) };
    form.stages = copiarEtapas(stagesDoModelo(item));
    loadDefaultCriteria();
  };

  const escolherModelo = chave => {
    const item = MODELOS.find(opcao => opcao.chave === chave);
    if (!item || chave === modelo.value) {
      modeloPendente.value = '';
      return;
    }
    if (etapasMudaram()) {
      modeloPendente.value = chave;
      return;
    }
    trocarModelo(item);
  };
  // Escolher o tipo já começa pelo primeiro modelo dele.
  const escolherTipo = chave => {
    if (chave === tipo.value) return;
    const [primeiro] = modelosDoTipo(chave);
    if (primeiro) escolherModelo(primeiro.chave);
  };
  const confirmarModelo = () => {
    const item = MODELOS.find(opcao => opcao.chave === modeloPendente.value);
    if (item) trocarModelo(item);
  };
  const manterModelo = () => {
    modeloPendente.value = '';
  };

  const reiniciarModelo = () => {
    tipo.value = '';
    modelo.value = '';
    modeloPendente.value = '';
  };

  return {
    tipo,
    modelo,
    modeloAtual,
    modelosDisponiveis,
    modeloPendente,
    stagesDoModelo,
    copiarEtapas,
    loadDefaultCriteria,
    quandoUsarDo,
    escolherTipo,
    escolherModelo,
    confirmarModelo,
    manterModelo,
    reiniciarModelo,
  };
};
