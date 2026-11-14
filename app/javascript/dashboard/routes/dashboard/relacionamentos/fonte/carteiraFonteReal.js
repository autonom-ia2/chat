// #2897 — a carteira de seguros lida do servidor
// (dashboard/api/relacionamentosSeguros.js), no formato que as peças da tela
// usam. Duas traduções moram aqui, e só aqui:
//
//   1. datas. O servidor fala `comeca` e `termina` como "AAAA-MM-DD" (data sem
//      hora, na leitura e na escrita). As peças guardam a data em segundos, ao
//      meio-dia do relógio de quem lê: formatada, ela cai sempre no mesmo dia.
//      A ida e a volta usam o mesmo relógio (carteira/formatosDoSeguro.js), e
//      nenhuma passa por UTC. `selo` e `dias` vêm prontos, no dia da conta, e
//      seguem como vieram. O que é instante (quando chegou, quando foi
//      cancelado, cada passo da história) já vem em segundos;
//   2. recusas. 404 é `NAO_ACHEI` (o seguro não existe mais, é de outra conta ou
//      a conta não tem a carteira); 401 e 403 são `SEM_ACESSO` (quem olha não
//      pode ver ou editar a pessoa); 422 é `RECUSADO`, com o código que o
//      servidor mandou em `codigo` (carteira/recusas.js). 413 também é
//      `RECUSADO`, com o código `arquivo_grande`: o arquivo passou do limite do
//      servidor web e nem chegou à carteira, que responderia a mesma coisa. O
//      resto sobe como veio.
//
// O link do PDF vale um minuto: `pdf(id)` pede um novo a cada chamada e nada
// aqui o guarda.
import SegurosAPI from 'dashboard/api/relacionamentosSeguros';
import { doCampoDeData, paraCampoDeData } from '../carteira/formatosDoSeguro';
import { ARQUIVO_GRANDE, RECUSADO } from '../carteira/recusas';
import { NAO_ACHEI, SEM_ACESSO } from '../ficha/falhas';
import { preenchido } from '../lista/filtros';

// ---- datas -----------------------------------------------------------------

const CAMPOS_DE_DATA = ['comeca', 'termina'];
const ehData = campo => CAMPOS_DE_DATA.includes(campo);

const seguroDaTela = seguro => ({
  ...seguro,
  comeca: doCampoDeData(seguro.comeca),
  termina: doCampoDeData(seguro.termina),
});

const mudancaDaTela = mudanca =>
  ehData(mudanca.campo)
    ? {
        ...mudanca,
        antes: doCampoDeData(mudanca.antes),
        depois: doCampoDeData(mudanca.depois),
      }
    : mudanca;

const passoDaTela = passo => ({
  ...passo,
  mudancas: passo.mudancas?.map(mudancaDaTela) ?? null,
});

// O que a tela corrigiu, como o servidor lê: a data volta a ser "AAAA-MM-DD".
// Data apagada (`null`) segue `null`, que é como o servidor apaga o campo.
const correcaoDoServidor = dados =>
  Object.fromEntries(
    Object.entries(dados).map(([campo, valor]) => [
      campo,
      ehData(campo) && valor !== null ? paraCampoDeData(valor) : valor,
    ])
  );

// ---- recusas ---------------------------------------------------------------

const STATUS_RECUSADO = 422;
const STATUS_GRANDE_DEMAIS = 413;
const NOME_DO_STATUS = new Map([
  [404, NAO_ACHEI],
  [401, SEM_ACESSO],
  [403, SEM_ACESSO],
  [STATUS_RECUSADO, RECUSADO],
  [STATUS_GRANDE_DEMAIS, RECUSADO],
]);

const codigoDe = resposta => {
  if (resposta.status === STATUS_GRANDE_DEMAIS) return ARQUIVO_GRANDE;
  return resposta.status === STATUS_RECUSADO &&
    typeof resposta.data?.error === 'string'
    ? resposta.data.error
    : '';
};

