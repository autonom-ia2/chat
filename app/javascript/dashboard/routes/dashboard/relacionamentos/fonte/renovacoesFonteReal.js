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
// O que mais vier na resposta passa direto.
// #2901 (E8) — com a cotação da renovação ligada na conta, o servidor manda
// também `cotacaoLiberada`, `cotaSozinha` (a conta tem o Agente de Cotação),
// `agente` (o nome dele), `caixas` ([{ id, nome, liaLigada }]) e, em `ajustes`,
// as escolhas da cotação (`quemCota`, `quemEnvia`, `quemResponde`, `caixaId`).
// Elas entram no "mudou" e voltam no salvar; sem a chave, nada disso vem nem
// vai. `cotacoes()` é o consumo de cotações do mês (só contagens).
import SegurosAPI from 'dashboard/api/relacionamentosSeguros';
import { temMensagens } from '../carteira/ajustesDaRenovacao';
import { escolhasDaCotacao } from '../carteira/cotacaoDaRenovacao';
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
const ajustesDaTela = ajustes => ({
  ...ondeEQuando(ajustes),
  ...(temMensagens(ajustes) ? { mensagens: ajustes.mensagens } : {}),
  ...escolhasDaCotacao(ajustes),
});

// Do que ficou guardado, só as escolhas que foram mandadas.
const soAsMandadas = (mandados, guardados) =>
  Object.fromEntries(
    Object.entries(ajustesDaTela(guardados)).filter(
      ([chave]) => chave in mandados
    )
  );

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
  // mandadas: quem não tinha o cartão de mensagens (ou o da cotação) continua
  // sem ele.
  async salvar(ajustes) {
    const mandados = ajustesDaTela(ajustes);
    const guardados = await noServidor(() =>
      SegurosAPI.salvarRenovacoes(mandados)
    );
    return soAsMandadas(mandados, guardados);
  },
  resultados: () => noServidor(() => SegurosAPI.resultados()),
  cotacoes: () => noServidor(() => SegurosAPI.cotacoes()),
});
