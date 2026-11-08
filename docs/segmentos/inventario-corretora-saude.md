# Inventário corretora × saúde (#2083)

24/10/2026. Base: head `c3b0292273` do #2156 (lote 2), que já traz o lote 1 (#2089, no ar).

## Método e alcance

- Script em Ruby, sem regex, que compõe o texto que cada conta vê (base ← seguros ← perfil) e compara os perfis
  `seguros/corretora` e `seguros/saude_beneficios` em cinco superfícies: painel, servidor, Guia, Central de Ajuda e
  instrução dos agentes.
- Palavras que a saúde não usa (DECISOES.md, 22/10): segurado, apólice, sinistro, seguradora, beneficiário,
  ganho/ganhou, perdido/perdeu, negócio, "fechou o plano", "venda ganha". Comparação por palavra inteira.
- Rótulo velho: rótulo do painel que o pacote renomeou (até 40 caracteres) e que o Guia ou a Central do perfil ainda
  citam em negrito com o nome da base. Quebra de linha normalizada.
- Cada achado de palavra foi lido no trecho (≈150 caracteres em volta). Os de rótulo foram lidos no artigo quando
  marcados "confirmado"; os demais estão "a conferir".
- Não entra: o módulo Cotação (seguro auto: condutor, veículo), que fala em seguradora de propósito.

## Números

| Superfície | Corretora | Saúde | Só a corretora troca | Palavra proibida que a saúde vê |
|---|---|---|---|---|
| Painel (chaves) | 440 | 390 | 108 (a saúde vê a base) | 0 |
| Servidor (chaves) | 23 | 25 | 1 | 0 real (2 são a instrução "nunca diga segurado") |
| Guia (fluxos em porques.md) | 11 | 21 | 0 | 2 reais em 19 blocos marcados |
| Central (variantes) | 17 | 24 | 1 | 1 real em 32 artigos marcados |
| Agentes (agentes.md) | 1.412 car. | 1.356 car. | — | 0 |

Os marcados que não são reais usam a palavra em outro sentido: "ganha dono", "perdeu a conexão", "chamadas perdidas",
"Gerenciador de Negócios", "Google Meu Negócio".

## Achados

### 1. Rótulo velho no Guia e na Central (vale para os dois perfis)

| Onde | Texto citado | A tela mostra (saúde · corretora) | Estado |
|---|---|---|---|
| Central 10.02, O que dá errado | **Nome do negócio** | Qual plano · Qual seguro | confirmado |
| Central 10.11 | **Funil do lead**, **Etapa do lead** | Funil do cliente, Etapa do cliente (nos dois) | confirmado |
| Central 10.17 | **Conversa de vendas** | Conversa para cotar (nos dois) | confirmado |
| Central 18.05 | modelos prontos **Vendas** | Venda de plano · Venda de seguro | confirmado |
| Central 13.20 | **Propostas**, **Vendas** no caminho do dinheiro | Cotações · Cotações | a conferir (Vendas pode ser outra chave) |
| Central 04.06 | perfil **Vendedor (SDR)** | Corretor (nos dois) | a conferir |
| Central 03.05 | cartão **Sua empresa** | Sua corretora (nos dois) | a conferir |
| Só corretora: Guia | **Vendendo**, **Novo card**, aba **Cards** | Cotando, Nova cotação, Seguros | a conferir |
| Só corretora: Central 10.13, 10.06, 10.01, 10.03, 09.10, 00.01, 01.01, 17.01 | Meta do mês, Novo card, Meta de vendas por mês, Etapas e negócio, Nome da empresa, Organizar as vendas, Financeiro | rótulos da corretora | a conferir |
| Central 13.29 | **Quanto custa?** | — | falso: é pergunta do FAQ, não o botão |

Causa raiz: nada liga o texto do Guia e da Central ao rótulo que o pacote troca. A checagem acima, virando spec,
pega o próximo caso no PR.

### 2. Saúde: "negócio" no Guia

- "Lembrete que repete, lembrete sem card e quem recebe o aviso": "Dá para criar lembrete sem negócio?" e "o
  lembrete precisa ser de um negócio do funil" → card.
- "Ver a gestão de campanhas": "Quantas campanhas viraram negócio no CRM?" → card.

### 3. Painel: 108 chaves que só a corretora troca

