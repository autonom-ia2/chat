import { ORDENS } from '../fonte/listaFonte';

// #3062 — as ordens da aba Pessoas: as sete da lista de contatos de hoje
// (última conversa, nome, e-mail, empresa, cidade, país e quando chegou), cada
// uma nos dois sentidos, na ordem de uso (as de data primeiro, e-mail por
// último). O valor é o nome que o servidor conhece
// (Relacionamentos::ConsultaDePessoas).
// #3078 — a aba Empresas ganha as cinco da lista de Empresas de hoje (última
// conversa, quando chegou, nome, site e número de pessoas), também nos dois
// sentidos (Relacionamentos::ConsultaDeEmpresas), guardadas na preferência
// dela (`companies_sort_by`).
const ORDEM = 'RELACIONAMENTOS.LISTA.ORDENAR';

const campo = (chave, ordens) => ({ chave, ordens });
const ordem = (value, sentido) => ({ value, sentido });

export const CAMPOS_DE_ORDEM = [
  campo('ULTIMA_CONVERSA', [
    ordem(ORDENS.ULTIMA_CONVERSA, 'RECENTE'),
    ordem('conversa_mais_antiga', 'ANTIGA'),
  ]),
  campo('CHEGADA', [
    ordem(ORDENS.MAIS_NOVOS, 'RECENTE'),
    ordem('mais_antigos', 'ANTIGA'),
  ]),
  campo('NOME', [ordem(ORDENS.NOME, 'A_Z'), ordem('nome_z_a', 'Z_A')]),
  campo('CIDADE', [ordem('cidade_a_z', 'A_Z'), ordem('cidade_z_a', 'Z_A')]),
  campo('EMPRESA', [ordem('empresa_a_z', 'A_Z'), ordem('empresa_z_a', 'Z_A')]),
  campo('PAIS', [ordem('pais_a_z', 'A_Z'), ordem('pais_z_a', 'Z_A')]),
  campo('EMAIL', [ordem('email_a_z', 'A_Z'), ordem('email_z_a', 'Z_A')]),
];

export const CAMPOS_DE_ORDEM_DAS_EMPRESAS = [
  CAMPOS_DE_ORDEM[0],
  CAMPOS_DE_ORDEM[1],
  CAMPOS_DE_ORDEM[2],
  campo('SITE', [ordem('site_a_z', 'A_Z'), ordem('site_z_a', 'Z_A')]),
  campo('PESSOAS', [
    ordem('mais_pessoas', 'MAIS'),
    ordem('menos_pessoas', 'MENOS'),
  ]),
];

// As escolhas da lista, agrupadas por campo (o `groups` do ChoiceSelect). O
// botão fechado mostra o campo e o sentido juntos ("Cidade, de A a Z").
export const gruposDeOrdem = (t, campos = CAMPOS_DE_ORDEM) =>
  campos.map(({ chave, ordens }) => ({
    label: t(`${ORDEM}.CAMPOS.${chave}`),
    options: ordens.map(({ value, sentido }) => {
      const escolhida = t(`${ORDEM}.ESCOLHIDA.${chave}_${sentido}`);
      return {
        value,
        label: t(`${ORDEM}.SENTIDOS.${sentido}`),
        shortLabel: escolhida,
        searchLabel: escolhida,
      };
    }),
  }));

// A ordem de cada pessoa da equipe fica guardada como a lista de contatos de
// hoje guarda (`contacts_sort_by` nas preferências do usuário, com "-" na
// frente para o sentido decrescente): escolher numa tela vale na outra.
export const NA_PREFERENCIA = {
  [ORDENS.ULTIMA_CONVERSA]: '-last_activity_at',
  conversa_mais_antiga: 'last_activity_at',
  [ORDENS.NOME]: 'name',
  nome_z_a: '-name',
  email_a_z: 'email',
  email_z_a: '-email',
  empresa_a_z: 'company_name',
  empresa_z_a: '-company_name',
  cidade_a_z: 'city',
  cidade_z_a: '-city',
  pais_a_z: 'country',
  pais_z_a: '-country',
  [ORDENS.MAIS_NOVOS]: '-created_at',
  mais_antigos: 'created_at',
};

export const CHAVE_DA_PREFERENCIA = 'contacts_sort_by';

// #3078 — a da lista de Empresas de hoje (CompaniesIndex), no mesmo formato.
export const NA_PREFERENCIA_DAS_EMPRESAS = {
  [ORDENS.ULTIMA_CONVERSA]: '-last_activity_at',
  conversa_mais_antiga: 'last_activity_at',
  [ORDENS.NOME]: 'name',
  nome_z_a: '-name',
  site_a_z: 'domain',
  site_z_a: '-domain',
  [ORDENS.MAIS_NOVOS]: '-created_at',
  mais_antigos: 'created_at',
  mais_pessoas: '-contacts_count',
  menos_pessoas: 'contacts_count',
};

export const CHAVE_DA_PREFERENCIA_DAS_EMPRESAS = 'companies_sort_by';

// A preferência que a lista nova não tem (a de hoje também ordena por telefone,
// `phone_number`) abre pela última conversa e não é regravada: só a escolha da
// pessoa grava (useOrdemGuardada), e a lista de hoje segue na dela.
// `tabela`: a de cada aba (NA_PREFERENCIA ou NA_PREFERENCIA_DAS_EMPRESAS).
export const ordemNaTabela = (tabela, guardada) =>
  Object.keys(tabela).find(valor => tabela[valor] === guardada) ??
  ORDENS.ULTIMA_CONVERSA;

export const preferenciaNaTabela = (tabela, valor) => tabela[valor] ?? null;

export const ordemDaPreferencia = guardada =>
  ordemNaTabela(NA_PREFERENCIA, guardada);

export const preferenciaDaOrdem = valor =>
  preferenciaNaTabela(NA_PREFERENCIA, valor);
