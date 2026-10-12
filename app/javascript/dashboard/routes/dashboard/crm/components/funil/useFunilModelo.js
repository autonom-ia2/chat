import { computed, ref } from 'vue';
import * as Sentry from '@sentry/vue';
import { useAlert } from 'dashboard/composables';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { FUNIL, MODELOS, corDaPosicao } from './funil';
import { copiarEtapa } from './funilForm';

// #1384 — os modelos de "Começar pronto" do funil novo: as etapas do modelo,
// a frase padrão de cada uma (vinda do servidor) e a troca de modelo, que pede
// confirmação quando a pessoa já mudou alguma etapa.
export const useFunilModelo = ({ t, ia, form, editorSession }) => {
  const modelo = ref('VENDAS');
  const modeloPendente = ref('');
  // Frase padrão que o servidor deu para cada etapa, para saber se a pessoa
  // mudou a frase depois.
  const padroes = new WeakMap();

  const modeloAtual = computed(
    () => MODELOS.find(item => item.chave === modelo.value) || MODELOS[0]
  );
  const nomesDeModelo = computed(() =>
    MODELOS.map(item => t(`${FUNIL}.MODELOS.${item.chave}.NOME`))
  );

  const stagesDoModelo = item =>
    item.etapas.map((chave, index) => ({
      name: t(chave),
      color: corDaPosicao(index),
    }));
  const copiarEtapas = etapas =>
    etapas.map((etapa, index) => copiarEtapa(etapa, corDaPosicao(index)));

  // O funil novo mostra a frase padrão de cada etapa, a mesma que o servidor
  // grava quando ela fica em branco (Crm::Ai::DefaultStageCriteria). Só
  // preenche etapa que a pessoa ainda não tocou e cujo nome não mudou.
  const loadDefaultCriteria = async () => {
    if (!ia.value) return;
    const session = editorSession.value;
    const requested = form.stages.map(stage => ({ stage, name: stage.name }));
    try {
      const { data } = await CrmKanbanAPI.getStageCriteriaDefaults(
        requested.map(item => item.name)
      );
      if (session !== editorSession.value) return;
      (data.payload || []).forEach((item, index) => {
        const { stage, name } = requested[index] || {};
        if (!stage || stage.name !== name || stage.aiCriteria !== undefined)
          return;
        if (!item.criteria) return;
        stage.aiCriteria = item.criteria;
        padroes.set(stage, item.criteria);
      });
    } catch (error) {
      // A tela segue sem as frases prontas e o servidor ainda grava o padrão
      // ao salvar; a pessoa fica sabendo e o erro vai para o Sentry.
      Sentry.captureException(error);
      useAlert(t(`${FUNIL}.ETAPAS.PADRAO_ERRO`));
    }
  };

  // O modelo também traz pronto o "Quando usar este funil" (a primeira ideia).
  const quandoUsarDo = item => t(`${FUNIL}.SOBRE.IDEIAS.${item.ideias[0]}`);

  // A pessoa mudou alguma etapa do modelo: quantidade, nome, cor ou frase.
  const etapasMudaram = () => {
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
    modelo.value = item.chave;
    modeloPendente.value = '';
    editorSession.value += 1;
    if (!form.name.trim() || nomesDeModelo.value.includes(form.name.trim()))
      form.name = t(`${FUNIL}.MODELOS.${item.chave}.NOME`);
    if (!form.whenToUse.trim() || form.whenToUse === quandoUsarAntigo)
      form.whenToUse = quandoUsarDo(item);
    form.countsAsSale = item.venda;
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
  const confirmarModelo = () => {
    const item = MODELOS.find(opcao => opcao.chave === modeloPendente.value);
    if (item) trocarModelo(item);
  };
  const manterModelo = () => {
    modeloPendente.value = '';
  };

  const reiniciarModelo = () => {
    modelo.value = 'VENDAS';
    modeloPendente.value = '';
  };

  return {
    modelo,
    modeloAtual,
    modeloPendente,
    stagesDoModelo,
    copiarEtapas,
    loadDefaultCriteria,
    quandoUsarDo,
    escolherModelo,
    confirmarModelo,
    manterModelo,
    reiniciarModelo,
  };
};
