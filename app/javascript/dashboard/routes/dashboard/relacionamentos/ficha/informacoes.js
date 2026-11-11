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

// "melhor_horario" -> "Melhor horario": o nome que a conta deu à informação.
export const nomeDaInformacao = chave => {
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
  const fixas = [
    { chave: 'telefone', valor: pessoa.phone_number },
    { chave: 'email', valor: pessoa.email },
    { chave: 'cpf', valor: cpf ? formatarCpf(cpf) : '', copiar: true },
    { chave: 'cidade', valor: adicionais.city },
    { chave: 'empresa', valor: adicionais.company_name },
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
    extras: Object.fromEntries(
      extrasDaConta(pessoa).map(([chave, valor]) => [
        chave,
        String(valor ?? ''),
      ])
    ),
  };
};

const soOQuePreencheu = objeto =>
  Object.fromEntries(
    Object.entries(objeto).filter(([, valor]) => preenchido(valor))
  );

// O formato que a fonte recebe (o mesmo do contato no servidor).
export const dadosParaSalvar = formulario => ({
  name: formulario.nome.trim(),
  phone_number: formulario.telefone || null,
  email: formulario.email.trim() || null,
  additional_attributes: {
    city: formulario.cidade.trim(),
    company_name: formulario.empresa.trim(),
    social_profiles: soOQuePreencheu(formulario.redes),
  },
  custom_attributes: soOQuePreencheu({
    ...(formulario.cpf ? { [CHAVE_DO_CPF]: soDigitos(formulario.cpf) } : {}),
    ...formulario.extras,
  }),
});

export const linhasDaEmpresa = empresa => [
  { chave: 'cnpj', valor: empresa.cnpj ? formatarCnpj(empresa.cnpj) : '' },
  { chave: 'site', valor: empresa.domain },
  { chave: 'pessoas', valor: String(empresa.contacts_count ?? 0) },
  { chave: 'clientes', valor: String(empresa.customers_count ?? 0) },
];
