// #3078 — "Apagar" das empresas marcadas na lista. Não há rota de apagar várias
// empresas: cada uma vai pelo DELETE companies/:id que a ficha antiga usa
// (Companies::DeleteJob tira as pessoas dela e apaga a empresa), uma depois da
// outra, no mesmo transporte em fatias das ações em grupo (emFatias.js), com o
// mesmo formato de resposta: { apagadas, deFora, faltam, erro }.
//  - a empresa que já não existe (404) fica de fora com o motivo, e as outras
//    seguem;
//  - qualquer outra falha para ali, como nas outras ações em grupo: o que
//    faltou continua marcado para tentar de novo. A que esta aba já apagou
//    (empresasApagadas.js) não é pedida outra vez.
import CompanyAPI from 'dashboard/api/companies';
import { emFatias } from './emFatias';
import { foiApagada, lembrarApagada } from './empresasApagadas';

const NAO_ACHEI = 404;

const apagarUma = async empresa => {
  if (foiApagada(empresa.id)) return null;
  try {
    await CompanyAPI.delete(empresa.id);
    lembrarApagada(empresa.id);
    return null;
  } catch (falha) {
    if (falha?.response?.status !== NAO_ACHEI) throw falha;
    return { id: empresa.id, nome: empresa.name, motivo: 'nao_existe_mais' };
  }
};

// Uma depois da outra: a próxima só vai quando a anterior voltou.
const apagarAFatia = fatia =>
  fatia.reduce(
    (cadeia, empresa) =>
      cadeia.then(async deFora => {
        const fora = await apagarUma(empresa);
        return fora ? [...deFora, fora] : deFora;
      }),
    Promise.resolve([])
  );

export const apagarEmpresas = lote =>
  emFatias({
    ...lote,
    contagem: 'apagadas',
    mandar: async fatia => {
      const deFora = await apagarAFatia(fatia);
      return { feitas: fatia.length - deFora.length, deFora };
    },
  });
