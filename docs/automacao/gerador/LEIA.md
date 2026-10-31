# Gerador da página de aceite (#2414)

A página `../termos-de-aceite.html` e o documento `../termos-de-aceite-F1-F9.md` saem dos mesmos dados. Não edite os dois à mão.

- Fases e itens de aceite: `FASES` em `gera_termos.py`.
- Exemplos: `exemplos20.py`.
- Visual: `termos_tpl.html`.

Para gerar:

```sh
cd docs/automacao/gerador
python3 gera_termos.py termos_tpl.html ../termos-de-aceite.html
python3 gera_md.py
```
