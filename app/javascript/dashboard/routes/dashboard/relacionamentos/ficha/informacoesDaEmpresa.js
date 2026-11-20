// #3078 — a empresa na ficha nova, com tudo o que a ficha antiga de Empresas
// tinha: as linhas de Informações, o formulário da gaveta (nova empresa e
// "Alterar informações") e o pedido que volta dele para a fonte. Funções puras,
// sem mutar o que recebem. O CNPJ e a cidade moram em `additional_attributes`
// (o servidor junta com o que já havia); a descrição é a coluna `description`.
import { formatarCnpj, formatarMes, quandoRelativo } from './formatos';
import { soDigitos } from '../fonte/texto';
import { linkCompleto, temValor } from './atributos';
import { atributosMudados, comLinksCompletos } from './informacoes';

const preenchido = valor => String(valor ?? '').trim() !== '';
const limpo = valor => (preenchido(valor) ? String(valor).trim() : '');

// As linhas de Informações: cidade, "O que a empresa faz" (só preenchida), quantas
// pessoas e clientes, desde quando está cadastrada, a última conversa e os
// campos personalizados que aparecem na ficha (`campos`, de camposDaEmpresa).
// CNPJ e site ficam no cabeçalho.
export const linhasDaEmpresa = (
  empresa,
  { campos = [], idioma = 'pt-BR', agora = Date.now() } = {}
) => {
  const fixas = [
    { chave: 'cidade', valor: limpo(empresa.city) },
    ...(preenchido(empresa.description)
      ? [{ chave: 'sobre', valor: limpo(empresa.description), longo: true }]
      : []),
    { chave: 'pessoas', valor: String(empresa.contacts_count ?? 0) },
    { chave: 'clientes', valor: String(empresa.customers_count ?? 0) },
    {
      chave: 'desde',
      valor: empresa.created_at ? formatarMes(empresa.created_at, idioma) : '',
    },
    {
      chave: 'ultima_conversa',
      valor: empresa.last_activity_at
        ? quandoRelativo(empresa.last_activity_at, agora, idioma)
        : '',
    },
  ];
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

// O formulário da gaveta. Empresa nova chega como `{}`. `foto` nasce vazia: é a
// troca pedida ({ arquivo, previa }) ou { tirar: true }.
export const formularioDaEmpresa = (empresa = {}) => ({
  nome: empresa.name ?? '',
  cnpj: formatarCnpj(empresa.cnpj ?? ''),
  site: empresa.domain ?? '',
  cidade: empresa.city ?? '',
  sobre: empresa.description ?? '',
  foto: null,
  atributos: { ...(empresa.custom_attributes ?? {}) },
});

// O site como o servidor guarda: só o nome do site, sem "https://" nem barra
// no fim ("https://padaria.com.br/" vira "padaria.com.br"). Quem confere é o
// parser de URL do navegador (atributos.js#linkCompleto). O que nem assim é um
// endereço de site volta como foi escrito: a gaveta já avisou antes.
export const siteParaGravar = texto => {
  const escrito = limpo(texto);
  if (!escrito) return '';
  const link = linkCompleto(escrito);
  return link ? new URL(link).hostname : escrito;
};

// O pedido que a fonte grava (fonte/gravarEmpresa.js): `empresa` no formato do
// servidor e, à parte, a foto e os campos personalizados que saem (`apagar`).
// Site, CNPJ, cidade e descrição apagados vão como `null`: no banco o site é
// único por conta quando não é nulo (o CNPJ não é), e site vazio em duas
// empresas bateria um no outro. `inicial` é o formulário de quando a gaveta
// abriu; `tipos` ({ chave: tipo }) diz quais campos são link.
export const pedidoDaEmpresa = (
  formulario,
  inicial = formulario,
  { tipos = {} } = {}
) => {
  const atributos = atributosMudados(
    comLinksCompletos(formulario.atributos, tipos),
    comLinksCompletos(inicial.atributos, tipos)
  );
  return {
    empresa: {
      name: limpo(formulario.nome),
      domain: siteParaGravar(formulario.site) || null,
      description: limpo(formulario.sobre) || null,
      additional_attributes: {
        cnpj: soDigitos(formulario.cnpj) || null,
        city: limpo(formulario.cidade) || null,
      },
      custom_attributes: atributos.gravar,
    },
    foto: formulario.foto,
    apagar: atributos.apagar,
  };
};
