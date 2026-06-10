-- ============================================================
-- QUERY 06: Produtos com Estoque Baixo e Último Movimento
-- ============================================================
-- PERGUNTA DE NEGÓCIO:
--   Quais tamanhos de produto estão com estoque abaixo do mínimo?
--   Quando foi a última movimentação de cada um?
--   Informação crucial para reposição de estoque.
--
-- TABELAS ENVOLVIDAS (3):
--   ProductSize, Product, StockMovement
--
-- TÉCNICA: Subquery correlacionada + JOIN + filtro condicional
--
-- EXPLICAÇÃO:
--   Unimos ProductSize com Product para identificar o produto.
--   Para cada linha, usamos uma subquery correlacionada que busca
--   a data da movimentação mais recente daquele ProductSize na
--   tabela StockMovement. Filtramos apenas os tamanhos cujo estoque
--   está abaixo do mínimo definido (minStock). Subqueries correlacionadas
--   são executadas uma vez por linha da query externa.
-- ============================================================

SELECT
    p.name                      AS produto,
    ps.size                     AS tamanho,
    ps.stock                    AS estoque_atual,
    ps."minStock"               AS estoque_minimo,
    (ps."minStock" - ps.stock)  AS deficit,
    (
        SELECT MAX(sm."createdAt")
        FROM "StockMovement" sm
        WHERE sm."productSizeId" = ps.id
    ) AS ultimo_movimento
FROM "ProductSize" ps
INNER JOIN "Product" p ON p.id = ps."productId"
WHERE ps.stock < ps."minStock"
ORDER BY deficit DESC, p.name;