A saúde vê o texto da base, por decisão "herda" do lote 1. Parte é neutra e está certa. Parte é oportunidade de texto
próprio, que pede decisão:

- **Nome das coisas do CRM:** Novo card / Ver cards / Meus cards / Cards no CRM / Buscar card (corretora: Nova
  cotação / Ver cotações / Minhas cotações / Seguros no CRM). "Cotação" já é palavra aprovada da saúde.
- **Meta e receita:** Meta do mês, Receita por origem (corretora: produção).
- **Exemplos com cara de ramo:** chips e conversa de exemplo dos agentes ("Oi, preciso de ajuda"), placeholders de
  campanha e e-mail ("Boletim de junho", "Reativação Junho"), lembrete ("ligar para um cliente na sexta"), modelo de
  WhatsApp "Promoção".
- **Nome da empresa:** "Nome da empresa", "Detalhes da empresa", "Vamos deixar seu atendimento pronto" (corretora:
  corretora). O corretor de saúde também é corretora.
- **Arquivos do contato:** "Arquivos compartilhados nas conversas" (corretora cita apólices e boletos; a saúde poderia
  citar boletos e carteirinhas).

Lista completa, com o texto de cada perfil e a decisão de cada chave: `proposta-108-chaves-saude.md`.

### 4. Servidor e Central: um item cada

- `brand_kits.import_errors.invalid_url`: a corretora diz `https://suacorretora.com.br`; a saúde vê
  `https://suaempresa.com.br`.
- Central 05.01 (Times): a corretora sugere times "Vendas, Renovação ou Sinistro"; a saúde vê o texto da base.

## Proposta de lote 3

1. Spec de trava: rótulo renomeado pelo pacote não pode aparecer em negrito no Guia ou na Central do mesmo perfil.
2. Corrigir os achados 1, 2 e 4 nos dois perfis.
3. Decidir com o Rodrigo quais das 108 chaves do achado 3 a saúde ganha com texto próprio.

## O que o lote 3 fez

- **Trava:** `spec/config/pacotes_rotulos_no_guia_e_central_spec.rb`. Para cada perfil, pega todo rótulo da base que o
  pacote troca e procura o nome antigo no Guia (fluxo por fluxo) e na Central daquele perfil: em negrito sempre, e em
  texto comum quando o rótulo tem duas ou mais palavras. Os falsos positivos ficam numa lista com o motivo, e exceção
  que deixa de acontecer também falha.
- **Texto comum:** a revisão do PR achou rótulo velho fora do negrito, e a trava estendida pegou mais casos no Guia
  dos dois perfis: modelos da página de agendamento, modelo de agente "Atender quem quer comprar", etapa "Organizar as
  vendas" dos Primeiros passos, grupo "Sua empresa" das Configurações, campo "Nome da empresa" do modelo de WhatsApp
  e, só na corretora, "ao lado de Novo card" na exportação e "Meta do mês" nas perguntas do 10.13. Todos corrigidos.
- **Achado 1:** corrigido nos dois perfis, artigo por artigo, só nas variantes do perfil (a camada seguros serve
  seguradora e insurtech, que mantêm o rótulo da base). Conferidos e descartados como falso positivo: 13.29
  **Quanto custa?** (título do FAQ), 09.10 **Nome da empresa** (campo do contato), 13.20 **Vendas** (etapa do caminho
  do dinheiro, que nenhum pacote troca), 10.13 **Cards** (contadores do dashboard), **Financeiro** em 01.01, 04.06 e
  17.01 (menu e perfil de função) e **Novo card** no Guia da corretora (botão da ficha do contato).
- **18.05:** o texto da base estava velho para todo mundo ("Vendas, Atendimento e Agendamentos", e a tela diz
  Vendas, Suporte e Agendamento). A base passou a dizer só "as etapas dos modelos prontos".
- **Achado 2:** "lembrete sem negócio" e "viraram negócio no CRM" corrigidos no Guia da saúde. Ficou de fora "o
  lembrete precisa ser de um negócio do funil": está em `pre_requisitos`, que o pacote do Guia não troca (só
  `titulo`, `intent`, `onde_fica`, `passos` e `gotchas`).
- **Achado 3:** 71 chaves (41 próprias, 30 iguais à corretora), conforme a proposta aprovada, com o chip do
  dermatologista trocado pela pergunta de reembolso.
- **Achado 4:** `invalid_url` e Central 05.01 da saúde corrigidos.
