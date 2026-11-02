// #2414 F5 — o que o editor faz com a automação: carregar, salvar cada mudança
// como versão nova, guardar, ligar e desligar. Salvar e ligar levam a versão que
// a tela mostrou; se outra pessoa salvou no meio (409), a tela recarrega e avisa.
// A nova fica só na tela até "Guardar sem ligar" ou "Ligar". Na salva, a receita
// que o esquema recusaria (um "Se" ainda sem passo) também fica só na tela até
// a pessoa completar: salvar ali só daria erro.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import AutomacoesAPI from 'dashboard/api/autonomia/automacoes';
import { copiar, falta, receitaVazia } from './receita';
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

  const nova = computed(() => !automacao.value);
  const versaoId = computed(() => automacao.value?.versao?.id ?? null);

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

  // Uma chamada à API: 409 recarrega e avisa; 422 mostra o que corrigir.
  const pedir = async chamada => {
    if (ocupado.value) return false;
    ocupado.value = true;
    problemas.value = [];
    try {
      await chamada();
      return true;
    } catch (erro) {
      const resposta = erroDaApi(erro, t);
      useAlert(resposta.mensagem);
      problemas.value = resposta.problemas;
      if (resposta.conflito && automacao.value)
        await carregar(automacao.value.id);
      return false;
    } finally {
      ocupado.value = false;
    }
  };

  // Cada "Salvar" do Alterar: na nova, ou enquanto falta completar, só a tela
  // muda; na salva e completa, vira versão.
  const aplicar = novaReceita => {
    if (nova.value || falta(novaReceita)) {
      receita.value = novaReceita;
      return Promise.resolve(true);
    }
    const estavaLigada = automacao.value.ativa;
    return pedir(async () => {
      const { data } = await AutomacoesAPI.salvar(automacao.value.id, {
        receita: novaReceita,
        baseVersaoId: versaoId.value,
      });
      mostrar(data);
      useAlert(
        estavaLigada && !data.ativa
          ? t('AUTOMACAO_LIVRE.EDITOR.PAUSOU')
          : t('AUTOMACAO_LIVRE.EDITOR.SALVOU')
      );
    });
  };

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

  const ligar = () =>
    pedir(async () => {
      if (nova.value) await criar();
      const { data } = await AutomacoesAPI.ligar(
        automacao.value.id,
        versaoId.value
      );
      juntar(data);
      useAlert(t('AUTOMACAO_LIVRE.LIGOU'));
    });

  const desligar = () =>
    pedir(async () => {
      const { data } = await AutomacoesAPI.desligar(automacao.value.id);
      juntar(data);
      useAlert(t('AUTOMACAO_LIVRE.DESLIGOU'));
    });

  const renomear = () => {
    const texto = nome.value.trim();
    if (nova.value || !texto || texto === automacao.value.nome) return null;
    return pedir(async () => {
      const { data } = await AutomacoesAPI.renomear(automacao.value.id, texto);
      juntar(data);
    });
  };

  return {
    automacao,
    receita,
    nome,
    estado,
    problemas,
    ocupado,
    nova,
    carregar,
    aplicar,
    guardar,
    ligar,
    desligar,
    renomear,
  };
}
