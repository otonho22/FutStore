-- ============================================================
-- QUERY 04: Produtos Sem Nenhuma Avaliação
-- ============================================================
-- PERGUNTA DE NEGÓCIO:
--   Quais produtos ainda não receberam nenhuma avaliação
--   dos clientes? Ajuda a direcionar campanhas de pós-venda
--   pedindo reviews.
--
-- TABELAS ENVOLVIDAS (3):
--   Product, Review, Category
--
-- TÉCNICA: LEFT JOIN + IS NULL (anti-join)
--
-- EXPLICAÇÃO:
--   Usamos LEFT JOIN entre Product e Review. Quando o LEFT JOIN
--   não encontra correspondência, Review.id fica NULL.
--   Filtramos exatamente esses casos com WHERE r.id IS NULL.
--   Também incluímos Category para mostrar a que categoria pertence
--   cada produto sem avaliação. Essa técnica (anti-join) é uma das
--   mais importantes em SQL para encontrar "ausências".
-- ============================================================

SELECT
    p.name      AS produto,
    p.team      AS time,
    c.name      AS categoria,
    p.price     AS preco,
    p."salesCount" AS vendas
FROM "Product" p
LEFT JOIN "Review" r   ON r."productId" = p.id
INNER JOIN "Category" c ON c.id = p."categoryId"
WHERE r.id IS NULL
  AND p.active = true
ORDER BY p."salesCount" DESC;
