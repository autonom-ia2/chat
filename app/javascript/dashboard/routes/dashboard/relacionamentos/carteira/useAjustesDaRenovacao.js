// #2898 — o estado de "Ajustar renovações": o que a conta escolheu, o rascunho
// que a pessoa está mexendo e o salvar. Fala só com a fonte
// (fonte/renovacoesFonte.js); quem desenha é a página. `salvar` devolve `true`
// se guardou; quando o servidor recusa com um código (carteira/recusas.js), ele
// fica em `recusa`, para a página escolher a frase.
// `funilParou` ('' | ARQUIVADO | APAGADO, carteira/funilDasRenovacoes.js): o
// funil guardado deixou de servir. O rascunho começa sem funil, e guardar outro
// tira o aviso.
// #2901 (E8) — com a cotação da renovação ligada (`cotacaoLiberada`), a tela
// lê também o consumo de cotações do mês (`consumo`, ou null enquanto não
// chegou ou se não deu para ler: é só leitura, e o resto da tela não depende
// dele). Se o robô cotava e a conta perdeu o Agente de Cotação ou o WhatsApp
// oficial, o rascunho começa em "Ninguém", que é o que a tela consegue mostrar.
import { computed, ref } from 'vue';
import { useEstadoDaFicha } from '../ficha/useEstadoDaFicha';
import { ajustesMudaram, semOFunil } from './ajustesDaRenovacao';
import {
  QUEM_COTA,
  caixaEscolhida,
  roboCota,
  roboPodeCotar,
  temEscolhasDaCotacao,
} from './cotacaoDaRenovacao';
import { codigoDaRecusa } from './recusas';

// O WhatsApp guardado que saiu da conta (ou deixou de ser oficial) também sai
// do rascunho: a pessoa escolhe outro.
const cotacaoDoRascunho = (ajustes, conta) => {
  if (!temEscolhasDaCotacao(ajustes)) return { ...ajustes };
  const caixaId = caixaEscolhida(conta.caixas, ajustes.caixaId)
    ? ajustes.caixaId
    : null;
  const quemCota =
    roboCota(ajustes) && !roboPodeCotar(conta)
      ? QUEM_COTA.NINGUEM
      : ajustes.quemCota;
  return { ...ajustes, quemCota, caixaId };
};
const rascunhoDe = (ajustes, conta) =>
  cotacaoDoRascunho(conta.funilParou ? semOFunil(ajustes) : ajustes, conta);

export const useAjustesDaRenovacao = fonte => {
  const { estado, carregar } = useEstadoDaFicha();
  // O que a tela precisa além das escolhas: os funis, os vencimentos, o exemplo.
  const conta = ref(null);
  const salvos = ref(null);
  const rascunho = ref(null);
  const salvando = ref(false);
  const recusa = ref('');
  const consumo = ref(null);

  const lerConsumo = async () => {
    try {
      consumo.value = await fonte.cotacoes();
    } catch {
      consumo.value = null;
    }
  };

  const buscar = async aindaVale => {
    const { ajustes, ...resto } = await fonte.ajustes();
    if (!aindaVale()) return false;
    conta.value = resto;
    salvos.value = ajustes;
    rascunho.value = rascunhoDe(ajustes, resto);
    if (resto.cotacaoLiberada && fonte.cotacoes) lerConsumo();
    return true;
  };

  const salvar = async () => {
    salvando.value = true;
    recusa.value = '';
    try {
      salvos.value = await fonte.salvar(rascunho.value);
      rascunho.value = { ...salvos.value };
      // Só se guarda com um funil que serve: o que tinha parado ficou para trás.
      conta.value = { ...conta.value, funilParou: '' };
      return true;
    } catch (falha) {
      recusa.value = codigoDaRecusa(falha);
      return false;
    } finally {
      salvando.value = false;
    }
  };

  return {
    estado,
    conta,
    rascunho,
    salvando,
    recusa,
    consumo,
    // A conta já tinha escolhido onde ficam as renovações antes de abrir a tela.
    jaEscolheu: computed(() => Boolean(salvos.value?.funilId)),
    funilParou: computed(() => conta.value?.funilParou || ''),
    mudou: computed(() => ajustesMudaram(salvos.value, rascunho.value)),
    carregar: () => carregar(buscar),
    salvar,
  };
};
