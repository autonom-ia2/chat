// #3078 — "Apagar" das empresas marcadas na lista. Não há rota de apagar várias
// empresas: cada uma vai pelo DELETE companies/:id que a ficha antiga usa, uma
// depois da outra, no mesmo transporte em fatias das ações em grupo
// (emFatias.js), com o mesmo formato de resposta: { apagadas, deFora, faltam,
// erro }, mais `naFila`.
//  - #3079 — o servidor apaga na hora a empresa pequena (200) e põe na fila a
//    que tem mais pessoas que um lote do Companies::DeleteJob (202). As da fila
//    contam como apagadas e voltam em `naFila` ({ id, nome }): a tela avisa que
//    elas saem da lista em alguns minutos;
//  - a empresa que já não existe (404) fica de fora com o motivo, e as outras
//    seguem;
//  - qualquer outra falha para ali, como nas outras ações em grupo: o que
//    faltou continua marcado para tentar de novo. O que a fatia já tinha
//    apagado antes da falha conta (a falha leva o `parcial` para emFatias).
import CompanyAPI from 'dashboard/api/companies';
import { emFatias } from './emFatias';

const NAO_ACHEI = 404;
const ACEITO = 202;

const apagarUma = async empresa => {
  try {
    const resposta = await CompanyAPI.delete(empresa.id);
    return { naFila: resposta?.status === ACEITO };
  } catch (falha) {
    if (falha?.response?.status !== NAO_ACHEI) throw falha;
    return {
      fora: { id: empresa.id, nome: empresa.name, motivo: 'nao_existe_mais' },
    };
  }
};

const NADA_NA_FATIA = Object.freeze({
  feitas: 0,
  deFora: [],
  tentadas: 0,
  naFila: [],
});

const somar = (feito, empresa, uma) => ({
  feitas: feito.feitas + (uma.fora ? 0 : 1),
  deFora: uma.fora ? [...feito.deFora, uma.fora] : feito.deFora,
  tentadas: feito.tentadas + 1,
  naFila: uma.naFila
    ? [...feito.naFila, { id: empresa.id, nome: empresa.name }]
    : feito.naFila,
});

// Uma depois da outra: a próxima só vai quando a anterior voltou. Se uma
// falha, a falha leva o que a fatia já fez (`parcial`).
const apagarAFatia = fatia =>
  fatia.reduce(
    (cadeia, empresa) =>
      cadeia.then(async feito => {
        try {
          return somar(feito, empresa, await apagarUma(empresa));
        } catch (falha) {
          throw Object.assign(falha, { parcial: feito });
        }
      }),
    Promise.resolve(NADA_NA_FATIA)
  );

export const apagarEmpresas = async lote => {
  let naFila = [];
  const feito = await emFatias({
    ...lote,
    contagem: 'apagadas',
    mandar: async fatia => {
      try {
        const daFatia = await apagarAFatia(fatia);
        naFila = [...naFila, ...daFatia.naFila];
        return daFatia;
      } catch (falha) {
        naFila = [...naFila, ...(falha.parcial?.naFila ?? [])];
        throw falha;
      }
    },
  });
  return { ...feito, naFila };
};
