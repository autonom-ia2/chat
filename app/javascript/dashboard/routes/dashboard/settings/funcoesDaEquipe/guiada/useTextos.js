import { useI18n } from 'vue-i18n';
import { LEVELS } from '../../customRoles/permissionMatrix';
import { soOlhaNaArea } from '../fraseDaFuncao';

// Textos que várias etapas montam do mesmo jeito (#2308): listas com "e", o nome de um nível, a primeira letra
// maiúscula e o começo das perguntas ("Com a função Atendente", sem artigo de gênero). Tudo por i18n, sem regex.
const ROTULO_DO_NIVEL = {
  [LEVELS.VIEW]: module => (module.levels?.manage ? 'SO_OLHA' : 'VE'),
  [LEVELS.MANAGE]: () => 'PODE_MEXER',
  [LEVELS.NONE]: module =>
    module.baseline ? `BASE_${module.baseline}` : 'NAO_VE',
};

// Com `permissions`, o rótulo diz o estado da função: no nível de ver, "Só olha" só quando nada muda na área
// (soOlhaNaArea); senão "Vê". Sem elas, é o nome da opção na escolha do nível.
const rotulo = (module, nivel, permissions) =>
  nivel === LEVELS.VIEW && permissions && !soOlhaNaArea(module.key, permissions)
    ? 'VE'
    : ROTULO_DO_NIVEL[nivel](module);

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

  const rotuloDoNivel = (module, nivel, permissions = null) =>
    t(`FUNCOES_EQUIPE.GUIADA.NIVEL.${rotulo(module, nivel, permissions)}`);

  const antesDoNivel = (module, nivel, permissions = null) =>
    t(`FUNCOES_EQUIPE.GUIADA.ANTES.${rotulo(module, nivel, permissions)}`);

  const nomeDaArea = key => t(`FUNCOES_EQUIPE.AREAS.${key}.NOME`);

  // "Com a função Atendente" (sem nome, "Com esta função"): o sujeito das perguntas é a pessoa, e a função entra sem
  // artigo, porque o nome dela pode ter qualquer gênero.
  const comAFuncao = nome =>
    nome
      ? t('FUNCOES_EQUIPE.GUIADA.COM_A_FUNCAO', { nome })
      : t('FUNCOES_EQUIPE.GUIADA.COM_ESTA_FUNCAO');

  return {
    t,
    te,
    lista,
    maiuscula,
    minuscula,
    rotuloDoNivel,
    antesDoNivel,
    nomeDaArea,
    comAFuncao,
  };
}
