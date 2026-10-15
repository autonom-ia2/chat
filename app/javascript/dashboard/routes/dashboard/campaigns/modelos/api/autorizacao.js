// Autorização do dono para o sistema criar modelos sozinho (#1586), pela API
// GET/POST whatsapp_template_consent. Preços, versão e textos do aviso vêm do
// servidor (Whatsapp::Templates::AvisoDeConsentimento): a tela mostra o mesmo
// texto que o registro grava.
//
// obterAutorizacao() → Autorizacao
// mudar({ acao: 'ligar' | 'desligar', marcas: ['utility', 'marketing'], versao }) → Autorizacao
//
// Autorizacao = {
//   servico: boolean, divulgacao: boolean,     (Aviso de serviço, Divulgação)
//   mudanca: Mudanca | null,                   (a do Aviso de serviço)
//   mudancaDivulgacao: Mudanca | null,
//   versao, vigenteDesde (AAAA-MM-DD),
//   precos: { servico: Preco, divulgacao: Preco },
//   textos: { ligar: { servico, divulgacao }, desligar: { servico, divulgacao } },
//   limites: { modelos, modelosVerificada, porHora },
// }
// Mudanca = { acao: 'ligou' | 'desligou', por, em (ISO) }; Preco = { valor, moeda }
import api from 'dashboard/api/whatsappTemplates';
import { ErroDaApi } from './adaptadorHttp';

export const MARCA = { servico: 'utility', divulgacao: 'marketing' };

const porMarca = (valores = {}, transformar = valor => valor) => ({
  servico: transformar(valores[MARCA.servico]),
  divulgacao: transformar(valores[MARCA.divulgacao]),
});

export const autorizacaoDaApi = payload => {
  const { aviso } = payload;
  return {
    servico: Boolean(payload[MARCA.servico]?.ativo),
    divulgacao: Boolean(payload[MARCA.divulgacao]?.ativo),
    mudanca: payload[MARCA.servico]?.mudanca || null,
    mudancaDivulgacao: payload[MARCA.divulgacao]?.mudanca || null,
    versao: aviso.versao,
    vigenteDesde: aviso.vigente_desde,
    precos: porMarca(aviso.precos, valor => ({
      valor: Number(valor),
      moeda: aviso.moeda,
    })),
    textos: {
      ligar: porMarca(aviso.textos.ligar),
      desligar: porMarca(aviso.textos.desligar),
    },
    limites: {
      modelos: aviso.limites.modelos,
      modelosVerificada: aviso.limites.modelos_verificada,
      porHora: aviso.limites.por_hora,
    },
  };
};

const chamar = async promessa => {
  try {
    const { data } = await promessa;
    return autorizacaoDaApi(data.payload);
  } catch (erro) {
    if (!erro?.response) throw erro;
    throw new ErroDaApi(erro);
  }
};

export default {
  obterAutorizacao: () => chamar(api.getConsent()),
  mudar: ({ acao, marcas, versao }) =>
    chamar(api.updateConsent({ acao, marcas, versaoAviso: versao })),
};
