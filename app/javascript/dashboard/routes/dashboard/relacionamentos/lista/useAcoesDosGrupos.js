import { useAlert } from 'dashboard/composables';

// #3168 — o que a lista faz com os diálogos de "Meus grupos" (tirado de
// pages/ListaPage.vue): "Guardar como grupo" e "Trocar o nome" usam o mesmo
// diálogo (`dialogoDoNome`); "Apagar grupo" pede confirmação
// (`dialogoApagarGrupo`); os dois são refs da tela. "Mudar quem entra" abre a
// gaveta no modo do grupo; "Guardar no grupo" (da gaveta, com os filtros dela,
// ou da faixa "Você mudou quem aparece neste grupo", com os da tela) grava no
// grupo o que a tela mostra. Cada uma avisa quando dá certo.
// `aoGuardarNovo`: a tela passa para "Meus grupos" com o grupo novo escolhido.
const MG = 'RELACIONAMENTOS.LISTA.MEUS_GRUPOS';

export const useAcoesDosGrupos = ({
  meusGrupos,
  maisFiltros,
  t,
  aoGuardarNovo,
  dialogoDoNome,
  dialogoApagarGrupo,
}) => {
  const nomeDoEscolhido = () => meusGrupos.grupo.value?.nome ?? '';
  let grupoNovo = true;

  const abrirGuardar = () => {
    grupoNovo = true;
    dialogoDoNome.value?.abrir();
  };
  const abrirTrocarNome = () => {
    grupoNovo = false;
    dialogoDoNome.value?.abrir(nomeDoEscolhido());
  };
  const guardarNome = async nome => {
    const novo = grupoNovo;
    const deu = novo
      ? await meusGrupos.guardarComoGrupo(nome)
      : await meusGrupos.trocarNome(nome);
    if (!deu) return;
    dialogoDoNome.value?.fechar();
    if (novo) aoGuardarNovo();
    useAlert(t(novo ? `${MG}.GUARDADO` : `${MG}.NOME_TROCADO`));
  };

  const mudarGrupo = () => maisFiltros.abrirParaGrupo(meusGrupos.grupo.value);
  // A gaveta só fecha quando o grupo foi gravado: se a escrita falha, o que a
  // pessoa escolheu continua nela.
  const guardarNoGrupo = async novos => {
    if (!(await meusGrupos.guardarNoGrupo(novos))) return;
    maisFiltros.aberta.value = false;
    useAlert(t(`${MG}.GUARDADO`));
  };
  const guardarDaFaixa = () => guardarNoGrupo();

  const abrirApagarGrupo = () =>
    dialogoApagarGrupo.value?.abrir(nomeDoEscolhido());
  const apagarGrupo = async () => {
    if (!(await meusGrupos.apagar())) return;
    dialogoApagarGrupo.value?.fechar();
    useAlert(t(`${MG}.APAGADO`));
  };

  return {
    abrirGuardar,
    abrirTrocarNome,
    guardarNome,
    mudarGrupo,
    guardarNoGrupo,
    guardarDaFaixa,
    abrirApagarGrupo,
    apagarGrupo,
  };
};
