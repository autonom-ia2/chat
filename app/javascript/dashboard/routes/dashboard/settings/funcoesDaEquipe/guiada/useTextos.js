import { useI18n } from 'vue-i18n';
import { LEVELS } from '../../customRoles/permissionMatrix';

// Textos que várias etapas montam do mesmo jeito (#2308): listas com "e", o nome de um nível, a primeira letra
// maiúscula e quem tem a função nas perguntas ("quem for Atendente", sem gênero). Tudo por i18n, sem regex.
const ROTULO_DO_NIVEL = {
  [LEVELS.VIEW]: module => (module.levels?.manage ? 'SO_OLHA' : 'VE'),
  [LEVELS.MANAGE]: () => 'PODE_MEXER',
  [LEVELS.NONE]: module =>
    module.baseline ? `BASE_${module.baseline}` : 'NAO_VE',
};

export function useTextos() {
  const { t, te, locale } = useI18n();

  const lista = itens =>
    new Intl.ListFormat(String(locale.value).replaceAll('_', '-'), {
      type: 'conjunction',
    }).format(itens);

  const maiuscula = texto =>
    texto ? `${texto.charAt(0).toLocaleUpperCase()}${texto.slice(1)}` : '';
  const minuscula = texto =>
    texto ? `${texto.charAt(0).toLocaleLowerCase()}${texto.slice(1)}` : '';

  const rotuloDoNivel = (module, nivel) =>
    t(`FUNCOES_EQUIPE.GUIADA.NIVEL.${ROTULO_DO_NIVEL[nivel](module)}`);

  const antesDoNivel = (module, nivel) =>
    t(`FUNCOES_EQUIPE.GUIADA.ANTES.${ROTULO_DO_NIVEL[nivel](module)}`);

  const nomeDaArea = key => t(`FUNCOES_EQUIPE.AREAS.${key}.NOME`);

  // forma: OBJETO ("quem for Atendente"), SUJEITO ("Quem for Atendente") ou NOME ("Atendente"); sem nome, "esta função".
  // SUJEITO é a forma do começo do título em pt; em en a pergunta começa pelo verbo, e ela fica minúscula.
  const quemFor = (nome, forma = 'OBJETO') =>
    nome
      ? t(`FUNCOES_EQUIPE.GUIADA.QUEM.${forma}`, { nome })
      : t(`FUNCOES_EQUIPE.GUIADA.QUEM.${forma}_SEM_NOME`);

  return {
    t,
    te,
    lista,
    maiuscula,
    minuscula,
    rotuloDoNivel,
    antesDoNivel,
    nomeDaArea,
    quemFor,
  };
}
