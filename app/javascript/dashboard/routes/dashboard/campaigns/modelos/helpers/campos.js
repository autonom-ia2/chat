import { useI18n } from 'vue-i18n';
import { CAMPOS } from '../constants';

// Os campos de um modelo têm três origens:
// - os da tela ("nome_cliente", "data"…), em MODELOS_WHATSAPP.CAMPOS;
// - chaves do catálogo único (#1331), quando o modelo foi feito em outro lugar
//   do sistema ("horario.data_hora", nos avisos do agendamento), em
//   MODELOS_WHATSAPP.CATALOGO;
// - variáveis sem nome de modelos feitos fora do Chat2You ("variavel_2").
// Dois campos da tela têm chave no catálogo: é por ela que a campanha liga o
// valor sozinha (cliente.primeiro_nome, minha_empresa.nome).
export const CAMPO_NO_CATALOGO = {
  nome_cliente: 'cliente.primeiro_nome',
  nome_empresa: 'minha_empresa.nome',
};

const CATALOGO_NA_TELA = Object.fromEntries(
  Object.entries(CAMPO_NO_CATALOGO).map(([campo, chave]) => [chave, campo])
);

// Chaves do catálogo que a tela sabe nomear (as que um Público preenche e as do
// agendamento, que aparecem nos modelos do sistema).
export const CHAVES_DO_CATALOGO = [
  'cliente.nome',
  'cliente.primeiro_nome',
  'cliente.telefone',
  'cliente.email',
  'cliente.cliente_desde',
  'empresa_cliente.nome',
  'empresa_cliente.cnpj',
  'minha_empresa.nome',
  'minha_empresa.endereco',
  'minha_empresa.telefone',
  'minha_empresa.site',
  'horario.data_hora',
  'horario.data',
  'horario.hora',
  'horario.link_gestao',
  'negocio.titulo',
  'negocio.valor',
  'atendente.nome',
];

const VARIAVEL = 'variavel_';
const PUBLICO = 'publico.';

// O que a campanha oferece para ligar uma variável a um campo do catálogo: só o
// que um Público preenche (TemplateFields::Catalog.in_audience?).
export const CAMPOS_DO_PUBLICO = CHAVES_DO_CATALOGO.filter(chave =>
  ['cliente', 'empresa_cliente', 'minha_empresa'].includes(chave.split('.')[0])
);

// Chave do catálogo que um Público não preenche (horario.*, negocio.*): numa
// campanha ela não tem de onde vir para cada cliente.
export const semFonteNaCampanha = campo =>
  CHAVES_DO_CATALOGO.includes(campo) && !CAMPOS_DO_PUBLICO.includes(campo);

export const campoDaVariavel = numero => `${VARIAVEL}${numero}`;

// O campo da tela para o que o perfil do modelo guardou na variável.
export const campoDoPerfil = (valor, numero) => {
  if (CATALOGO_NA_TELA[valor]) return CATALOGO_NA_TELA[valor];
  const conhecido =
    CAMPOS.includes(valor) ||
    CHAVES_DO_CATALOGO.includes(valor) ||
    String(valor || '').startsWith(PUBLICO);
  if (conhecido) {
    return valor;
  }
  return campoDaVariavel(numero);
};

// O que o perfil guarda para um campo da tela: a chave do catálogo quando há,
// senão a própria etiqueta ("data"), que a campanha liga a uma coluna ou texto.
// Variável sem nome não é guardada.
export const campoParaPerfil = campo => {
  if (campo.startsWith(VARIAVEL)) return null;
  return CAMPO_NO_CATALOGO[campo] || campo;
};

// A ligação que a campanha faz sozinha, pelo catálogo (null: a pessoa escolhe).
export const ligacaoDoCatalogo = campo => {
  const chave = CAMPO_NO_CATALOGO[campo] || campo;
  return CAMPOS_DO_PUBLICO.includes(chave)
    ? { source: 'field', value: chave, suggested: true }
    : null;
};

export const rotuloDoCampo = (t, campo) => {
  if (CAMPOS.includes(campo))
    return t(`MODELOS_WHATSAPP.CAMPOS.${campo}.ROTULO`);
  if (campo.startsWith(VARIAVEL)) {
    return t('MODELOS_WHATSAPP.CAMPO_SEM_NOME', {
      n: campo.slice(VARIAVEL.length),
    });
  }
  if (CHAVES_DO_CATALOGO.includes(campo)) {
    return t(`MODELOS_WHATSAPP.CATALOGO_DE_CAMPOS.${campo}`);
  }
  // Coluna da planilha do Público: o próprio cabeçalho.
  if (campo.startsWith(PUBLICO)) return campo.slice(PUBLICO.length);
  return campo;
};

export const exemploDoCampo = (t, campo) =>
  CAMPOS.includes(campo) ? t(`MODELOS_WHATSAPP.CAMPOS.${campo}.EXEMPLO`) : '';

export function useRotuloDoCampo() {
  const { t } = useI18n();
  return campo => rotuloDoCampo(t, campo);
}
