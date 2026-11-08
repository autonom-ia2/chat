import { idiomaDoNavegador } from './pagina';

// #1429 F3 — "2026-10-21" é uma data sem hora: montada no fuso de quem vê, para não virar o dia anterior.
export const dataDaBase = (publicadaEm, locale) => {
  const [ano, mes, dia] = (publicadaEm || '').split('-').map(Number);
  if (!ano) return '';
  return new Date(ano, mes - 1, dia).toLocaleDateString(
    idiomaDoNavegador(locale),
    { day: '2-digit', month: '2-digit', year: 'numeric' }
  );
};

// Os tipos de conta de seguros com nome no i18n (Autonomia::Agents::Nicho::PERFIS). Tipo novo sem nome ainda: "Seguros".
const TIPOS = {
  corretora: 'CORRETORA',
  seguradora: 'SEGURADORA',
  insurtech: 'INSURTECH',
  saude_beneficios: 'SAUDE_BENEFICIOS',
};

// O nome do tipo de seguro ('seguros/saude_beneficios' → "Saúde e benefícios"), sempre pelo i18n.
export const rotuloDoTipo = (segmento, t) => {
  const tipo = (segmento || '').split('/').pop();
  if (!tipo) return '';
  return t(`AGENTS.JORNADA.PAGINA.BASE.TIPOS.${TIPOS[tipo] || 'OUTRO'}`);
};

// "Corretora · de 21/10/2026", ou só "Corretora" quando a versão não tem data registrada.
export const rotuloDaBase = (base, t, locale) => {
  const tipo = rotuloDoTipo(base?.segmento, t);
  const data = dataDaBase(base?.data, locale);
  return data ? t('AGENTS.JORNADA.PAGINA.BASE.ROTULO', { tipo, data }) : tipo;
};
