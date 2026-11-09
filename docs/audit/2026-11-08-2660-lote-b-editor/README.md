# #2660 lote B · as ações novas no editor: conferência visual (08/11/2026)

Os componentes reais do editor (`LivreSeletorPasso.vue` e `LivreAlterar.vue`), com o Tailwind, o i18n pt_BR e o
catálogo gerado (`automacao-passos.json`) desta branch, num Vite mínimo. Captura pelo Chrome headless: 1440 px pela
janela e 390 px pela emulação de celular (DevTools). A lista de campos personalizados aparece vazia porque a captura
não carrega os campos de uma conta.

- `seletor-*.png`: o "+" do editor. "Criar o contato do card" entra em Funil; "Criar um contato", "Criar uma empresa" e
  "Marcar o contato como cliente" entram em Contato e empresa.
- `contato_criar-*.png`: nome, e-mail, telefone, empresa e campos personalizados, como no "Atualizar o contato".
- `empresa_criar-*.png`: nome (obrigatório: o "Salvar" espera), descrição, site e campos personalizados.
- `contato_cliente-*.png`: não pede nada; o painel diz "Este passo não pede nada. É só salvar." (antes abria vazio).
- `card_contato_criar-*.png`: nome, e-mail, telefone e campos personalizados do contato que nasce ligado ao card.

Ficam no Guia, fora do editor, com o motivo no `automacao-passos.yml` (`so_guia`): pôr o contato na empresa (o editor
já faz pelo "Atualizar o contato", campo Empresa), ligar e desligar contato e conversa do card, restaurar card e os
três fatos da memória. Nenhum dos 20 exemplos dos termos usa essas ações.
