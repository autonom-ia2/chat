import { config } from '@vue/test-utils';

// O i18n global dos specs não tem mensagens (vitest.setup.js), e o I18nT sem mensagem não desenha os
// slots. Para testar o {acao} da nota da gaveta Nome / Foto e nome, só a NOTA ganha um texto; as
// outras chaves seguem aparecendo como chave.
const i18nGlobal = () => config.global.plugins[0].global;

export const comNotaDaGaveta = () =>
  i18nGlobal().setLocaleMessage('en', {
    AGENTS: { JORNADA: { PAGINA: { FOTO: { NOTA: 'Nota {acao}.' } } } },
  });

export const semMensagens = () => i18nGlobal().setLocaleMessage('en', {});
