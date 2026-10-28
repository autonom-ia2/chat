import { useI18n } from 'vue-i18n';
import { LEVELS } from '../../customRoles/permissionMatrix';

// Textos que várias etapas montam do mesmo jeito (#2308): listas com "e", o nome de um nível e a primeira letra
// maiúscula. Tudo por i18n, sem regex.
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

  const rotuloDoNivel = (module, nivel) =>
    t(`FUNCOES_EQUIPE.GUIADA.NIVEL.${ROTULO_DO_NIVEL[nivel](module)}`);

  const antesDoNivel = (module, nivel) =>
    t(`FUNCOES_EQUIPE.GUIADA.ANTES.${ROTULO_DO_NIVEL[nivel](module)}`);

  const nomeDaArea = key => t(`FUNCOES_EQUIPE.AREAS.${key}.NOME`);

  return { t, te, lista, maiuscula, rotuloDoNivel, antesDoNivel, nomeDaArea };
}
