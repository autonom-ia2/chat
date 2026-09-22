# Variáveis de ambiente de produção: onde moram e o que não pode sumir

As duas stacks (Hub2You e Autonomia) leem o ambiente de um parâmetro seguro do SSM,
`/chatwoot/prod/env` (SecureString), na conta AWS de cada uma. O Terraform cria o
parâmetro (`infra/aws-chatwoot*/ec2.tf`, recurso `aws_ssm_parameter.chatwoot_ec2_env`),
mas **não guarda o conteúdo**: os valores foram postos no parâmetro e vivem só lá.

A cada deploy, os workflows `deploy-*-blue-green.yml` leem o parâmetro, acrescentam as
flags de runtime obrigatórias e gravam de volta (passo "Ensure ... runtime flags"). Todo
o resto do conteúdo, segredos inclusive, é preservado como estava.

## Chaves de criptografia (não podem sumir nem mudar)

```
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT
```

- Cifram no banco as credenciais de canal: senhas IMAP/SMTP das caixas de e-mail e os
  tokens de Instagram, Telegram, TikTok, Line, SMS (Twilio) e das importações de dados
  (`encrypts` nos models de `app/models/channel/` e `app/models/data_import.rb`).
- **Perder ou trocar essas chaves deixa essas credenciais ilegíveis.** Os canais param
  de funcionar e só voltam reconectando um por um.
- Conferido em 22/09/2026 (só nomes, sem ler valores): as três existem nas duas stacks;
  4 caixas de e-mail no Hub2You e 1 na Autonomia dependem delas.

## Cuidados

- Nunca reescrever `/chatwoot/prod/env` do zero. Mudança é cirúrgica: ler, editar a
  linha, gravar, e comparar o conjunto de chaves antes e depois.
- O SSM guarda as **100 últimas versões** do parâmetro, e o deploy cria uma versão nova a
  cada rodada. Apagar o parâmetro apaga o histórico junto. A cópia de segurança dos
  valores tem de existir fora do SSM, num cofre de segredos, com acesso restrito.
- Ambiente novo (stack nova, restauração): copiar as três chaves do ambiente antigo.
  Gerar chaves novas só vale para banco novo, sem dado cifrado.

## Verificação em duas etapas

`Chatwoot.mfa_enabled?` (`config/application.rb`) liga a verificação em duas etapas do
perfil quando as chaves existem **e** a instalação não usa o login único automático
(`AUTONOMIA_SSO_AUTO_REDIRECT`). Nas duas stacks o login único automático está ligado,
então a verificação não aparece: a entrada pelo login único não passa por ela, e quem
entra assim não teria senha para desligá-la depois.
