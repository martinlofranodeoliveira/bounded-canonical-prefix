# Bounded Canonical Prefix (PT-BR)

Versão de desenvolvimento `0.1.0` — biblioteca e CLI em Nim (`>= 2.0`) para tabelas Huffman canônicas com comprimento limitado ($L \in [1, 16]$), otimização determinística por package-merge (Larmore–Hirschberg), formato binário explícito de demonstração (`BCP1`) e consumidor/verificador nativo independente em C11.

Desenvolvido por [Lofrano Tecnologia](https://lofranotecnologia.com.br). [English version](README.md).

## Visão Geral

- **Package-Merge determinístico**: minimiza $\sum f_i \ell_i$ sujeito a $1 \le \ell_i \le L$ e $\sum 2^{-\ell_i} = 1$, com desempate determinístico.
- **Aritmética inteira verificada**: frequências por símbolo até $2^{40}$ e soma até $2^{48}$.
- **Orçamentos explícitos**: nós de pacotes (`65.536`) e operações (`1.000.000`), retornando `UNKNOWN_BUDGET` se excedidos.
- **Formato BCP1**: cabeçalho de 268 bytes (`"BCP1"`, `decoded_length`, `meaningful_bits`, 256 comprimentos de código) e payload compacto verificado por consumidor C11 independente.

## Como Executar

```sh
/bin/sh scripts/test-offline.sh
/bin/sh scripts/demo-offline.sh --assert
/bin/sh scripts/demo-offline.sh --assert --json
```

## Limitações e Exclusões de Escopo

- `BCP1` é um formato estrito de demonstração; não implementa DEFLATE, gzip ou ZIP.
- Não inclui checksum criptográfico ou autenticação de mensagens.

## Licença

MIT — Copyright (c) 2026 Lofrano Tecnologia. Consulte [LICENSE](LICENSE).
