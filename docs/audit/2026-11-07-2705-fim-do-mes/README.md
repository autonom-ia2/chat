# #2705 · "fim do mês" na peça de data: conferência visual (07/11/2026)

O componente real (`LivreData.vue`) renderizado com o Tailwind e o i18n pt_BR do projeto, num Vite mínimo, com captura
pelo Chrome headless. Valor: hoje + 1 mês, no fim do mês.

- `desktop-fechado.png`: 1280 px, a pergunta "Que dia desse mês?" e a frase "Grava: hoje + 1 mês, no fim do mês".
- `desktop-aberto.png`: 1280 px, a escolha aberta ("O próprio dia calculado" / "O último dia do mês").
- `celular-390.png`: 390 px, a escolha aberta.

Achado na conferência: o campo "Quantos" ficava com a borda vermelha com qualquer número, porque o `LivreData` passava
`message-type="error"` sempre ao `Input`. Agora só o número que não vale fica vermelho (mesmo PR).
