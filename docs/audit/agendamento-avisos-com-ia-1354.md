# Agendamento: texto dos avisos escrito com IA na configuração (#1354)

Opção A da decisão do Rodrigo (12/10/2026, "A agora e B depois"): a IA escreve na configuração e o dono aprova. A
opção B (a IA escreve cada aviso na hora do envio) é a #1355. Sem migration.

## Decisões

- **Chaves do catálogo, sem sintaxe nova** (combinado com a sessão Modelos WhatsApp): o texto guarda
  `{{cliente.primeiro_nome}}`, `{{horario.data_hora}}`, `{{horario.link_gestao}}` e `{{minha_empresa.nome}}`
  (`TemplateFields::Catalog`). O envio preenche por `TemplateFields::Resolver.for_meeting(meeting, invite:)`; o
  `MeetingResolver` já resolvia dia/hora e link, sem extensão. Parser único: `Ai::Redacao::Chaves` (index/split, sem
  regex), reaproveitável pela Modelos.
- **Onde fica:** `metadata['notice_texts']` da página. Não em `notice_templates`, que é o modelo aprovado de cada aviso
  (formato fechado, lido pelo `Notices::Route` para decidir o envio).
- **Validação** (salvar, resposta da IA e de novo no envio, `Notices::CustomText`): só as 4 chaves; link e dia/hora
  obrigatórios; até 500 caracteres; sem chave malformada; sem a linha de parar (é do sistema). Texto salvo que não
  passa no envio, ou sem link ou dia/hora para preencher: vai o padrão e fica no log, sem o texto.
- **Linha de parar:** sempre acrescentada pelo sistema, nos dois caminhos (texto próprio e padrão).
- **`booked_by_team`:** a reunião marcada pela equipe usa o padrão, que diz quem marcou. O texto próprio não tem campo
  para isso, e costuma ser escrito como se o próprio cliente tivesse marcado.
- **Sem primeiro nome:** o campo sai junto com a vírgula ou o espaço antes dele ("Oi, !" vira "Oi!").
- **Modelos da Meta e canal API:** `template_values` e `appendix` não mudam.

## Redator compartilhado (`Ai::Redacao::Escrever`)

- Compartilhado com a fase E da Modelos WhatsApp (#1333, "Criar/Melhorar com IA"). O agendamento é o primeiro consumidor.
- Registro de canais (`Ai::Redacao::Canais`): `whatsapp_texto` implementado; `whatsapp_modelo` e `email` respondem
  "ainda não suportado", sem chamar a IA. Cada canal tem `prompt` (`prompts/comum.md` + `prompts/<canal>.md`),
  `schema` (núcleo comum + campos do canal), `validar` e `normalizar`.
- `comum.md` é o bloco calibrado pela Modelos (v3 da bateria dela). `whatsapp_texto.md` é deste PR.
- Pela chave de IA da conta (`Crm::Ai::CredentialResolver` + `ResponsesClient`), `feature: 'aviso_redacao'` (Gestão IA →
  Agendamento), schema estrito, 11 s, sem retry, cache por feature. Modelo padrão: o luna (`MODEL_FOLLOWUP`), esforço baixo;
  `modelo:` aceito como parâmetro.
- O código descarta a opção que quebra regra (chave fora da lista, obrigatória ausente, campo no começo ou no fim,
  tamanho, malformada). A ação do painel ainda passa cada opção pela validação do aviso.
- Diferença em relação ao combinado: "campo no fim" vale para o que a IA escreve, mas não para o texto que o dono
  salva. O texto padrão de hoje termina no link, e a linha de parar sempre vem depois.
- O Kit da marca ainda não tem "jeito de falar": `tom.kit` vai nulo e vale a escolha da pessoa (Curto, Simpático ou Formal).
- Entrada para a IA: título da página, duração, tipos de local, nome do negócio (`minha_empresa.nome`) e idioma da conta.
  Nenhum dado de cliente. Os exemplos dos campos são fictícios.

## Validação

- rspec focado: novos (`spec/services/ai/redacao/*`, `notices/custom_text_spec`, `notices/text_spec`,
  `booking_pages_notice_texts_spec`) e existentes (`sender`, `scheduler`, `agent_alert`, `notice_templates/*`, jobs de
  aviso, `booking_pages*`, modelo, policies, `ai_usage`, `template_fields/resolver`).
- Bateria `spec/fixtures/files/ai_redacao/whatsapp_texto.jsonl`: 12 casos, só com resposta simulada. A rodada com IA de
  verdade fica para o Rodrigo autorizar, com teto de custo.
- vitest da pasta de agendamento, eslint, prettier, gate de e-mail, rubocop, `autonomia:guia:formatos:check`,
  `guide-map/check`, `central-de-ajuda/conferir`, `check-fork-i18n`.

## Revisão independente (cavecrew-reviewer)

- Corrigido: colchete sobrando (rótulo que não virou campo) agora é recusado (`:bracket`), JSON fora do formato e erro
  de rede viram "indisponível" (erro de programação estoura), endereço escrito à mão na saída da IA (`://`, `www.`,
  ponto entre letras) descarta a opção, payload só com os avisos do jogo, contexto truncado em 120, a11y do cartão.
- Riscos abertos (decisão do Rodrigo): sem limite de chamadas por conta no "Escrever com IA" (nenhum endpoint de IA do
  agendamento tem; exige regra no rack-attack); o `timeout: 11` do HTTParty vale por operação, não como total (mesmo
  padrão do `NoticeTemplates::Suggester`); trocar o jogo de avisos e salvar descarta o texto próprio dos avisos que saíram
  do jogo.
