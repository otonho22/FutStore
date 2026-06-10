-- ============================================================
-- QUERY 02: Receita Total por Marca nos Últimos 3 Meses
-- ============================================================
-- PERGUNTA DE NEGÓCIO:
--   Qual marca (Nike, Adidas, Puma...) gerou mais receita
--   nos últimos 3 meses? Isso ajuda na negociação com fornecedores.
--
-- TABELAS ENVOLVIDAS (4):
--   Brand, Product, OrderItem, Order
--
-- TÉCNICA: JOIN de 4 tabelas + GROUP BY + SUM + filtro de data
--
-- EXPLICAÇÃO:
--   Partimos da tabela Brand e percorremos Brand → Product → OrderItem → Order.
--   Filtramos apenas pedidos dos últimos 3 meses (excluindo cancelados).
--   Agrupamos por marca e somamos (quantidade × preço unitário) de cada item
--   para obter a receita total. O resultado mostra qual marca gera mais faturamento.
-- ============================================================

SELECT
    b.name                                          AS marca,
    COUNT(DISTINCT o.id)                            AS total_pedidos,
    SUM(oi.quantity)                                AS itens_vendidos,
    ROUND(SUM(oi."unitPrice" * oi.quantity)::NUMERIC, 2) AS receita_total
FROM "Brand" b
INNER JOIN "Product" p   ON p."brandId" = b.id
INNER JOIN "OrderItem" oi ON oi."productId" = p.id
INNER JOIN "Order" o      ON o.id = oi."orderId"
WHERE o."createdAt" >= NOW() - INTERVAL '3 months'
  AND o.status != 'cancelado'
GROUP BY b.name
ORDER BY receita_total DESC;
