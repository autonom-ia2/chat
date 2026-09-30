# Importação inteligente de destinatários

## Objetivo

A importação de destinatários de campanhas de e-mail aceita CSV e XLSX sem exigir que o arquivo seja reformatado para um único padrão de separador, encoding, aba ou nomenclatura de cabeçalho. Quando habilitado e configurado, TypeSafe Jev interpreta os cabeçalhos antes dos aliases locais, inclusive quando Cliente e Contato parecem nomes ou há e-mails principal e secundário. A estrutura do arquivo e a existência de endereços válidos continuam sendo verificadas localmente antes da chamada. Com Jev desligado, os aliases conhecidos resolvem o arquivo sem chamada externa.

A regra de negócio é: **e-mail é obrigatório; nome é opcional**. Colunas não mapeadas para nome/e-mail continuam em `custom_data`.

## Configuração no SuperAdmin

A integração fica em **SuperAdmin → Settings → TypeSafe AI**.

- `Enable intelligent imports with Jev`: habilita a interpretação de colunas. O padrão é desligado.
- `Jev model`: fixado em `jev-1.13.0`; não se usa `jev-latest` em produção.
- `TypeSafe API Key`: campo de escrita única. Depois de salva, a chave não retorna no HTML e deixar o campo vazio preserva a chave atual.
- `Test connection`: consulta `GET https://api.typesafe.ai/v1/models` usando a credencial salva.

A chave não é gravada em `InstallationConfig`. Ela fica em `ai_provider_credentials.api_key` com Active Record Encryption. A instalação precisa ter `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`, `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` e `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT`; sem o cofre configurado a aplicação recusa gravar a chave e recusa habilitar Jev.

## Fluxo

1. O upload permanece assíncrono e durável; o arquivo é persistido antes do job.
2. O parser identifica CSV/XLSX.
3. CSV é normalizado para UTF-8 e suporta UTF-8/BOM, UTF-16 LE/BE com BOM e Windows-1252. O separador é escolhido entre vírgula, ponto e vírgula, TAB e pipe.
4. XLSX expõe todas as planilhas do workbook, não apenas a primeira.
5. O resolver examina até 100 linhas candidatas por tabela/aba para encontrar o cabeçalho real, inclusive quando há títulos/linhas informativas antes dele.
6. Com Jev habilitado e configurado, ele interpreta as colunas antes de validar o mapeamento, sem recusar automaticamente os aliases duplicados. Ambiguidades reais de destinatário continuam exigindo correção pelo usuário.
7. Jev recebe os cabeçalhos, a posição do cabeçalho, a presença de endereços válidos por coluna e até três exemplos estruturais de 80 caracteres por coluna. A verificação de presença cobre todas as linhas, mesmo quando a amostra de até 50 linhas não contém nenhum endereço válido. Colunas com endereço confirmado enviam apenas o marcador de formato válido; contagens e proporções de linhas inválidas ficam locais, separando identificação da coluna e qualidade dos destinatários. Nos exemplos, letras e dígitos são substituídos por `A`, `a`, `0` e `x`; pontuação limitada mantém apenas o formato. Nomes, telefones, notas e endereços reais das linhas não são enviados.
8. O de/para exige confiança suficiente no e-mail, confirmação do esquema e evidência local na coluna escolhida. Dúvida sobre o nome opcional deixa essa coluna como dado adicional, sem impedir a importação.
9. O job grava destinatários, issues, contadores e conclusão com os locks/transações existentes.
10. `email_campaign_imports.schema_resolution` registra apenas metadados não sensíveis da decisão: método, formato, aba, linha do cabeçalho, delimitador, índices de colunas e, quando aplicável, modelo/confianças do Jev.

## TypeSafe

Cliente direto, sem OpenRouter:

- Base: `https://api.typesafe.ai`
- Modelos: `GET /v1/models`
- Decisão: `POST /v1/systemone`
- Modelo fixado: `jev-1.13.0`

