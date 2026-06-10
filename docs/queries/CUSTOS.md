# Análise de Custo das Consultas — FutStore

> Gerado com `EXPLAIN (ANALYZE, BUFFERS)` no PostgreSQL 18.
> Base com ~109 produtos, 120 usuários, 120 pedidos, 149 reviews.

## Tabela Resumo

| Query | Descrição | Total Cost | Planning (ms) | Execution (ms) | Linhas | Observações |
|-------|-----------|-----------|---------------|-----------------|--------|-------------|
| Q01 | Top 10 produtos vendidos | 5.29 | 15.0 | 0.16 | 10 | Index Scan no salesCount — muito eficiente |
| Q02 | Receita por marca (3 meses) | 53.59 | 59.0 | 1.08 | 4 | Hash Join em 4 tabelas; Seq Scan em OrderItem |
| Q03 | Clientes VIP (>R$1000) | 32.84 | 32.3 | 0.67 | 47 | HAVING filtra após agregação; Hash Join eficiente |
| Q04 | Produtos sem avaliação | 18.97 | 46.9 | 0.68 | 29 | Anti-join via Hash Right Join + IS NULL |
| Q05 | Cupons mais usados | 24.46 | 35.8 | 0.86 | 5 | Memoize no Coupon_code_key — cache efetivo |
| Q06 | Estoque baixo + último mov. | 1236.52 | 30.8 | 0.71 | 25 | Subquery correlacionada infla o custo estimado |
| Q07 | Pedido completo (5 tabelas) | 22.92 | 75.3 | 0.65 | 20 | 5 Nested Loops com Index Scan — excelente |
| Q08 | Wishlist não comprada | 57.43 | 98.8 | 1.35 | 20 | NOT EXISTS via Hash Right Anti Join |
| Q09 | Avaliação média por categoria | 34.10 | 41.8 | 1.22 | 42 | Window Function (RANK) + Incremental Sort |
| Q10 | Usuários ativos vs inativos | 43.83 | 42.9 | 1.74 | 30 | CTE + Hash Right Join + HashAggregate |

## Análise Detalhada por Query

### Q01 — Top 10 Produtos Mais Vendidos
- **Custo total:** 5.29
- **Estratégia:** Nested Loop com Index Scan Backward no índice `Product_salesCount_idx`
- **Ponto forte:** O PostgreSQL usa o índice de salesCount para ler direto os top 10 sem ordenar — custo mínimo
- **Buffer hits:** 19 (tudo em cache/memória)
- **Memoize:** Cache no Category e Brand PKs (hits: 7/10 cada) — evita releituras

### Q02 — Receita por Marca nos Últimos 3 Meses
- **Custo total:** 53.59
- **Estratégia:** Hash Join encadeado (OrderItem → Order → Product → Brand)
- **Gargalo:** Seq Scan em OrderItem (248 linhas) e Order (120 linhas) — tabelas pequenas, não justifica índice extra
- **Filtro temporal:** `createdAt >= NOW() - 3 months` remove 69 dos 120 pedidos
- **GroupAggregate:** Agrupamento por marca após sort

### Q03 — Clientes VIP (Gastaram > R$1.000)
- **Custo total:** 32.84
- **Estratégia:** Hash Join (Order → User) + Hash Right Join (User → Address)
- **HAVING:** Aplicado após HashAggregate — remove 26 dos 73 grupos
- **Address filter:** `isDefault = true` remove 91 de 211 endereços via Seq Scan

### Q04 — Produtos Sem Nenhuma Avaliação
- **Custo total:** 18.97
- **Estratégia:** Hash Right Join entre Review e Product, filtrando `r.id IS NULL`
- **Anti-join:** 149 reviews removidas pelo filtro, restam 29 produtos sem avaliação
- **Index Scan:** Category_pkey usado para cada produto restante (29 buscas)

### Q05 — Ranking de Cupons Mais Utilizados
- **Custo total:** 24.46
- **Estratégia:** Nested Loop com Memoize no Coupon_code_key
- **Memoize efetivo:** 108 hits de 114 lookups (5 códigos distintos de cupom)
- **Join por texto:** couponCode (string) não é FK — funciona via índice UNIQUE

### Q06 — Produtos com Estoque Baixo
- **Custo total estimado:** 1236.52 (alto!)
- **Custo real de execução:** 0.71ms (baixo!)
- **Motivo da diferença:** Subquery correlacionada — o otimizador estima custo alto porque prevê N execuções, mas na prática executa apenas 25 (linhas com estoque baixo)
- **Sugestão de otimização:** Substituir subquery por LEFT JOIN LATERAL para custo estimado mais preciso

### Q07 — Detalhes Completos do Pedido (5 tabelas)
- **Custo total:** 22.92
- **Estratégia:** 5 Nested Loops encadeados com Index Scan em cada tabela
- **Destaques:** Index Scan Backward em Order_createdAt_idx + Memoize em User e Product PKs
- **Eficiência exemplar:** JOIN de 5 tabelas com custo muito baixo graças aos índices

### Q08 — Wishlist Não Comprada (NOT EXISTS)
- **Custo total:** 57.43
- **Estratégia:** Hash Right Anti Join — PostgreSQL otimiza NOT EXISTS automaticamente
- **4 tabelas envolvidas:** Wishlist ↔ User, Order ↔ OrderItem
- **Top-N heapsort:** Ordena apenas os 20 primeiros resultados (memory: 29kB)

### Q09 — Avaliação Média por Categoria (Window Function)
- **Custo total:** 34.10
- **Estratégia:** HashAggregate (média por produto) → WindowAgg (RANK por categoria) → Incremental Sort
- **Window Function:** `RANK() OVER (PARTITION BY categoria ORDER BY media_nota DESC)`
- **Incremental Sort:** Reusa presorted key (categoria) — sort parcial mais eficiente

### Q10 — Usuários Ativos vs Inativos (CTE)
- **Custo total:** 43.83
- **Estratégia:** CTE inline (resumo_usuario) via Hash Right Join + HashAggregate externo
- **CTE materialize:** PostgreSQL 12+ pode inline CTEs — aqui é inlined como subquery
- **CASE classification:** Avaliado após agregação, custo desprezível
