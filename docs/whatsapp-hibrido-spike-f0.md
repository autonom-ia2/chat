# WhatsApp Híbrido — roteiro do spike F0

**PRD:** `docs/whatsapp-hibrido-cloud-waha-prd.md` (seções 0 e 24)
**Conta:** 1 (piloto) · **Caixa:** 111 "Autonom.ia WhatsApp" · **Contatos:** Autonomia Comunidade, Rodrigo Victor
**Sem código de produto.** Nada de PR de feature até este roteiro passar.

## Objetivo

Responder duas perguntas, nesta ordem. Se a primeira falhar, a segunda não roda.

1. **Gate zero — o vínculo funciona?** Um número em Coexistência aceita uma sessão WhatsApp Web via WAHA (GOWS 2026.9.2) e ela fica estável?
2. **Gate um — a correlação é determinística?** Dá para ligar, sem heurística, o ID da mensagem enviada pelo WAHA ao `wamid` do eco `smb_message_echoes` que a Meta entrega na Cloud?

## Pré-requisitos

- Caixa WhatsApp Oficial da conta 1 em Coexistência, saudável (aba Saúde da conta).
- Celular com o WhatsApp Business desse número em mãos.
- Contatos de teste: Autonomia Comunidade e Rodrigo Victor (celulares nossos, com telefone).
- Sessão WAHA nova, nome `hybrid-spike-<numero>`, **sem** App Chatwoot, **sem** App de números brasileiros e **sem webhook**. Eventos WAHA lidos sob demanda pela API do próprio WAHA (mensagens do chat e ACK) — nada sai para serviço externo.
- Lado Cloud lido no banco de produção, somente leitura (psql via SSM): `messages.source_id`, `content_attributes`, `created_at` das conversas dos dois contatos na caixa 111.
- Comportamento esperado hoje (sem código novo): o eco Cloud de um envio WAHA aparece como bolha outgoing nova na conversa. Isso é o que vamos medir; não é bug a corrigir no F0.

## Gate zero — vínculo

| # | Passo | Passa se |
|---|---|---|
| 0.1 | Criar sessão WAHA e ler QR pelo WhatsApp Business do número | Sessão chega a `WORKING` |
| 0.2 | `GET /api/{session}/auth/me` (ou equivalente) | Número retornado = número da Cloud |
| 0.3 | Conferir a Cloud após o vínculo | Saúde da conta igual a antes; webhook Cloud continua chegando |
| 0.4 | Deixar a sessão 24h ligada | Sem desconexão; sem aviso da Meta no WhatsApp Business ou no Business Manager |

Falhou qualquer item: parar e reportar com evidência.

## Gate um — correlação

Para cada envio:

1. `POST /api/{session}/... new message id` → guardar `waha_id`.
2. Enviar pelo WAHA usando esse ID.
3. Capturar: resposta do POST, a mensagem e seu ACK lidos pela API do WAHA, e o eco `smb_message_echoes` gravado no banco (source_id da bolha nova).
4. Registrar numa planilha: `waha_id`, ID retornado, `wamid` do eco, decodificação do `wamid` (base64 → campos), latência POST→eco.

Os envios são **trocas reais de mensagem**, não disparos soltos. Roteiro por contato:

| Cena | O que acontece | O que medir |
|---|---|---|
| E1 | Contato escreve → Cloud recebe | Inbound entra só pela Cloud, uma bolha |
| E2 | Resposta pelo WAHA **dentro** de 24h | Eco Cloud chega? ID bate? |
| E3 | Contato responde à mensagem do WAHA | Cai na mesma conversa, sem duplicata, reply-to aponta certo |
| E4 | Resposta pelo WAHA **fora** de 24h (conversa sem inbound recente) | Entrega ao contato + eco Cloud |
| E5 | Dois textos idênticos em sequência rápida | Correlação sem confundir os dois |
| E6 | Imagem, documento, áudio pelo WAHA | Eco e ID por tipo de mídia |
| E7 | Mensagem enviada pelo celular (WhatsApp Business) | Continua igual a hoje (eco já existente) |

Volume mínimo somando os dois contatos:


| Tipo | Contato A | Contato B |
|---|---|---|
| Texto | 10 | 10 |
| Imagem | 3 | 3 |
| Documento | 3 | 3 |
| Áudio | 2 | 2 |
| Texto idêntico repetido em sequência rápida | 3 | 3 |

Total: 42 envios. Incluir ao menos um envio com o contato fora da janela de 24h.

### Passa se

- Toda mensagem gera exatamente um eco Cloud (ou a ausência de eco é consistente e documentada).
- Existe regra determinística `waha_id ↔ wamid` com **zero** falso positivo nos 42, inclusive nos textos idênticos.
- Eco que chega antes da resposta do POST também é correlacionável pelo ID pré-gerado.

### Se não passar

Documentar o que faltou. Não seguir com matching por texto e horário. Reavaliar o projeto com o Rodrigo.

## Saída

`docs/audit/<data>-whatsapp-hibrido-spike-f0.md` com resultados, regra de correlação encontrada e decisão (seguir / parar). Sem telefones completos, tokens ou conteúdo de clientes.

## Limpeza

Ao fim: logout e exclusão da sessão `hybrid-spike-*` no WAHA. Nenhuma alteração na caixa oficial.
