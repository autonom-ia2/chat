// #2897 — o que a carteira soma à lista de pessoas e de empresas em conta de
// seguros: o selo do seguro mais urgente de cada uma, "· Auto vence em 18 dias"
// na segunda linha, o grupo "Só tem um seguro" (depois de "Clientes") e a busca
// por placa e número da apólice. Desligada (`ligada: false`), devolve tudo
// vazio e a lista do bloco A fica como era.
import { shallowRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { carteiraFonte } from '../fonte/carteiraFonte';
import { ABAS, gruposDaAba } from '../fonte/grupos';
import {
  GRUPO_DE_PESSOAS_SO_UM_SEGURO,
  GRUPO_SO_UM_SEGURO,
} from '../fonte/gruposDeSeguros';
import { SELOS } from '../fonte/selosDoSeguro';
import { chaveDoTipo } from './tiposDeSeguro';

const GRUPO_ANTES_DO_NOVO = 'clientes';
const SEM_RESUMOS = Object.freeze({ pessoas: {}, empresas: {} });

const comOGrupoNovo = grupos =>
  grupos.flatMap(grupo =>
    grupo.id === GRUPO_ANTES_DO_NOVO
      ? [grupo, GRUPO_DE_PESSOAS_SO_UM_SEGURO]
      : [grupo]
  );

export const useCarteiraNaLista = ({ demo, ligada }) => {
  const { t } = useI18n();
  const fonte = ligada ? carteiraFonte({ demo }) : null;
  const resumos = shallowRef(SEM_RESUMOS);

  // A carteira fora do ar não derruba a lista de pessoas: ela aparece sem os
  // selos, e é a aba Seguros que mostra o erro.
  const ler = async () => {
    try {
      const [pessoas, empresas] = await Promise.all([
        fonte.resumoPorPessoa(),
        fonte.resumoPorEmpresa(),
      ]);
      return { pessoas, empresas };
    } catch {
      return SEM_RESUMOS;
    }
  };

  const complemento = async () => {
    const { pessoas } = await ler();
    const buscaDe = pessoa => pessoas[pessoa.id]?.busca ?? [];
    return {
      grupos: {
        [GRUPO_SO_UM_SEGURO]: pessoa => pessoas[pessoa.id]?.quantos === 1,
      },
      campos: pessoa => ({ textos: buscaDe(pessoa), numeros: buscaDe(pessoa) }),
    };
  };

  const comSelo = resumo => (resumo?.selo ? resumo : null);

  // "Auto vence em 18 dias": só quando o selo é "Em renovação".
  const partesDaPessoa = id => {
    const resumo = resumos.value.pessoas[id];
    if (resumo?.selo !== SELOS.EM_RENOVACAO) return [];
    const tipo = t(chaveDoTipo(resumo.tipo));
    return [
      resumo.dias > 0
        ? t(
            'RELACIONAMENTOS_CARTEIRA.PESSOAS.TIPO_VENCE_EM',
            { tipo, count: resumo.dias },
            resumo.dias
          )
        : t('RELACIONAMENTOS_CARTEIRA.PESSOAS.TIPO_VENCE_HOJE', { tipo }),
    ];
  };

  return {
    complemento: ligada ? complemento : null,
    carregar: async () => {
      if (ligada) resumos.value = await ler();
    },
    grupos: aba =>
      ligada && aba === ABAS.PESSOAS
        ? comOGrupoNovo(gruposDaAba(aba))
        : gruposDaAba(aba),
    daPessoa: id => comSelo(resumos.value.pessoas[id]),
    daEmpresa: id => comSelo(resumos.value.empresas[id]),
    partesDaPessoa: ligada ? partesDaPessoa : () => [],
  };
};
