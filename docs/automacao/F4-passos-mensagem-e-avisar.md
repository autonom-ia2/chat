# F4: passos "mensagem" e "avisar" (#2414)

Desenho com as decisões da sessão Automação de 02/11/2026, depois da rodada da qualidade.
- **Branch:** `feat/2459-f4-mensagens`, empilhada no PR-B da F3 (#2459).
- Sem migration.

## Regra principal: sem freio no uso do cliente (Rodrigo, 31/10/2026)

O cliente manda quantas mensagens quiser. A F4 **não tem teto de mensagens**: nem por conversa, nem por automação,
nem por hora, nem por conta. A linha da F4 no épico ("teto de mensagem por conversa") virou **proteção anti-laço**,
que só pega defeito. Uso legítimo, por maior que seja, nunca é barrado. Isso vale também para texto repetido: o menu
"responda 1 ou 2", errado 5 vezes em 2 minutos, responde as 5.

## Flag `automacao_mensagens`

- **Própria da F4.** Só vale com `automacao_motor` e `automacao_fundacao`: sem a fundação não há a cadeia comum contra
  laço com as regras antigas.
- **Bit:** sai da ordem no yml: `feature_flags_ext_2`, posição 23 (4194304), logo depois de `automacao_editor`
  (F5, #2485), que entrou primeiro na main e ficou com a 22.
- **Contas:** nasce DESLIGADA em todas as contas; só liga depois da #2486 (Salvar tudo).
- **Desligada:**
  - o salvar recusa o passo (`passo_desligado`);
  - a execução que chega nele fecha como parada (`mensagens_desligadas`), sem mandar nada. É o rollback.

## Passo `mensagem`

```json
{ "id": "p3", "tipo": "mensagem", "texto": ["Oi ", { "$valor": "contato.nome" }, ", seu pedido saiu."] }
```

- **Autor (D9):** sai como "Automação". O `sender` fica vazio, e `content_attributes` leva `automacao_id`,
  `execucao_id` e `passo`.
  - A marca `automacao_id` entrou na lista única de envios automáticos (`PessoaDaEquipe` e o espelho no front).
  - Não conta como resposta de pessoa: `first_reply_created_at` e `waiting_since` ficam como estavam (spec).
  - No Híbrido, a origem é `automation`.
- **Pula, com motivo:**
  - valor vazio: `faltou_valor`;
  - texto em branco: `texto_vazio`;
  - contato que pediu para não receber (`opted_out_at`, o campo das campanhas): `contato_nao_recebe`;
  - tweet: `canal_sem_resposta`.
- **Janela:** `MessageWindowService.new(conversa, automatic: true)`, para todo canal com janela (WhatsApp, Instagram,
  Messenger, TikTok, Twilio, API com prazo).
  - Como envio automático, a tag de agente humano da Meta não vale, e a janela é de 24 h.
  - A caixa híbrida com o WhatsApp API pronto responde fora da janela.
  - Fora da janela: `fora_da_janela`. É só texto livre; o modelo da Meta é a F4b, #2468.
- **Resultado:** o passo dá `ok` quando a mensagem é criada. O passo que deu ok nunca reenvia.
- **Duplicidade:** é tratada pelo evento de origem, nunca pelo texto. Uma execução por mensagem recebida e, no
  máximo, uma resposta do passo por evento. A marca por evento fica na escuta (PR-C), que eu refaço sobre este PR.

## Passo `avisar`

```json
{ "id": "p4", "tipo": "avisar", "para": { "responsavel": true, "times": [3], "pessoas": [12] },
  "texto": ["Cliente ", { "$valor": "contato.nome" }, " pediu desconto"] }
```

- **Como:** uma nota privada da Automação na conversa, que menciona cada pessoa.
  - O aviso é o da menção que a plataforma já tem (`conversation_mention`): sino, push e e-mail pela preferência de
    cada pessoa.
  - Nenhum tipo de notificação novo (o 13 e as flags dele deixaram de ser necessários).
- **Para quem:**
  - o responsável, os times (abertos pessoa a pessoa) e as pessoas escolhidas, só da conta;
  - fica só quem passa no `ConversationPolicy#show?` de cada pessoa. Função personalizada e administrador mudam a
    resposta; não basta estar na caixa;
  - nunca menciona o time inteiro, só pessoas, cada uma conferida;
  - a menção só avisa administrador e membro da caixa: quem enxerga a conversa de outro jeito ficaria mencionado sem
    aviso, e por isso sai;
  - quem sai fica no registro do passo (`fora`), com o motivo: `nao_ve_a_conversa`, `nao_e_da_caixa` ou
    `fora_da_conta` (saiu da conta depois do salvar);
  - o texto, com os valores, só chega a quem passou;
  - lista vazia pula com `ninguem_para_avisar`.
- **No salvar:** time e pessoa de outra conta são recusados.

## Passo `email` (G2, Destrava: exemplo 13)

Manda um e-mail ao contato do alvo pela caixa de e-mail da conta escolhida na receita: `{ id, tipo: "email", caixa_id, assunto, texto }`. `assunto` e `texto` aceitam valores, como o `mensagem`. Mesma flag (`automacao_mensagens`); sem flag nova. Código: `app/services/autonomia/automacao/passo_de_email.rb`.

- **Contato:** sai do alvo (`Contexto#contato`): a conversa de qualquer canal (o WhatsApp, por exemplo), o card ou o próprio contato.
- **Envio:** abre uma conversa nova na caixa, como o "Nova conversa" do painel: `ContactInboxBuilder` (o `source_id` vira o e-mail do contato) e `ConversationBuilder` com `additional_attributes.mail_subject` = assunto, que é de onde o envio lê o assunto. A mensagem é `Messages::MessageBuilder` sem remetente e com a marca, e sai pelo envio de sempre (`SendReplyJob` → `Email::SendOnEmailService`, SMTP ou Microsoft Graph). Nenhum mailer novo. Caixa com `lock_to_single_conversation` reaproveita a conversa dela.
- **Quem recebe a conversa:** a Atribuição, como qualquer conversa nova. O passo não atribui.
- **Pula, com motivo:** `caixa_de_email_indisponivel` (apagada ou deixou de ser de e-mail), `contato_sem_email`, `contato_nao_recebe` (o mesmo campo das campanhas), `email_bloqueado` (`EmailSuppression.suppressed?`: devolução, reclamação, descadastro; a régua das campanhas), `faltou_valor`, `texto_vazio` (assunto ou texto em branco).
- **Quem ligou:** precisa estar na caixa de e-mail (ou ser administrador), a mesma pergunta da `ConversationPolicy` para começar conversa. Sem isso o passo devolve `sem_acesso` e a automação pausa, como nos outros passos.
- **Sem janela** (e-mail não tem) e **sem teto de uso**.
- **Ao salvar:** a Receita recusa `caixa_id` que não é caixa de e-mail da conta (`caixa_de_email_invalida`).
- **Fora deste passo (D3):** HTML, anexo, cc/cco.

### Resposta automática não dispara gatilho

"Mensagem recebida → manda e-mail" giraria sem fim com o autoresponder do outro lado ("estou de férias"): a resposta chega como mensagem do contato, e a cadeia não a vê. O `MailPresenter` já marca a resposta automática pelo cabeçalho (`Auto-Submitted`, `X-Autoreply`): na mensagem (`Message#auto_reply_email?`) e na conversa que ela abre (`additional_attributes.auto_reply`). A `Escuta` não começa gatilho por ela (`Escuta.resposta_automatica?`), para qualquer passo, a mesma regra das automações antigas (`AutomationRuleListener`). O ensaio usa a mesma régua e mostra a conversa com o motivo `resposta_automatica`. O "esperar até" continua sendo acordado pela mensagem: acordar só reconfere a condição.

## Alvo card

- Os dois passos agem na conversa principal do card, com os valores dela.
- Card sem conversa principal pula com `sem_conversa`, e o histórico mostra. Nada é mandado.
- Quem ligou precisa enxergar a conversa principal, e não só o card: sem acesso, nada sai e a automação pausa com
  `quem_ligou_sem_acesso`, como na ação. A regra fica nos dois passos (`NaConversa#sem_acesso`).
- Os gatilhos de card são da F6.

## Proteção anti-laço

1. **Cadeia comum (F1, D6):** a mensagem sai dentro da cadeia da execução.
   - A escuta não dispara a própria automação e para na profundidade 3, contando os três motores.
   - A regra antiga que responde a toda mensagem de saída (o padrão das contas 6, 16 e 17) responde uma vez e para.
2. **Robô do outro lado:** são **40 envios respondidos seguidos** desde o último corte.
   - **Envio respondido:** uma mensagem do passo "mensagem" do motor novo que recebe resposta do contato em **menos
     de 20 s**. Cada envio conta, e não cada troca. Por isso a amplificação é pega: o robô que responde com 2 balões
     dispara uma execução por balão, o volume dobra a cada volta, e a conta chega a 40 em poucas voltas.
   - **Leitura:** as mensagens desde o último corte, no máximo as 1000 mais recentes. O 1000 é só limite da
     consulta, não teto: passar dele não dispara nada.
   - **Fica de fora:** mensagem de IA, de robô (AgentBot), das automações antigas ou de campanha. Ela não conta nem
     corta.
   - **Corte:** quando uma pessoa da equipe escreve, ou quando a conversa fica 30 min sem mensagem.
   - **Zera:** a resposta que chega em 20 s ou mais depois do nosso último envio. Robô não demora; gente demora, e a
     conversa humana longa, sem pausa de 30 min, não junta respostas rápidas espalhadas.
   - **Ao disparar:** a execução para com `laco_suspeito`, só nessa conversa, e a automação continua ligada. Fica uma
     nota para a equipe, que menciona quem ligou. É uma nota só por automação e conversa até o próximo corte, mesmo
     com várias execuções em voo (o robô de 2 balões): sem enxurrada de avisos para a mesma pessoa.

Os números ficam em constantes (`AntiLaco`). As specs provam cada caso:
- robô de 2 balões, com execuções de verdade (uma por balão), para antes de 100 mensagens;
- robô com latência de 12 s é pego no 40º envio respondido; com 39, ainda manda;
- 39 respostas rápidas, 1 lenta e mais 39 rápidas não disparam;
- receita de 2 passos contra robô é pega;
- passam: pessoa rápida com receita de 2 passos em 10 voltas, cliente humano com 20 mensagens no próprio ritmo, menu
  errado 5 vezes e cliente com 50 mensagens ao longo do dia, com pausas de mais de 30 min;
- mensagem de IA ou de regra antiga no meio não conta nem corta;
- a conta recomeça com pessoa da equipe e com 30 min parada.

## Envio pelos canais (sem remetente)

Specs com o envio de verdade:
- WhatsApp Cloud e Instagram passam pelo `SendReplyJob` com o HTTP simulado, sem erro;
- o Híbrido manda fora da janela oficial;
- a mensagem passa por todos os ouvintes do evento (`EventDispatcherJob`) e chega ao webhook com `sender` vazio.

## Fora da F4

- Modelo da Meta: F4b, #2468.
- Anexo e e-mail como canal.
- Escolher a caixa quando o contato tem várias conversas.
- Variável no corpo da ação do catálogo. A `Receita` diz "chega com a mensagem (F4)", mas a F4 não a trouxe: fica
  para quando um caso pedir.
