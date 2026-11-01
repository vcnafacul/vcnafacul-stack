#!/usr/bin/env python3
"""Confere os .env antes do modo homol.

No modo homol os bancos e o bucket vêm do `.env` de cada repo. Um endereço
`localhost` ali não leva a nada dentro do container (é o próprio container),
então o serviço sobe e quebra na primeira consulta. Este script falha antes.

Uso: conferir-modo-homol.py <pasta-raiz-dos-repos>
"""
import sys
from pathlib import Path

# repo -> variáveis de dados que precisam apontar para fora
VARIAVEIS = {
    "api-vcnafacul": ["MY_HOST", "AWS_ENDPOINT"],
    "ms-simulado": ["MONGODB", "AWS_ENDPOINT"],
    "vcnafacul-form": ["MONGODB"],
    "ms-omr": ["AWS_ENDPOINT"],
}
LOCAIS = ("localhost", "127.0.0.1", "0.0.0.0")
# O MySQL de homol e o de produção ficam no mesmo servidor da Hostinger; só o
# nome do banco muda. Homol termina em _hml (ver CLAUDE.md).
SUFIXO_HOMOL_MYSQL = "_hml"


def ler_env(caminho: Path) -> dict:
    """Leitura simples de .env: última definição vence, como no dotenv do compose."""
    valores = {}
    for linha in caminho.read_text().splitlines():
        linha = linha.strip()
        if not linha or linha.startswith("#") or "=" not in linha:
            continue
        chave, valor = linha.split("=", 1)
        chave = chave.removeprefix("export ").strip()
        valores[chave] = valor.strip().strip("'\"")
    return valores


def main() -> int:
    raiz = Path(sys.argv[1] if len(sys.argv) > 1 else "..")
    erros = []
    for repo, variaveis in VARIAVEIS.items():
        env = ler_env(raiz / repo / ".env")
        for var in variaveis:
            valor = env.get(var, "")
            if not valor:
                erros.append(f"  {repo}/.env: {var} não definido")
            elif any(local in valor for local in LOCAIS):
                erros.append(f"  {repo}/.env: {var} aponta para {valor.split('@')[-1]}")
    banco = ler_env(raiz / "api-vcnafacul" / ".env").get("MY_DB_NAME", "")
    if not banco.endswith(SUFIXO_HOMOL_MYSQL):
        erros.append(
            f"  api-vcnafacul/.env: MY_DB_NAME={banco or '(vazio)'} não é o banco de homol "
            f"(termina em {SUFIXO_HOMOL_MYSQL}) — pode ser produção"
        )
    if erros:
        print("❌ modo homol precisa de bancos/bucket remotos nos .env:")
        print("\n".join(erros))
        print("   → ajuste esses .env para homol, ou use o modo local (make up)")
        return 1
    print("✔ .env apontam para fora")
    print("\033[31m⚠ MODO HOMOL: tudo o que você fizer escreve nos bancos de homol\033[0m")
    return 0


if __name__ == "__main__":
    sys.exit(main())
