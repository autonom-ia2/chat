#!/usr/bin/env python3
"""Regenera as duas tabelas oficiais das ferramentas prontas (#2858, F4) a partir da fonte.

- lib/ferramentas_prontas/procedimentos.csv: a TUSS 22 da ANS (só os termos em vigor, código de 8 dígitos);
- lib/ferramentas_prontas/doencas.csv: a CID-10 do DATASUS (categorias e subcategorias, sem o ponto).

Roda todo dia no GitHub Actions (.github/workflows/ferramentas-prontas-tabelas.yml), que abre um PR quando um CSV muda.
Também roda à mão, da raiz do repositório: python3 scripts/ferramentas-prontas/atualizar_tabelas.py

Nada vai para o repositório se a fonte parecer quebrada: arquivo grande demais, tabela que encolheu demais ou código
fora do formato derrubam o script (saída diferente de zero) e o job fica vermelho, sem PR. Só biblioteca padrão.
"""

import csv
import hashlib
import io
import os
import sys
import urllib.request
import zipfile
from datetime import datetime, timezone

LIB = os.path.join('lib', 'ferramentas_prontas')
MAX_ZIP = 10 * 1024 * 1024
MAX_ARQUIVO = 30 * 1024 * 1024
PRAZO = 120
AGENTE = 'Autonomia-FerramentasProntas/1.0 (atualizacao de tabelas oficiais)'

TABELAS = [
    {
        'nome': 'TUSS 22 (ANS)',
        'url': 'https://dadosabertos.ans.gov.br/FTP/PDA/terminologia_unificada_saude_suplementar_TUSS-049/pda-049-tuss.zip',
        'csv': 'procedimentos.csv',
        'licenca': 'LICENCA-procedimentos-tuss.txt',
        'minimo': 4000,
        'encolher_ate': 0.8,
    },
    {
        'nome': 'CID-10 (DATASUS)',
        # O DATASUS só serve este arquivo por http. A conferência de formato e de tamanho abaixo é a proteção.
        'url': 'http://www2.datasus.gov.br/cid10/V2008/downloads/CID10CSV.zip',
        'csv': 'doencas.csv',
        'licenca': 'LICENCA-doencas-cid10.txt',
        'minimo': 12000,
        'encolher_ate': 0.95,
    },
]


class FonteQuebrada(Exception):
    pass


def baixar(url):
    pedido = urllib.request.Request(url, headers={'User-Agent': AGENTE})
    with urllib.request.urlopen(pedido, timeout=PRAZO) as resposta:  # noqa: S310 (URL fixa, da lista acima)
        corpo = resposta.read(MAX_ZIP + 1)
    if len(corpo) > MAX_ZIP:
        raise FonteQuebrada(f'{url}: zip maior que {MAX_ZIP} bytes')
    return corpo


def ler_do_zip(corpo, nome_do_arquivo, codificacao):
    with zipfile.ZipFile(io.BytesIO(corpo)) as arquivo:
        info = arquivo.getinfo(nome_do_arquivo)
        if info.file_size > MAX_ARQUIVO:
            raise FonteQuebrada(f'{nome_do_arquivo}: aberto, passa de {MAX_ARQUIVO} bytes')
        return arquivo.read(info).decode(codificacao)


def tuss(corpo):
    texto = ler_do_zip(corpo, 'pda-049-tabela_22_procedimentos_e_eventos_em_saude.csv', 'utf-8-sig')
    termos = {}
    for linha in csv.DictReader(io.StringIO(texto), delimiter=';'):
        codigo = (linha.get('CD_TERMO') or '').strip()
        nome = ' '.join((linha.get('NM_TERMO') or '').split())
        if (linha.get('DT_FIM_VIGENCIA') or '').strip() or not nome:
            continue
        if not (codigo.isdigit() and len(codigo) == 8):
            raise FonteQuebrada(f'TUSS: código fora do formato: {codigo!r}')
        termos.setdefault(codigo, nome)
    return termos


def cid10(corpo):
    termos = {}
    for arquivo, coluna in (('CID-10-CATEGORIAS.CSV', 'CAT'), ('CID-10-SUBCATEGORIAS.CSV', 'SUBCAT')):
        texto = ler_do_zip(corpo, arquivo, 'latin-1')
        for linha in csv.DictReader(io.StringIO(texto), delimiter=';'):
            codigo = (linha.get(coluna) or '').strip().upper()
            nome = ' '.join((linha.get('DESCRICAO') or '').split())
            if not codigo or not nome:
                continue
            if not (len(codigo) in (3, 4) and codigo[0].isalpha() and codigo[1:].isdigit()):
                raise FonteQuebrada(f'CID-10: código fora do formato: {codigo!r}')
            termos.setdefault(codigo, nome)
    return termos


LEITORES = {'procedimentos.csv': tuss, 'doencas.csv': cid10}


def atuais(caminho):
    if not os.path.exists(caminho):
        return {}
    with open(caminho, encoding='utf-8', newline='') as arquivo:
        return {linha['codigo']: linha['nome'] for linha in csv.DictReader(arquivo, delimiter=';')}


