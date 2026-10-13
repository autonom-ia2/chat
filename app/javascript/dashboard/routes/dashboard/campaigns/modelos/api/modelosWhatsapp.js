// Camada de dados da tela "Modelos de mensagem do WhatsApp" e da ponte com a
// campanha (ponte/useModelosNaCampanha.js). Fala com a API de Modelos (#1330) e
// com os endpoints da tela (#1332) pelo adaptador HTTP; o resto da tela só
// conhece este contrato.
import adaptador from './adaptadorHttp';

// Contrato (o que cada função devolve, já no formato da tela). Ids no formato
// real: `id` do modelo é o id da Meta (texto com um número longo) e `id` do
// número é o inbox_id (número), para `?modelo=&caixa=` valer igual no backend.
//
// listarNumeros() → [Numero]  (só os conectados)
// listarCaixasDaCampanha() → [Numero]  (todas as caixas do WhatsApp oficial,
//   inclusive as que precisam reconectar)
//   Numero = { id: inbox_id, nome, telefone, conta: { id, nome },
//              situacao: 'conectada' | 'reconectar' }
//   Um modelo é da conta do WhatsApp (WABA) e vale para todos os números dela;
//   `conta.id` é o id da primeira caixa da conta (a tela nunca vê o id da WABA).
// listarModelos({ atualizar }) → [Modelo]  (`atualizar`: pede a lista nova à Meta)
//   com `naoLeu` (nomes das contas do WhatsApp que não responderam) e `naoAtualizou`.
// obterModelo(id) → Modelo
// ondeEstaEmUso(id) → [{ tipo: 'campanha' | 'agendamento' | 'crm'
//   | 'oculto', nome, data? (ISO), agendado, rota: { name, query? } | null }]
//   Tudo ali ainda vai sair: enquanto houver um, apagar e alterar ficam
//   bloqueados. `oculto`: em uso onde a pessoa não tem acesso (sem nome).
// listarCampanhasParadas() → [{ id, pausaId, nome, modeloId, modeloNome,
//   motivo: 'modelo_pausado' | 'modelo_recusado' | 'modelo_em_analise' |
//   'modelo_mudou' | 'tipo_mudou' | 'modelo_apagado' | 'formato_nao_vai' |
//   'nao_conferido' | 'outro' }]  (conferência do modelo no disparo, #1329)
// retomarCampanha(pausaId) → a pausa fechada (a campanha confere o modelo de novo)
// custoPorEnvio(tipo) → { valor, moeda } | null  (tabela WHATSAPP_MESSAGE_PRICES)
// obterFranquia() → { limite, numeros: [{ id, nome, usadas }] } | null
// criarModelo(rascunho, { textos }) → [Modelo]  (um por conta do WhatsApp); se uma
//   conta falha depois de outra criar, a lista vem com `falha` e `contasSemPedido`.
// alterarModelo(id, rascunho, { textos }) → Modelo (volta para 'em_analise')
// apagarModelo(id) → { nomeBloqueadoAte }  (data ISO, 30 dias depois)
// subirArquivoDaCampanha(caixa, arquivo) → { referencia, nome }  (foto, vídeo ou
//   documento do topo ou de um cartão, escolhido na campanha, #1334/#1465)
//   Erros da API chegam como ErroDaApi { codigo, mensagem (já traduzida), status }.
// obterCatalogo() → null e listarFormularios() → []: ainda sem backend.
// criarComIA({ objetivo, tom, tipo?, exemplo }) → { status, pergunta,
//   sugestoes, opcoes: [{ id, nome, tipo, motivo, conteudo }] }
// melhorarComIA({ conteudo, pedido, tipo, recusa? }) → { status, pergunta,
//   sugestoes, texto (pedaços) | null, tipo, oQueMudou, motivo,
//   continuaDivulgacao }  (#1333; opções já conferidas pela regra estrutural)
//
// Modelo = {
//   id, nome, nomeNoWhatsapp, objetivo, sistema, idioma,
//   situacao: 'pronto' | 'em_analise' | 'recusado' | 'pausado',
//   tipo: 'aviso' | 'divulgacao' | 'codigo', tipoMudouPeloWhatsapp,
//   conta, caixa (a caixa que fala com a Meta), numeros: [inbox_id],
//   conteudo: { formato, topo, texto, exemplos, rodape, botoes,
//     cartoes?, oferta?, catalogo?, codigo?, formulario? },
//   campos: { '1': campo }, template (o modelo como a Meta devolve),
//   cartoesGuardados: [{ nome } | null]  (arquivo aprovado de cada cartão do
//     carrossel, guardado no Chat2You; a campanha usa o mesmo, #1334),
//   topoGuardado: { nome } | null  (arquivo do topo guardado, #1465),
//   recusa: { codigo } | null, pausa: { desde | null } | null,
//   sinal: 'bom' | 'atencao' | 'ruim' | 'sem_nota'  (qualidade dada pelo WhatsApp),
//   saude: { dias, enviadas, entregues, lidas, responderam,
//     custo: { total, porResposta | null, moeda } | null,
//     mediaDeRespostas: % | null (só com 3 modelos ou mais com envios) }
//     | undefined  (últimos 30 dias, só o que saiu pelo Chat2You, #1338),
//   enviosNoMes | null, enviadoEm | null,
//   edicoes: { restantesNoMes | null, liberadaEm | null },
// }
// null: a Meta não informa e a tela não inventa.
export default adaptador;
