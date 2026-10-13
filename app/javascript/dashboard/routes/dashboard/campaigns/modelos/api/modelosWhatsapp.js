// Camada de dados da tela "Modelos de mensagem do WhatsApp" e da ponte com a
// campanha (ponte/useModelosNaCampanha.js).
//
// Nesta fase (só front) os dados vêm de um adaptador falso em memória. Quando o
// endpoint real existir, troque a linha abaixo por um adaptador HTTP com as
// mesmas funções e o mesmo formato — o resto da tela não muda.
import adaptador from './adaptadorEmMemoria';

// Contrato (o que cada função devolve, já no formato da tela). Ids no formato
// real: `id` do modelo é o id da Meta (texto com um número longo) e `id` do
// número é o inbox_id (número), para `?modelo=&caixa=` valer igual no backend.
//
// listarNumeros() → [Numero]  (só os conectados)
// listarCaixasDaCampanha() → [Numero]  (todas as caixas do WhatsApp oficial,
//   inclusive as que precisam reconectar)
//   Numero = { id: inbox_id, nome, telefone, conta: { id, nome },
//              situacao: 'conectada' | 'reconectar' }
//   Um modelo é da conta do WhatsApp (WABA) e vale para todos os números dela.
// listarModelos() → [Modelo]
// obterModelo(id) → Modelo
// ondeEstaEmUso(id) → [{ tipo: 'campanha' | 'agendamento' | 'crm' | 'anuncios'
//   | 'satisfacao', nome, quando?, agendado, rota: { name, query? } }]
//   `agendado`: ainda vai sair; enquanto houver um, apagar fica bloqueado.
// listarCampanhasParadas() → [{ id, nome, modeloId, modeloNome,
//   motivo: 'modelo_pausado' | 'modelo_recusado' | 'modelo_mudou' | 'tipo_mudou' }]
//   Conferência do modelo no disparo: a campanha para em vez de falhar.
// custoPorEnvio(tipo) → { valor, moeda }
// criarModelo(rascunho) → [Modelo]  (um por conta do WhatsApp, 'em_analise')
// alterarModelo(id, rascunho) → Modelo (volta para 'em_analise')
// apagarModelo(id) → { nomeBloqueadoAte }  (data ISO, 30 dias depois)
//   Recusa modelo do sistema e modelo com uso agendado.
// obterCatalogo() → { nome, produtos } | null  (catálogo conectado à conta)
// listarFormularios() → [{ id, nome }]  (formulários que já existem no WhatsApp)
// criarComIA({ objetivo, tom, numeros }) → { opcoes: [{ id, nome, tipo, conteudo }] }
//   2 ou 3 opções prontas; `tom`: 'curto' | 'simpatico' | 'formal'.
// melhorarComIA({ texto, pedido, objetivo, tipo }) → { texto, exemplos, tipo,
//   continuaDivulgacao } — `pedido`: 'mais_curto' | 'mais_claro' |
//   'manter_aviso' | 'corrigir_recusa'. `continuaDivulgacao`: pediu aviso de
//   serviço, mas o conteúdo é divulgação (a tela mostra os dois custos).
//   As duas levam alguns segundos e podem falhar: a tela trata os dois casos.
//
// Modelo = {
//   id, nome, nomeNoWhatsapp, objetivo, biblioteca, sistema, idioma,
//   situacao: 'pronto' | 'em_analise' | 'recusado' | 'pausado',
//   tipo: 'aviso' | 'divulgacao' | 'codigo', tipoMudouPeloWhatsapp,
//   conta: id da conta do WhatsApp, numeros: [inbox_id],
//   conteudo: { formato, topo, texto, exemplos, rodape, botoes,
//     cartoes?, oferta?, catalogo?, codigo?, formulario? },
//   recusa: { codigo } | null, pausa: { desde } | null,
//   enviosNoMes, enviadoEm,
//   edicoes: { restantesNoMes, liberadaEm | null },
// }
export default adaptador;
