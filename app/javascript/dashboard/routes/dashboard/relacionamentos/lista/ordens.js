import { ORDENS } from '../fonte/listaFonte';

// #3062 — as ordens da aba Pessoas: as sete da lista de contatos de hoje
// (última conversa, nome, e-mail, empresa, cidade, país e quando chegou), cada
// uma nos dois sentidos. O valor é o nome que o servidor conhece
// (Relacionamentos::ConsultaDePessoas). A aba Empresas segue com as três de
// sempre (ORDENS).
const ORDEM = 'RELACIONAMENTOS.LISTA.ORDENAR';

const campo = (chave, ordens) => ({ chave, ordens });
const ordem = (value, sentido) => ({ value, sentido });

export const CAMPOS_DE_ORDEM = [
  campo('ULTIMA_CONVERSA', [
    ordem(ORDENS.ULTIMA_CONVERSA, 'RECENTE'),
    ordem('conversa_mais_antiga', 'ANTIGA'),
  ]),
  campo('NOME', [ordem(ORDENS.NOME, 'A_Z'), ordem('nome_z_a', 'Z_A')]),
  campo('EMAIL', [ordem('email_a_z', 'A_Z'), ordem('email_z_a', 'Z_A')]),
  campo('EMPRESA', [ordem('empresa_a_z', 'A_Z'), ordem('empresa_z_a', 'Z_A')]),
  campo('CIDADE', [ordem('cidade_a_z', 'A_Z'), ordem('cidade_z_a', 'Z_A')]),
  campo('PAIS', [ordem('pais_a_z', 'A_Z'), ordem('pais_z_a', 'Z_A')]),
  campo('CHEGADA', [
    ordem(ORDENS.MAIS_NOVOS, 'RECENTE'),
    ordem('mais_antigos', 'ANTIGA'),
  ]),
];

// As escolhas da lista, agrupadas por campo (o `groups` do ChoiceSelect). O
// botão fechado mostra o campo e o sentido juntos ("Cidade, de A a Z").
export const gruposDeOrdem = t =>
  CAMPOS_DE_ORDEM.map(({ chave, ordens }) => ({
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
const NA_PREFERENCIA = {
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

export const ordemDaPreferencia = guardada =>
  Object.keys(NA_PREFERENCIA).find(
    valor => NA_PREFERENCIA[valor] === guardada
  ) ?? ORDENS.ULTIMA_CONVERSA;

export const preferenciaDaOrdem = valor => NA_PREFERENCIA[valor] ?? null;
