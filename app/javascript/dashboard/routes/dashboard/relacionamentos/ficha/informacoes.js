// #2894 — as informações da pessoa: a lista da coluna do lado, o formulário da
// gaveta e o que volta dele para a fonte. Funções puras, sem mutar o que recebem.
// #3075 — e os dados que a ficha antiga tinha: país e "Sobre a pessoa"
// (additional_attributes.country_code, country e description), a empresa
// cadastrada (company_id), a foto e os campos personalizados com o tipo de cada
// um (ficha/atributos.js).
import { formatarCnpj, formatarCpf } from './formatos';
import { soDigitos } from '../fonte/texto';
import { CHAVE_DO_CPF, nomeDaInformacao, temValor } from './atributos';
import { nomeGravadoDoPais, paisNaTela } from './paises';

export { nomeDaInformacao };

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

const preenchido = valor => String(valor ?? '').trim() !== '';

// As linhas de Informações: CPF, cidade, país, "Sobre a pessoa" e os campos
// personalizados que aparecem na ficha (`campos`, de camposDaPessoa). Telefone,
// e-mail e empresa ficam só no cabeçalho; a gaveta os edita. Cada linha:
// { chave, valor, rotulo?, tipo?, copiar?, longo? }. O valor dos campos
// personalizados vai como está gravado (a lista formata pelo `tipo`).
export const linhasDaPessoa = (
  pessoa,
  { idioma = 'pt-BR', campos = [] } = {}
) => {
  const adicionais = pessoa.additional_attributes ?? {};
  const cpf = pessoa.custom_attributes?.[CHAVE_DO_CPF];
  // CPF e cidade aparecem sempre (com "Não informado"); país e "Sobre a
  // pessoa", só preenchidos.
  const fixas = [
    { chave: 'cpf', valor: cpf ? formatarCpf(cpf) : '', copiar: true },
    { chave: 'cidade', valor: adicionais.city },
    { chave: 'pais', valor: paisNaTela(adicionais, idioma), soCheia: true },
    {
      chave: 'sobre',
      valor: adicionais.description,
      longo: true,
      soCheia: true,
    },
  ]
    .filter(linha => !linha.soCheia || preenchido(linha.valor))
    .map(({ soCheia: _soCheia, ...linha }) => ({
      ...linha,
      valor: preenchido(linha.valor) ? String(linha.valor).trim() : '',
    }));
  const daConta = campos
    .filter(campo => campo.principal)
    .map(campo => ({
      chave: `conta:${campo.chave}`,
      rotulo: campo.rotulo,
      tipo: campo.tipo,
      valor: temValor(campo.valor) ? campo.valor : '',
    }));
  return [...fixas, ...daConta];
};

export const redesPreenchidas = pessoa =>
  Object.entries(pessoa.additional_attributes?.social_profiles ?? {})
    .filter(([rede, usuario]) => REDES.includes(rede) && preenchido(usuario))
    .map(([rede, usuario]) => ({ rede, usuario }));

// O formulário da gaveta. `atributos` são os campos personalizados como estão
// gravados (o número continua número, o "marcado" continua verdadeiro); a
// gaveta escreve neles pelo tipo de cada campo. `foto` nasce vazia: é a troca
// pedida ({ arquivo, previa }) ou { tirar: true }.
export const formularioDaPessoa = pessoa => {
  const adicionais = pessoa.additional_attributes ?? {};
  const perfis = adicionais.social_profiles ?? {};
  const { [CHAVE_DO_CPF]: cpf, ...atributos } = pessoa.custom_attributes ?? {};
  return {
    nome: pessoa.name ?? '',
    telefone: pessoa.phone_number ?? '',
    email: pessoa.email ?? '',
    cpf: formatarCpf(cpf ?? ''),
    cidade: adicionais.city ?? '',
    pais: adicionais.country_code ?? '',
    sobre: adicionais.description ?? '',
    empresa: adicionais.company_name ?? '',
    empresaId: pessoa.company_id ?? null,
    empresaNova: false,
    foto: null,
    redes: Object.fromEntries(REDES.map(rede => [rede, perfis[rede] ?? ''])),
    // Rede que a gaveta não mostra: vai e volta sem ninguém mexer.
    outrasRedes: Object.fromEntries(
      Object.entries(perfis).filter(([rede]) => !REDES.includes(rede))
    ),
    atributos,
  };
};