const comNome = falha => {
  const resposta = falha?.response;
  const nome = NOME_DO_STATUS.get(resposta?.status);
  return nome
    ? Object.assign(new Error(falha.message, { cause: falha }), {
        name: nome,
        codigo: codigoDe(resposta),
      })
    : falha;
};

// `pedido()` é uma ida ao servidor: devolve o corpo da resposta. A fonte das
// renovações (fonte/renovacoesFonteReal.js) fala com o servidor por aqui: as
// recusas dela ganham os mesmos nomes.
export const noServidor = async pedido => {
  try {
    return (await pedido()).data;
  } catch (falha) {
    throw comNome(falha);
  }
};

const umSeguro = pedido => noServidor(pedido).then(seguroDaTela);
const variosSeguros = async pedido =>
  (await noServidor(pedido)).map(seguroDaTela);

// ---- o pedido da lista -----------------------------------------------------

// O que vai na URL: só o que está preenchido. "Quem cuida" (#2898) vai pelo id
// da pessoa.
const paramsDoPedido = ({ grupo, busca, ordem, pagina, filtros = {} }) =>
  Object.fromEntries(
    [
      ['grupo', grupo],
      ['busca', busca],
      ['ordem', ordem],
      ['pagina', pagina],
      ['filtros[tipo]', filtros.tipo],
      ['filtros[seguradora]', filtros.seguradora],
      ['filtros[cuida]', filtros.cuida],
    ].filter(([, valor]) => preenchido(valor))
  );

export const carteiraFonteReal = () => ({
  usaDemo: false,
  resumo: () => noServidor(() => SegurosAPI.resumo()),
  // `aba` vem de quem usa a lista (lista/useLista.js) e aqui não muda nada.
  contagens: (aba, { busca, filtros } = {}) =>
    noServidor(() => SegurosAPI.contagens(paramsDoPedido({ busca, filtros }))),
  async listar(pedido = {}) {
    const data = await noServidor(() =>
      SegurosAPI.lista(paramsDoPedido(pedido))
    );
    return {
      itens: data.itens.map(seguroDaTela),
      total: data.total,
      temMais: data.temMais,
    };
  },
  opcoesDeFiltro: () => noServidor(() => SegurosAPI.opcoesDeFiltro()),
  daPessoa: id => variosSeguros(() => SegurosAPI.daPessoa(id)),
  daEmpresa: id => variosSeguros(() => SegurosAPI.daEmpresa(id)),
  // A lista de pessoas: o selo de seguro de cada pessoa da página (`ids`). Vem
  // só quem tem seguro, com o selo e os dias prontos, no dia da conta.
  resumoPorPessoa: ids => noServidor(() => SegurosAPI.resumoPorPessoa(ids)),
  seguro: id => umSeguro(() => SegurosAPI.seguro(id)),
  historia: async id =>
    (await noServidor(() => SegurosAPI.historia(id))).map(passoDaTela),
  corrigir: (id, dados) =>
    umSeguro(() => SegurosAPI.corrigir(id, correcaoDoServidor(dados))),
  cancelar: id => umSeguro(() => SegurosAPI.cancelar(id)),
  voltarAAtivo: id => umSeguro(() => SegurosAPI.voltarAAtivo(id)),
  guardarPdf: (id, arquivo) =>
    umSeguro(() => SegurosAPI.guardarPdf(id, arquivo)),
  tirarPdf: id => umSeguro(() => SegurosAPI.tirarPdf(id)),
  // #2898 — como a renovação terminou. As três devolvem o seguro como ficou.
  renovou: id => umSeguro(() => SegurosAPI.renovou(id)),
  naoRenovou: (id, dados) => umSeguro(() => SegurosAPI.naoRenovou(id, dados)),
  desfazerDesfecho: id => umSeguro(() => SegurosAPI.desfazerDesfecho(id)),
  // A apólice nova do seguro `id`, escrita à mão: devolve o seguro NOVO.
  apoliceNova: (id, dados) =>
    umSeguro(() =>
      SegurosAPI.criar({ anteriorId: id, ...correcaoDoServidor(dados) })
    ),
  pdf: async id => (await noServidor(() => SegurosAPI.linkDoPdf(id))).url,
});