A chamada semântica ocorre antes dos locks de escrita do importador. No job de importação, erros `429`, `529` e `5xx` têm até duas repetições curtas no cliente. O teste de conexão síncrono faz uma única tentativa com timeout, para caber no limite da requisição web. A UI não exibe corpo de resposta de erro nem credenciais.

Quando TypeSafe estiver temporariamente indisponível, o import fica `failed` com código sanitizado, o arquivo permanece anexado e a tentativa fica reutilizável dentro da janela normal de retenção. Com Jev habilitado, não há troca silenciosa para aliases quando o serviço falha. Com a integração desligada, arquivos reconhecidos pelos aliases continuam importando sem TypeSafe.

## Formatos e casos cobertos

- CSV com `,`, `;`, TAB ou `|`.
- Campos CSV entre aspas contendo os próprios delimitadores.
- UTF-8, UTF-8 com BOM, UTF-16 LE/BE com BOM e Windows-1252.
- XLSX com base na primeira ou em outra aba.
- Linhas de título/relatório antes do cabeçalho.
- Nome opcional e e-mail obrigatório.
- Colunas extras preservadas em `custom_data`.
- Duplicados, inválidos e suprimidos preservam o comportamento de higiene existente.
- Até 50.000 linhas de dados; 50.001 é recusado antes de inserir destinatários.

A regressão obrigatória do incidente #764 é o cabeçalho `NOME;E-MAIL;CORRETORA`; ele deve importar sem o usuário editar o arquivo.

## Privacidade e segurança

Nomes de abas não são enviados. A resolução estrutural é gravada na mesma transação que os destinatários, contadores e conclusão do import, para que um job concorrente não sobrescreva a decisão que venceu.

- A API key nunca deve ser colocada em commit, log, issue, PR ou chat.
- A chave salva não retorna para a página do SuperAdmin.
- TypeSafe recebe metadados estruturais, perfis derivados e formatos de exemplos mascarados; valores reais das linhas não são enviados pelo resolver.
- Não há chamada Jev por destinatário: uma resolução semântica por arquivo selecionado, com até duas repetições de transporte em falhas temporárias.
- Saída do modelo nunca substitui a validação determinística de e-mail.

## Operação e troubleshooting

1. Confirme que Active Record Encryption está configurado.
2. Em **SuperAdmin → Settings → TypeSafe AI**, salve a chave.
3. Use **Test connection**.
4. Mantenha Jev desligado até o teste da conexão passar.
5. Habilite Jev e faça um upload controlado sem agendar/enviar a campanha.
6. Confira `recipient_import.status`, resultado e `schema_resolution`; não registre conteúdo de destinatários em logs.

Erros externos são reduzidos a códigos como `typesafe_invalid_key`, `typesafe_rate_limited`, `typesafe_overloaded`, `typesafe_unavailable` e `typesafe_invalid_response`. O editor abre um diálogo com motivo, orientação e envio do arquivo corrigido na mesma campanha. Só falhas temporárias ou desconhecidas oferecem a repetição do arquivo original; erros de configuração e solicitação recusada orientam procurar o administrador. A interface não mostra payloads externos. A API exige permissão de gerenciamento para importar ou repetir arquivos, inclusive com funções personalizadas.

## Atualização do modelo

Não substituir `jev-1.13.0` por alias móvel. Uma atualização exige corpus de regressão com arquivos brasileiros, comparação de mapeamentos/confianças, suíte completa verde, revisão e alteração explícita do modelo.

## Rollback

O rollback operacional é primeiro desligar **Enable intelligent imports with Jev**. Isso preserva a credencial, arquivos, importações e `schema_resolution`; arquivos reconhecidos deterministicamente continuam funcionando. Não remover a migration nem apagar importações durante rollback de aplicação. Um rollback de código deve respeitar as mesmas regras de drenagem de importações ativas descritas no runbook de importação assíncrona.
