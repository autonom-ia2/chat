import { idiomaDoNavegador } from './pagina';

// #1429 F3 — "2026-10-21" é uma data sem hora: montada no fuso de quem vê, para não virar o dia anterior.
export const dataDaBase = (publicadaEm, locale) => {
  const [ano, mes, dia] = (publicadaEm || '').split('-').map(Number);
  if (!ano) return '';
  return new Date(ano, mes - 1, dia).toLocaleDateString(
    idiomaDoNavegador(locale),
    { day: '2-digit', month: '2-digit' }
  );
};

// O nome do tipo de seguro ('seguros/saude_beneficios' → "Saúde e benefícios"), sempre pelo i18n.
export const rotuloDoTipo = (segmento, t) => {
  const tipo = (segmento || '').split('/').pop();
  return tipo
    ? t(`AGENTS.JORNADA.PAGINA.BASE.TIPOS.${tipo.toUpperCase()}`)
    : '';
};

// "Corretora · de 21/10", ou só "Corretora" quando a versão não tem data registrada.
export const rotuloDaBase = (base, t, locale) => {
  const tipo = rotuloDoTipo(base?.segmento, t);
  const data = dataDaBase(base?.data, locale);
  return data ? t('AGENTS.JORNADA.PAGINA.BASE.ROTULO', { tipo, data }) : tipo;
};
