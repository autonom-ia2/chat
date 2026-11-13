// #2898 — os ajustes e os resultados das renovações lidos do servidor
// (dashboard/api/relacionamentosSeguros.js), no formato que as telas usam. As
// recusas ganham os mesmos nomes da carteira (fonte/carteiraFonteReal.js): 422
// é `RECUSADO`, com o código que o servidor mandou (`funil_desconhecido`,
// `etapa_de_outro_funil`, `dias_invalidos`).
//
// O que a tela espera do servidor em `GET seguros/renovacoes`:
//   ajustes:     { funilId, etapaId, dias, mensagens } (funil e etapa nulos
//                enquanto a conta não escolheu, ou se o funil foi apagado);
//   funis:       [{ id, nome, etapas: [{ id, nome }] }];
//   vencimentos: em quantos dias termina cada seguro que ainda vale;
//   semPermissao: quem olha não pode mudar os ajustes.
// O que mais vier na resposta (o que é da cotação, de outra entrega) passa
// direto e a tela não lê.
import SegurosAPI from 'dashboard/api/relacionamentosSeguros';
import { noServidor } from './carteiraFonteReal';

// Só as escolhas desta tela: o que o servidor guardar a mais não entra na
// conta do "mudou".
const ajustesDaTela = ({
  funilId = null,
  etapaId = null,
  dias,
  mensagens,
}) => ({
  funilId,
  etapaId,
  dias,
  mensagens,
});

export const renovacoesFonteReal = () => ({
  usaDemo: false,
  async ajustes() {
    const dados = await noServidor(() => SegurosAPI.renovacoes());
    return { ...dados, ajustes: ajustesDaTela(dados.ajustes) };
  },
  salvar: async ajustes =>
    ajustesDaTela(
      await noServidor(() =>
        SegurosAPI.salvarRenovacoes(ajustesDaTela(ajustes))
      )
    ),
  resultados: () => noServidor(() => SegurosAPI.resultados()),
});