// O que a pessoa preencheu, mais `''` explícito para o que existia no formulário
// inicial e ela apagou (limpar um campo tem de limpar). O que nunca existiu fica
// de fora. O servidor junta `additional_attributes` com o que o contato já tinha
// (ContactsController#contact_update_params): chave que não vai fica como
// estava, e por isso o apagado vai como texto vazio.
const comVaziosExplicitos = (atual, inicial) =>
  Object.fromEntries(
    Object.entries(atual).flatMap(([chave, valor]) => {
      if (preenchido(valor)) return [[chave, valor]];
      return preenchido(inicial?.[chave]) ? [[chave, '']] : [];
    })
  );

// Os campos personalizados mudados. Os preenchidos vão em `custom_attributes`
// (o servidor junta com o que já havia); os que tinham valor e ficaram vazios
// vão em `apagar`, e saem de verdade da ficha (destroy_custom_attributes), como
// o "Apagar" da ficha antiga. O que ninguém mexeu não vai.
const atributosMudados = (atual, inicial) => {
  const chaves = [...new Set([...Object.keys(atual), ...Object.keys(inicial)])];
  const mudadas = chaves.filter(chave => atual[chave] !== inicial[chave]);
  return {
    gravar: Object.fromEntries(
      mudadas
        .filter(chave => temValor(atual[chave]))
        .map(chave => [chave, atual[chave]])
    ),
    apagar: mudadas.filter(
      chave => !temValor(atual[chave]) && temValor(inicial[chave])
    ),
  };
};

const cpfComoAtributo = cpf => (cpf ? soDigitos(cpf) : '');

// A empresa: com a chave `companies`, o vínculo com a empresa cadastrada vai
// por `company_id` (o servidor grava o nome junto). Empresa nova vai como
// `empresaNova`: a fonte a cadastra antes de gravar a pessoa. Sem a chave, fica
// só o nome, como antes.
const vinculoDaEmpresa = (formulario, inicial, comEmpresas) => {
  if (!comEmpresas || formulario.empresaNova) return {};
  if (formulario.empresaId === inicial.empresaId) return {};
  return { company_id: formulario.empresaId };
};

const paisMudado = (formulario, inicial) =>
  formulario.pais === inicial.pais
    ? {}
    : {
        country_code: formulario.pais,
        country: nomeGravadoDoPais(formulario.pais),
      };

// O pedido que a fonte grava (fonte/gravarPessoa.js): `contato` no formato do
// contato no servidor e, à parte, o que não cabe nele: a empresa nova, a foto e
// os campos personalizados que saem. `inicial` é o formulário de quando a
// gaveta abriu.
export const pedidoParaSalvar = (
  formulario,
  inicial = formulario,
  { comEmpresas = false } = {}
) => {
  const atributos = atributosMudados(
    {
      [CHAVE_DO_CPF]: cpfComoAtributo(formulario.cpf),
      ...formulario.atributos,
    },
    { [CHAVE_DO_CPF]: cpfComoAtributo(inicial.cpf), ...inicial.atributos }
  );
  return {
    contato: {
      name: formulario.nome.trim(),
      phone_number: formulario.telefone || null,
      email: formulario.email.trim() || null,
      ...vinculoDaEmpresa(formulario, inicial, comEmpresas),
      additional_attributes: {
        city: formulario.cidade.trim(),
        company_name: formulario.empresa.trim(),
        ...comVaziosExplicitos(
          { description: formulario.sobre.trim() },
          { description: inicial.sobre }
        ),
        ...paisMudado(formulario, inicial),
        // O servidor troca `social_profiles` inteiro: o que a gaveta não mostra
        // tem de ir junto, senão some.
        social_profiles: {
          ...formulario.outrasRedes,
          ...comVaziosExplicitos(formulario.redes, inicial.redes),
        },
      },
      custom_attributes: atributos.gravar,
    },
    empresaNova:
      comEmpresas && formulario.empresaNova ? formulario.empresa.trim() : null,
    foto: formulario.foto,
    apagar: atributos.apagar,
  };
};

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
