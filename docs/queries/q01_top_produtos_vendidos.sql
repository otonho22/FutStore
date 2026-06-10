-- ============================================================
-- QUERY 01: Top 10 Produtos Mais Vendidos por Categoria
-- ============================================================
-- PERGUNTA DE NEGÓCIO:
--   Quais são os 10 produtos mais vendidos da loja,
--   mostrando a categoria e a marca de cada um?
--
-- TABELAS ENVOLVIDAS (3):
--   Product, Category, Brand
--
-- TÉCNICA: INNER JOIN + ORDER BY + LIMIT
--
-- EXPLICAÇÃO:
--   Esta consulta une a tabela Product com Category (para obter
--   o nome da categoria) e Brand (para obter a marca).
--   Ordena pelo campo salesCount de forma decrescente e limita
--   aos 10 primeiros resultados. Isso permite ao gestor da loja
--   identificar rapidamente quais camisas são mais populares.
-- ============================================================

SELECT
    p.name          AS produto,
    p.team          AS time,
    c.name          AS categoria,
    b.name          AS marca,
    p."salesCount"  AS total_vendas,
    p.price         AS preco
FROM "Product" p
INNER JOIN "Category" c ON c.id = p."categoryId"
INNER JOIN "Brand" b    ON b.id = p."brandId"
WHERE p.active = true
ORDER BY p."salesCount" DESC
LIMIT 10;
