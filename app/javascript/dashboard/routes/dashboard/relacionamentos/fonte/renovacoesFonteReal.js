// #2898 — os ajustes e os resultados das renovações lidos do servidor
// (dashboard/api/relacionamentosSeguros.js), no formato que as telas usam. As
// recusas ganham os mesmos nomes da carteira (fonte/carteiraFonteReal.js): 422
// é `RECUSADO`, com o código que o servidor mandou (`funil_desconhecido`,
// `etapa_de_outro_funil`, `dias_invalidos`).
//
// O que a tela espera do servidor em `GET seguros/renovacoes`:
//   ajustes:     { funilId, etapaId, dias, mensagens } (funil e etapa nulos
//                enquanto a escolha não vale: ninguém escolheu, o funil foi
//                arquivado, ou o funil ou a etapa foram apagados; `mensagens`
//                só quando a conta tem as mensagens de renovação);
//   escolha:     como está a escolha do funil (`feita`, `nunca_feita`,
//                `funil_arquivado`, `sumiu`);
//   funis:       [{ id, nome, etapas: [{ id, nome }] }];
//   vencimentos: em quantos dias termina cada seguro que ainda vale;
//   semPermissao: quem olha não pode mudar os ajustes.
// A fonte soma `funilParou` ('' | ARQUIVADO | APAGADO): o funil escolhido
// deixou de servir. Quem lê o sinal do servidor é carteira/funilDasRenovacoes.js.
// O que mais vier na resposta (o que é da cotação, de outra entrega) passa
// direto e a tela não lê.
import SegurosAPI from 'dashboard/api/relacionamentosSeguros';
import { temMensagens } from '../carteira/ajustesDaRenovacao';
import { funilParou } from '../carteira/funilDasRenovacoes';
import { noServidor } from './carteiraFonteReal';

// Só as escolhas desta tela: o que o servidor guardar a mais não entra na
// conta do "mudou". A escolha das mensagens só entra quando o servidor a manda:
// sem ela, a tela não tem o cartão e não manda `mensagens` de volta (o servidor
// só muda o que veio).
const ondeEQuando = ({ funilId = null, etapaId = null, dias }) => ({
  funilId,
  etapaId,
  dias,
});
const ajustesDaTela = ajustes =>
  temMensagens(ajustes)
    ? { ...ondeEQuando(ajustes), mensagens: ajustes.mensagens }
    : ondeEQuando(ajustes);

export const renovacoesFonteReal = () => ({
  usaDemo: false,
  async ajustes() {
    const dados = await noServidor(() => SegurosAPI.renovacoes());
    return {
      ...dados,
      ajustes: ajustesDaTela(dados.ajustes),
      funilParou: funilParou(dados),
    };
  },
  // O que volta é o que ficou guardado, com as mesmas escolhas que foram
  // mandadas: quem não tinha o cartão de mensagens continua sem ele.
  async salvar(ajustes) {
    const mandados = ajustesDaTela(ajustes);
    const guardados = await noServidor(() =>
      SegurosAPI.salvarRenovacoes(mandados)
    );
    return temMensagens(mandados)
      ? ajustesDaTela(guardados)
      : ondeEQuando(guardados);
  },
  resultados: () => noServidor(() => SegurosAPI.resultados()),
});
