import { useI18n } from 'vue-i18n';
import { useLocale } from 'shared/composables/useLocale';
import { formatarDinheiro } from './numerosTextos';

// Dinheiro e texto da tela de Números (#1871): `traduzir` recebe o que as
// funções de numerosTextos devolvem e formata em moeda os parâmetros listados.
export function useNumerosFormato(moeda = 'BRL') {
  const { t } = useI18n();
  const { resolvedLocale } = useLocale();

  const locale = () => resolvedLocale.value;
  const dinheiro = valor =>
    formatarDinheiro(valor, { locale: locale(), moeda });

  const traduzir = (texto, emDinheiro = []) => {
    if (!texto) return '';
    const params = { ...(texto.params || {}) };
    emDinheiro.forEach(chave => {
      if (typeof params[chave] === 'number')
        params[chave] = dinheiro(params[chave]);
    });
    return texto.plural === undefined
      ? t(texto.key, params)
      : t(texto.key, params, texto.plural);
  };

  return { t, dinheiro, traduzir, locale };
}