def gravar(caminho, termos):
    with open(caminho, 'w', encoding='utf-8', newline='') as arquivo:
        escritor = csv.writer(arquivo, delimiter=';', lineterminator='\n')
        escritor.writerow(['codigo', 'nome'])
        for codigo in sorted(termos):
            escritor.writerow([codigo, termos[codigo]])


def milhar(numero):
    return f'{numero:,}'.replace(',', '.')


def anotar_licenca(caminho, corpo, linhas):
    """Troca, no arquivo de origem, a linha do download (data, tamanho, sha256) e a contagem de linhas."""
    with open(caminho, encoding='utf-8') as arquivo:
        texto = arquivo.read()
    hoje = datetime.now(timezone.utc).strftime('%d/%m/%Y')
    sha = hashlib.sha256(corpo).hexdigest()
    novo = []
    for linha in texto.split('\n'):
        if linha.startswith('Baixado em '):
            linha = f'Baixado em {hoje} ({milhar(len(corpo))} bytes, sha256 {sha}).'
        novo.append(linha)
    texto = '\n'.join(novo)
    marcador = ' linhas.'
    fim = texto.find(marcador)
    inicio = texto.rfind(' ', 0, fim)
    if fim > 0 and inicio > 0:
        texto = texto[:inicio + 1] + milhar(linhas) + texto[fim:]
    with open(caminho, 'w', encoding='utf-8') as arquivo:
        arquivo.write(texto)


def sha_registrado(caminho):
    """O sha256 do zip anotado na linha "Baixado em ... sha256 <hex>)." do arquivo de origem (vazio se não houver)."""
    if not os.path.exists(caminho):
        return ''
    with open(caminho, encoding='utf-8') as arquivo:
        for linha in arquivo:
            if linha.startswith('Baixado em ') and 'sha256 ' in linha:
                return linha.split('sha256 ', 1)[1].split(')', 1)[0].strip()
    return ''


def resumo(nome, antes, depois, sha_antes, sha_depois):
    novos = sorted(set(depois) - set(antes))
    saidos = sorted(set(antes) - set(depois))
    mudados = sorted(codigo for codigo in set(antes) & set(depois) if antes[codigo] != depois[codigo])
    partes = [f'- **{nome}**: {len(antes)} → {len(depois)} linhas; {len(novos)} novas, {len(saidos)} saíram, '
              f'{len(mudados)} mudaram de nome.']
    partes.append(f'  - zip: sha256 `{sha_antes or "(sem registro)"}` → `{sha_depois}`')
    for titulo, codigos in (('Novas', novos), ('Saíram', saidos)):
        if codigos:
            amostra = ', '.join(codigos[:15]) + (' …' if len(codigos) > 15 else '')
            partes.append(f'  - {titulo}: {amostra}')
    # O nome que mudou vai inteiro, antes e depois: é o que chega ao agente, e ninguém lê um diff de milhares de linhas.
    # A CID-10 vem por http, então esta é a conferência de que nada foi trocado no caminho.
    if mudados:
        partes.append('  - Mudaram (antes → depois):')
        for codigo in mudados[:30]:
            partes.append(f'    - {codigo}: {antes[codigo]} → {depois[codigo]}')
        if len(mudados) > 30:
            partes.append(f'    - … e mais {len(mudados) - 30}')
    return '\n'.join(partes)


def main():
    mudancas = []
    for tabela in TABELAS:
        caminho = os.path.join(LIB, tabela['csv'])
        licenca = os.path.join(LIB, tabela['licenca'])
        corpo = baixar(tabela['url'])
        sha_antes = sha_registrado(licenca)
        sha_depois = hashlib.sha256(corpo).hexdigest()
        depois = LEITORES[tabela['csv']](corpo)
        antes = atuais(caminho)
        if len(depois) < tabela['minimo'] or (antes and len(depois) < len(antes) * tabela['encolher_ate']):
            raise FonteQuebrada(f"{tabela['nome']}: {len(depois)} linhas (antes {len(antes)}): a fonte parece quebrada")
        if depois == antes:
            if sha_antes and sha_antes != sha_depois:
                print(f"::warning::{tabela['nome']}: o zip mudou (sha256 {sha_depois}) e a tabela ficou igual")
            print(f"{tabela['nome']}: igual ({len(depois)} linhas)")
            continue
        gravar(caminho, depois)
        anotar_licenca(licenca, corpo, len(depois))
        mudancas.append(resumo(tabela['nome'], antes, depois, sha_antes, sha_depois))
        print(f"{tabela['nome']}: mudou ({len(antes)} → {len(depois)} linhas)")

    saida = os.environ.get('GITHUB_OUTPUT')
    corpo_do_pr = os.environ.get('CORPO_DO_PR')
    if saida:
        with open(saida, 'a', encoding='utf-8') as arquivo:
            arquivo.write(f"mudou={'true' if mudancas else 'false'}\n")
    if corpo_do_pr and mudancas:
        with open(corpo_do_pr, 'w', encoding='utf-8') as arquivo:
            arquivo.write('\n\n'.join(mudancas) + '\n')


if __name__ == '__main__':
    try:
        main()
    except (FonteQuebrada, KeyError, zipfile.BadZipFile, OSError) as erro:
        print(f'::error::{type(erro).__name__}: {erro}', file=sys.stderr)
        sys.exit(1)
