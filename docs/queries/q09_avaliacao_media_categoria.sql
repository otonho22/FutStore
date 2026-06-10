-- ============================================================
-- QUERY 09: Ranking de Avaliação Média por Categoria
-- ============================================================
-- PERGUNTA DE NEGÓCIO:
--   Qual a avaliação média dos produtos em cada categoria?
--   E qual o ranking dos produtos mais bem avaliados dentro
--   de cada categoria?
--
-- TABELAS ENVOLVIDAS (3):
--   Review, Product, Category
--
-- TÉCNICA: Window Function (RANK() OVER) + GROUP BY + AVG
--
-- EXPLICAÇÃO:
--   Primeiro, calculamos a média de avaliação por produto
--   (agrupando reviews por productId). Depois usamos a Window
--   Function RANK() OVER (PARTITION BY categoria ORDER BY média DESC)
--   para atribuir um ranking dentro de cada categoria.
--   Window Functions permitem calcular valores agregados sem
--   colapsar as linhas, diferente do GROUP BY puro. O PARTITION BY
--   reinicia o ranking para cada categoria.
-- ============================================================

WITH produto_avaliacao AS (
    SELECT
        p.id                            AS produto_id,
        p.name                          AS produto,
        c.name                          AS categoria,
        COUNT(r.id)                     AS total_avaliacoes,
        ROUND(AVG(r.rating)::NUMERIC, 2) AS media_nota
    FROM "Review" r
    INNER JOIN "Product" p  ON p.id = r."productId"
    INNER JOIN "Category" c ON c.id = p."categoryId"
    GROUP BY p.id, p.name, c.name
    HAVING COUNT(r.id) >= 2
)
SELECT
    categoria,
    produto,
    total_avaliacoes,
    media_nota,
    RANK() OVER (PARTITION BY categoria ORDER BY media_nota DESC) AS ranking_na_categoria
FROM produto_avaliacao
ORDER BY categoria, ranking_na_categoria;
