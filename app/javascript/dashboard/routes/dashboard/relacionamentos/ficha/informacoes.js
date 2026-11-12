// #2894 — as informações da pessoa: a lista da coluna do lado, o formulário da
// gaveta e o que volta dele para a fonte. Funções puras, sem mutar o que recebem.
import { formatarCnpj, formatarCpf } from './formatos';
import { soDigitos } from '../fonte/texto';

export const REDES = [
  'linkedin',
  'facebook',
  'instagram',
  'whatsapp',
  'telegram',
  'tiktok',
  'twitter',
  'github',
];

const CHAVE_DO_CPF = 'cpf';

const preenchido = valor => String(valor ?? '').trim() !== '';

// O nome que a conta deu à informação. A chave não tem acento, então os nomes
// conhecidos vêm daqui; os outros saem da própria chave ("cor_favorita" ->
// "Cor favorita"). No servidor o nome de exibição da informação substitui isto
// (entrega E2, #2895).
const NOMES_CONHECIDOS = {
  melhor_horario: 'Melhor horário',
  como_prefere_ser_chamado: 'Como prefere ser chamado',
};

export const nomeDaInformacao = chave => {
  if (NOMES_CONHECIDOS[chave]) return NOMES_CONHECIDOS[chave];
  const palavras = String(chave).split('_').filter(Boolean).join(' ');
  return palavras.charAt(0).toUpperCase() + palavras.slice(1);
};

const extrasDaConta = pessoa =>
  Object.entries(pessoa.custom_attributes ?? {}).filter(
    ([chave]) => chave !== CHAVE_DO_CPF
  );

export const linhasDaPessoa = pessoa => {
  const adicionais = pessoa.additional_attributes ?? {};
  const cpf = pessoa.custom_attributes?.[CHAVE_DO_CPF];
  // Telefone, e-mail e empresa ficam só no cabeçalho; a gaveta os edita.
  const fixas = [
    { chave: 'cpf', valor: cpf ? formatarCpf(cpf) : '', copiar: true },
    { chave: 'cidade', valor: adicionais.city },
  ];
  const daConta = extrasDaConta(pessoa).map(([chave, valor]) => ({
    chave: `conta:${chave}`,
    rotulo: nomeDaInformacao(chave),
    valor: String(valor ?? ''),
  }));
  return [...fixas, ...daConta].map(linha => ({
    ...linha,
    valor: preenchido(linha.valor) ? String(linha.valor) : '',
  }));
};

export const redesPreenchidas = pessoa =>
  Object.entries(pessoa.additional_attributes?.social_profiles ?? {})
    .filter(([rede, usuario]) => REDES.includes(rede) && preenchido(usuario))
    .map(([rede, usuario]) => ({ rede, usuario }));

export const formularioDaPessoa = pessoa => {
  const adicionais = pessoa.additional_attributes ?? {};
  const perfis = adicionais.social_profiles ?? {};
  return {
    nome: pessoa.name ?? '',
    telefone: pessoa.phone_number ?? '',
    email: pessoa.email ?? '',
    cpf: formatarCpf(pessoa.custom_attributes?.[CHAVE_DO_CPF] ?? ''),
    cidade: adicionais.city ?? '',
    empresa: adicionais.company_name ?? '',
    redes: Object.fromEntries(REDES.map(rede => [rede, perfis[rede] ?? ''])),
    // Rede que a gaveta não mostra: vai e volta sem ninguém mexer.
    outrasRedes: Object.fromEntries(
      Object.entries(perfis).filter(([rede]) => !REDES.includes(rede))
    ),
    extras: Object.fromEntries(
      extrasDaConta(pessoa).map(([chave, valor]) => [
        chave,
        String(valor ?? ''),
      ])
    ),
  };
};

// O que a pessoa preencheu, mais `''` explícito para o que existia no formulário
// inicial e ela apagou (limpar um campo tem de limpar). O que nunca existiu fica
// de fora. O servidor junta `custom_attributes` e `additional_attributes` com o
// que o contato já tinha (ContactsController#contact_update_params): chave que
// não vai fica como estava, e por isso o apagado vai como texto vazio.
const comVaziosExplicitos = (atual, inicial) =>
  Object.fromEntries(
    Object.entries(atual).flatMap(([chave, valor]) => {
      if (preenchido(valor)) return [[chave, valor]];
      return preenchido(inicial?.[chave]) ? [[chave, '']] : [];
    })
  );

// O formato que a fonte recebe (o mesmo do contato no servidor). `inicial` é o
// formulário de quando a gaveta abriu.
export const dadosParaSalvar = (formulario, inicial = null) => ({
  name: formulario.nome.trim(),
  phone_number: formulario.telefone || null,
  email: formulario.email.trim() || null,
  additional_attributes: {
    city: formulario.cidade.trim(),
    company_name: formulario.empresa.trim(),
    // O servidor troca `social_profiles` inteiro: o que a gaveta não mostra
    // tem de ir junto, senão some.
    social_profiles: {
      ...formulario.outrasRedes,
      ...comVaziosExplicitos(formulario.redes, inicial?.redes),
    },
  },
  custom_attributes: comVaziosExplicitos(
    {
      [CHAVE_DO_CPF]: formulario.cpf ? soDigitos(formulario.cpf) : '',
      ...formulario.extras,
    },
    {
      [CHAVE_DO_CPF]: inicial?.cpf,
      ...inicial?.extras,
    }
  ),
});

// CNPJ e site ficam só no cabeçalho da empresa.
export const linhasDaEmpresa = empresa => [
  { chave: 'pessoas', valor: String(empresa.contacts_count ?? 0) },
  { chave: 'clientes', valor: String(empresa.customers_count ?? 0) },
];

// A gaveta "Alterar" da empresa: nome, CNPJ e site. O CNPJ vai só com os números.
export const formularioDaEmpresa = empresa => ({
  nome: empresa.name ?? '',
  cnpj: formatarCnpj(empresa.cnpj ?? ''),
  site: empresa.domain ?? '',
});

export const dadosDaEmpresaParaSalvar = formulario => ({
  name: formulario.nome.trim(),
  cnpj: soDigitos(formulario.cnpj),
  domain: formulario.site.trim(),
});
