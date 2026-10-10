# WhatsApp Híbrido no Chat2You — Resumo Funcional

## Objetivo

Permitir que uma mesma caixa de WhatsApp no Chat2You utilize dois transportes no mesmo número:

- **WhatsApp Oficial / Cloud API** como conexão principal.
- **WhatsApp API / WAHA** como conexão auxiliar via QR Code.

Para o atendente, continua existindo **uma única conversa** no Chat2You.

## Como será a conexão

1. O administrador conecta primeiro o **WhatsApp Oficial**.
2. O Chat2You confirma que a Cloud está funcionando, o número está em **Coexistência** e a conta está saudável.
3. Na configuração da própria caixa oficial aparece a nova aba **WhatsApp API**.
4. O administrador clica em **Conectar WhatsApp API**.
5. O Chat2You cria automaticamente uma sessão no **WAHA** usando o mesmo número.
6. O sistema mostra o QR Code.
7. O administrador lê o QR pelo WhatsApp Business.
8. O Chat2You confirma que o número conectado no WAHA é o mesmo número da Cloud.
9. A conexão híbrida é ativada.

Não será necessário criar e administrar uma segunda caixa de atendimento.

## Lógica de funcionamento

| Situação | Transporte |
| --- | --- |
| Cliente envia mensagem | **Cloud / Oficial** |
| Agente responde dentro de 24h | **Cloud / Oficial** |
| Agente responde depois de 24h | **WAHA / WhatsApp Web** |
| Template aprovado | **Cloud / Oficial** |
| WhatsApp Flow, catálogo e recursos Meta | **Cloud / Oficial** |
| Recurso disponível apenas no WhatsApp Web | **WAHA** |
| Cloud falha antes de enviar e a falha é comprovadamente segura | **WAHA como fallback** |
| Não é possível saber se a Cloud chegou a enviar | **Não reenviar automaticamente** |

## Regra principal

A **Cloud é dona da conversa**.

O WAHA é apenas um **segundo transporte de envio**.

Continuam na caixa oficial:

- histórico;
- contato;
- responsável;
- equipe;
- CRM;
- IA/bot;
- automações;
- etiquetas;
- SLA;
- relatórios.

## Exemplo

O cliente escreve às 10h e o Chat2You recebe pela **Cloud Oficial**.

O atendente responde às 11h. Como ainda está dentro da janela de 24 horas, a resposta sai pela **Cloud**.

Dois dias depois, o atendente escreve na mesma conversa. A janela oficial está fechada. O Chat2You percebe isso automaticamente e envia pelo **WAHA**, sem trocar de conversa.

## Interface

Na caixa oficial:

    Configurações
    Colaboradores
    Horário
    CSAT
    Configuração
    Saúde da conta
    WhatsApp API    ← nova aba

Antes de conectar:

    Conexão híbrida

    WhatsApp Oficial    ● Conectado
    Coexistência        ● Ativa

    WhatsApp API        ○ Não conectado

    [ Conectar WhatsApp API ]

Depois:

    WhatsApp Oficial    ● Saudável
    WhatsApp API        ● Conectado

    Roteamento automático

    Dentro de 24h       Oficial
    Fora de 24h         WhatsApp API
    Templates           Oficial
    Fallback seguro     Ativado

## Identificação na conversa

Cada mensagem enviada poderá indicar discretamente o transporte utilizado:

- **Oficial**
- **WhatsApp API**
- **WhatsApp API · fallback**

## Proteção contra duplicidade

Quando uma mensagem for enviada pelo WAHA, a Meta pode devolver essa mesma mensagem para a Cloud por causa da Coexistência.

O Chat2You deverá reconhecer que o envio WAHA e o echo Cloud representam **a mesma mensagem** e manter apenas uma bolha na conversa.

## Segurança do fallback

Não faremos:

    Cloud deu qualquer erro
            ↓
    manda novamente pelo WAHA

O sistema distinguirá:

- **Falha segura:** existe certeza de que a Cloud não enviou → pode tentar WAHA.
- **Falha definitiva:** número inválido, opt-out, bloqueio etc. → não tenta outro transporte.
- **Falha indeterminada:** não sabemos se a Cloud chegou a enviar → **não haverá fallback automático**.

Essa regra evita mensagem duplicada para o cliente.

## Contato sem telefone utilizável

A Cloud pode operar com identificadores próprios da Meta, como BSUID.

Se não houver telefone resolvível de forma segura:

- a Cloud continua funcionando;
- o WAHA não será usado;
- fora das 24h será necessário template oficial.

Nunca tentaremos descobrir telefone por nome ou aproximação.

## O que já temos

O Chat2You já possui grande parte das peças:

- WhatsApp Cloud;
- Embedded Signup;
- Coexistência;
- janela de 24 horas;
- templates;
- echoes da Meta;
- sincronização de histórico;
- saúde da conta;
- WAHA;
- QR Code;
- reconexão;
- GOWS;
- normalização de números brasileiros.

O desenvolvimento novo é principalmente a camada que decide **qual transporte usar por mensagem** e garante que Cloud e WAHA representem a mesma conversa.

## Primeiro passo técnico

Antes da implementação completa precisamos provar:

> Quando uma mensagem sai pelo WAHA, conseguimos relacionar de forma inequívoca o ID dessa mensagem com o echo/wamid devolvido pela Meta?

Fluxo a validar:

    Chat2You Message
          ↓
    WAHA Message ID
          ↓
    WhatsApp
          ↓
    Meta Cloud Echo / wamid
          ↓
    mesma Message no Chat2You

Só depois dessa correlação estar comprovada avançaremos para o roteamento automático completo.

## Resultado esperado

Para o atendente:

> **Uma caixa. Uma conversa. Um botão de enviar.**

Para o Chat2You:

> Cloud e WAHA trabalhando juntos, escolhendo automaticamente o transporte mais adequado para cada mensagem.

A Cloud continua sendo a conexão principal e oficial. O WAHA adiciona uma segunda capacidade de transporte sem dividir o atendimento em duas caixas.
