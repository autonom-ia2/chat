# G13 · Passo "webhook": mandar para outro sistema

- **Épico:** #2414 · **Issue:** #2670 · **Destrava:** exemplos 14 e 20 (passos "manda os dados para o sistema da
  seguradora/cobrança") e o passo 8 do exemplo 8.

## O que faz

O passo manda os campos escolhidos a outro sistema (n8n, ERP, seguradora, cobrança) num `POST` com JSON e usa a
resposta nos passos seguintes.

```json
{ "id": "cobranca", "tipo": "webhook", "descricao": "Mandar ao sistema de cobrança",
  "url": "https://cobranca.exemplo.com/api/clientes",
  "corpo": { "cnpj": { "$valor": "card.atributos.cnpj" }, "plano": { "$valor": "card.titulo" } },
  "gravar": [ { "chave": "cliente.numero", "destino": "card.atributos.numero_cliente" },
              { "chave": "erro", "destino": "card.atributos.motivo_cobranca" } ],
  "se_recusar": [ { "id": "avisar_financeiro", "tipo": "avisar", "para": { "pessoas": [12] },
                    "texto": ["A cobrança recusou: ", { "$valor": "card.atributos.motivo_cobranca" }] } ] }
```

- `corpo`: o valor calculado de sempre (G16). Valor vazio pula o passo sem mandar nada.
- `gravar`: chave da resposta (com ponto para entrar no objeto: `cliente.numero`) e o atributo onde grava, no card, no
  contato ou na conversa. Grava pela porta da ação, como quem ligou a automação. Só texto (até 255 letras, o resto é
  cortado), número e sim/não. Vale
  também na recusa: é assim que o motivo chega ao aviso.
- Desfecho: 2xx segue; 4xx entra em `se_recusar` (sem ele, a execução para com `webhook_recusado`, e nada do texto da
  recusa é gravado); 5xx, 408, 425, 429, falta de resposta e nome que não resolve tentam de novo (3 tentativas, 1 e 5
  minutos) e depois param; endereço bloqueado e redirecionamento param na hora.
- Depois que o outro sistema respondeu 2xx, nada é passageiro: se gravar a resposta falhar, a execução para
  (`webhook_gravar_falhou`) e o pedido **não** é mandado de novo. Uma leitura que estoura o prazo ainda tenta de novo:
  o outro sistema descarta a repetição pelo `X-Automacao-Execucao`.
- Quem pode: salvar ou ligar uma automação com o passo exige o administrador ou a função com `integration_manage`
  (regra de delegação, #2027). `automation_manage` sozinha não basta. A chave é relida a cada envio: se quem ligou
  perder a chave, mesmo no meio de uma execução, a automação pausa (`webhook_sem_permissao`).
- Flag: `automacao_gatilhos` (com o motor ligado). Sem flag nova.

## Como o outro sistema confere que somos nós

Cada automação tem um segredo. O administrador, ou a função com `token_manage`, vê e troca em
`GET|POST /api/v1/accounts/:id/autonomia/automacoes/:automacao_id/segredo_do_webhook` (`trocar_segredo_do_webhook`).

Cabeçalhos de todo envio:

| Cabeçalho | Valor |
|---|---|
| `X-Automacao-Timestamp` | segundos desde 1970 (UTC) |
| `X-Automacao-Signature` | `sha256=` + HMAC SHA256 de `"<timestamp>.<corpo>"` com o segredo |
| `X-Automacao-Execucao` | id da execução (o mesmo nas novas tentativas: use para descartar repetição) |
| `X-Automacao-Passo` | id do passo na receita |

O outro sistema recalcula o HMAC com o corpo bruto recebido e compara. Recomendado recusar timestamp com mais de 5
minutos de diferença.

## Segurança

- Só `https`, sem usuário e senha no endereço, sem seguir redirecionamento.
- Nada de rede interna: IP privado, loopback, link-local (inclui o metadata 169.254.169.254), faixa das operadoras,
  multicast e as demais faixas reservadas (a mesma lista do SsrfFilter), NAT64, IPv4 escrito dentro de IPv6 e o próprio
  servidor da plataforma (o host e os IPs de `FRONTEND_URL` e
  `HELPCENTER_URL`) são recusados ao salvar e de novo ao enviar. O nome é resolvido uma vez só, e o SafeFetch conecta
  nesses IPs já conferidos (sem segunda resolução, sem DNS rebinding). Vale mesmo com `SAFE_FETCH_ALLOW_PRIVATE_NETWORK`
  ligado na instalação.
- Prazo: 3 s para conectar, 10 s por leitura, 15 s no total. Resposta lida até 64 KB; maior que isso, nada é gravado
  (`webhook_resposta_grande`).
- O Guia não lê o segredo: a resposta da API usa a chave `secret`, que o Guia corta antes de mandar ao modelo.
- O histórico guarda só host, código, duração e as chaves gravadas. Nunca a URL inteira (pode ter token), o corpo, a
  resposta ou o segredo.
- O segredo não fica gravado: é derivado do `SECRET_KEY_BASE` com o id da automação e a geração (contador na própria
  automação, `autonomia_automacoes.segredo_geracao`). Trocar sobe a geração num UPDATE só. Como o contador não mora num
  campo que outros pontos regravam inteiro, nenhuma gravação concorrente volta o segredo anterior. **Trocar o
  `SECRET_KEY_BASE` troca o segredo de todas as automações**: os sistemas de fora precisam do novo.
- Ver e trocar o segredo: o administrador ou a função com `token_manage` (regra de delegação, #1782: é um dos segredos
  que a plataforma gera).
- Limite conhecido: o IP da própria plataforma é comparado com o que o nome de `FRONTEND_URL` e `HELPCENTER_URL`
  resolve. Se a plataforma ficar atrás de uma CDN (Cloudflare e afins), um endereço de cliente servido pelo mesmo IP da
  CDN é recusado como `webhook_endereco_interno`. Quem puser a plataforma atrás de CDN precisa rever esta regra.

## Fora deste PR

- Webhook de entrada (outro sistema disparando a automação).
