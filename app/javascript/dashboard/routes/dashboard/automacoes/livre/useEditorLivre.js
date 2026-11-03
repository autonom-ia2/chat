// #2414 F5 — o que o editor faz com a automação: carregar, salvar, guardar,
// ligar e desligar. #2486: cada mudança fica só na tela (o rascunho) até
// "Salvar tudo", que vira uma versão só; ligada ou desligada, a regra é a mesma.
// A nova fica só na tela até "Guardar sem ligar" ou "Ligar". Salvar e ligar
// levam a versão que a tela mostrou; se outra pessoa salvou no meio (409), o
// rascunho fica na tela com o aviso, e só "Ver a versão nova" o descarta.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import AutomacoesAPI from 'dashboard/api/autonomia/automacoes';
import { copiar, falta, iguais, receitaVazia } from './receita';
import { erroDaApi } from './erroDaApi';

const NAO_ACHOU = 404;

export function useEditorLivre() {
  const { t } = useI18n();

  const automacao = ref(null);
  const receita = ref(receitaVazia());
  const nome = ref('');
  const estado = ref('carregando');
  const problemas = ref([]);
  const ocupado = ref(false);
  const conflito = ref(false);

  const nova = computed(() => !automacao.value);
  const versaoId = computed(() => automacao.value?.versao?.id ?? null);
  const salva = computed(
    () => automacao.value?.versao?.receita || receitaVazia()
  );
  const mudou = computed(
    () => !nova.value && !iguais(receita.value, salva.value)
  );

  const mostrar = dados => {
    automacao.value = dados;
    receita.value = copiar(dados.versao?.receita || receitaVazia());
    nome.value = dados.nome;
  };

  // Ligar e desligar respondem sem a receita: a da tela continua valendo.
  const juntar = dados => {
    automacao.value = {
      ...automacao.value,
      ...dados,
      versao: { ...automacao.value.versao, ...dados.versao },
    };
  };

  const carregar = async id => {
    estado.value = 'carregando';
    problemas.value = [];
    conflito.value = false;
    if (!id) {
      automacao.value = null;
      receita.value = receitaVazia();
      nome.value = t('AUTOMACAO_LIVRE.EDITOR.NOVA');
      estado.value = 'pronto';
      return;
    }
    try {
      const { data } = await AutomacoesAPI.show(id);
      mostrar(data);
      estado.value = 'pronto';
    } catch (erro) {
      estado.value =
        erro?.response?.status === NAO_ACHOU ? 'nao_achou' : 'erro';
    }
  };

  // Uma chamada à API: 422 mostra o que corrigir; 409 deixa o rascunho na
  // tela com o aviso de conflito, sem recarregar por cima do que a pessoa fez.
  // No conflito só o desligar segue (sempre funciona, D7). O renomear (no blur
  // do nome) não ocupa a tela: senão o clique em "Salvar tudo" que tirou o
  // foco do nome cairia num botão já desligado.
  const pedir = async (
    chamada,
    { mesmoNoConflito = false, ocupa = true } = {}
  ) => {
    if (ocupado.value || (conflito.value && !mesmoNoConflito)) return false;
    ocupado.value = ocupa;
    problemas.value = [];
    try {
      await chamada();
      return true;
    } catch (erro) {
      const resposta = erroDaApi(erro, t);
      if (resposta.conflito) conflito.value = true;
      else useAlert(resposta.mensagem);
      problemas.value = resposta.problemas;
      return false;
    } finally {
      ocupado.value = false;
    }
  };

  // Cada "Salvar" e "Tirar" do Alterar só muda a tela.
  const aplicar = novaReceita => {
    receita.value = novaReceita;
    return Promise.resolve(true);
  };

  const gravarRascunho = async () => {
    const estavaLigada = automacao.value.ativa;
    const { data } = await AutomacoesAPI.salvar(automacao.value.id, {
      receita: receita.value,
      baseVersaoId: versaoId.value,
    });
    mostrar(data);
    return estavaLigada && !data.ativa;
  };

  const salvarTudo = () => {
    if (!mudou.value || falta(receita.value)) return Promise.resolve(false);
    return pedir(async () => {
      const pausou = await gravarRascunho();
      useAlert(
        pausou
          ? t('AUTOMACAO_LIVRE.EDITOR.PAUSOU')
          : t('AUTOMACAO_LIVRE.EDITOR.SALVOU')
      );
    });
  };

  const descartar = () => {
    receita.value = copiar(salva.value);
    problemas.value = [];
    useAlert(t('AUTOMACAO_LIVRE.EDITOR.DESCARTOU'));
  };

  // Depois do conflito: o rascunho sai e entra a versão que a outra pessoa
  // salvou.
  const verNova = () => carregar(automacao.value.id);

  const criar = async () => {
    const { data } = await AutomacoesAPI.create({
      nome: nome.value,
      receita: receita.value,
    });
    mostrar(data);
  };

  const guardar = () =>
    pedir(async () => {
      await criar();
      useAlert(t('AUTOMACAO_LIVRE.EDITOR.GUARDOU'));
    });

  // Ligar com mudança na tela salva antes: liga o que a pessoa está vendo.
  const ligar = () =>
    pedir(async () => {
      if (nova.value) await criar();
      else if (mudou.value) await gravarRascunho();
      const { data } = await AutomacoesAPI.ligar(
        automacao.value.id,
        versaoId.value
      );
      juntar(data);
      useAlert(t('AUTOMACAO_LIVRE.LIGOU'));
    });

  const desligar = () =>
    pedir(
      async () => {
        const { data } = await AutomacoesAPI.desligar(automacao.value.id);
        juntar(data);
        useAlert(t('AUTOMACAO_LIVRE.DESLIGOU'));
      },
      { mesmoNoConflito: true }
    );

  const renomear = () => {
    const texto = nome.value.trim();
    if (nova.value || !texto || texto === automacao.value.nome) return null;
    return pedir(
      async () => {
        const { data } = await AutomacoesAPI.renomear(
          automacao.value.id,
          texto
        );
        juntar(data);
      },
      { ocupa: false }
    );
  };

  return {
    automacao,
    receita,
    nome,
    estado,
    problemas,
    ocupado,
    conflito,
    nova,
    mudou,
    carregar,
    aplicar,
    salvarTudo,
    descartar,
    verNova,
    guardar,
    ligar,
    desligar,
    renomear,
  };
}
